const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

/// Signature required by `registerFunc`. Arguments are read off the Lua stack
/// by index (1-based); the return value is the number of values pushed back
/// onto the stack for Lua to receive.
pub const LuaFunc = fn (*Lua) i32;

/// Wraps a Lua 5.3 state (via `ziglua`) with the standard libraries opened.
/// Owns the underlying `*Lua`; call `deinit()` to close it.
pub const ScriptEngine = struct {
    lua: *Lua,

    /// Creates a new Lua state and opens the standard libraries (string,
    /// table, math, etc).
    pub fn init(allocator: std.mem.Allocator) !ScriptEngine {
        var lua = try Lua.init(allocator);
        lua.openLibs();
        return .{ .lua = lua };
    }

    pub fn deinit(self: *ScriptEngine) void {
        self.lua.deinit();
    }

    /// Registers `func` as a global Lua function named `name`. Prefer
    /// stateless functions here; use a context struct (see
    /// `sequencer.SeqScriptingContext`) when the function needs to touch
    /// engine state.
    pub fn registerFunc(self: *ScriptEngine, name: [:0]const u8, comptime func: LuaFunc) !void {
        self.lua.pushFunction(ziglua.wrap(func));
        self.lua.setGlobal(name);
    }

    /// Compiles and runs an inline Lua code string. On a syntax or runtime
    /// error, logs the Lua error message and returns `error.SyntaxError` /
    /// `error.ScriptError`.
    pub fn run(self: *ScriptEngine, code: [:0]const u8) !void {
        // Compile a line of Lua code
        self.lua.loadString(code) catch {
            // If there was an error, Lua will place an error string on the top of the stack.
            // Here we print out the string to inform the user of the issue.
            std.log.err("{s}\n", .{self.lua.toString(-1) catch unreachable});

            // Remove the error from the stack and go back to the prompt
            self.lua.pop(1);
            return error.SyntaxError;
        };

        // Execute a line of Lua code
        self.lua.protectedCall(.{ .args = 0, .results = 0, .msg_handler = 0 }) catch {
            // Error handling here is the same as above.
            std.log.err("{s}\n", .{self.lua.toString(-1) catch unreachable});
            self.lua.pop(1);
            return error.ScriptError;
        };
    }

    /// Runs a Lua file from disk. Raises the same errors as `run()` on
    /// syntax or runtime failure.
    pub fn runScript(self: *ScriptEngine, file: [:0]const u8) !void {
        try self.lua.doFile(file);
    }

    /// Reads the global Lua table named `globalName` into a Zig struct `T`.
    /// `T` must be default-constructible (`.{}`) and every field must be
    /// present in the Lua table with a matching type — a missing field or a
    /// type mismatch returns `error.InvalidFieldType`, it does not fall back
    /// to the Zig default. Supported field types: `bool`, `int`, `float`,
    /// and `?[]u8` (heap-allocated with the Lua allocator; caller frees it,
    /// e.g. via the struct's own `deinit`). Any other field type returns
    /// `error.UnsupportedFieldType`; a missing or non-table global returns
    /// `error.InvalidConfigTable`.
    pub fn loadStruct(
        self: *const ScriptEngine,
        comptime T: type,
        globalName: [:0]const u8,
    ) !T {
        // Push the global `config` table onto the stack
        _ = try self.lua.getGlobal(globalName);

        // Ensure the global `config` is a table
        if (!self.lua.isTable(-1)) {
            self.lua.pop(1); // Pop the `config` table
            return error.InvalidConfigTable;
        }

        var myStruct: T = .{};
        // Iterate over fields of the struct at comptime
        inline for (@typeInfo(T).@"struct".fields) |field| {
            const field_name = field.name;

            // Get the value from Lua
            _ = self.lua.getField(-1, field_name); // Pushes `config.<field_name>` onto the stack

            // Match the field type and retrieve the value
            switch (@typeInfo(field.type)) {
                // Handle booleans
                .bool => {
                    if (!self.lua.isBoolean(-1)) {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidFieldType;
                    }
                    @field(myStruct, field_name) = self.lua.toBoolean(-1);
                },
                .int => {
                    if (!self.lua.isInteger(-1)) {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidFieldType;
                    }
                    @field(myStruct, field_name) = @intCast(try self.lua.toInteger(-1));
                },
                .float => {
                    if (!self.lua.isNumber(-1)) {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidFieldType;
                    }
                    @field(myStruct, field_name) = @floatCast(try self.lua.toNumber(-1));
                },
                .optional => |opt| {
                    switch (@typeInfo(opt.child)) {
                        .pointer => |ptr_info| switch (ptr_info.size) {
                            .slice => {
                                if (ptr_info.child != u8) {
                                    return error.UnsupportedFieldType;
                                }

                                const lua_str = try self.lua.toString(-1);
                                const len: usize = self.lua.rawLen(-1);
                                const buffer = try self.lua.allocator().alloc(u8, len);
                                @memcpy(buffer, lua_str[0..len]);
                                @field(myStruct, field_name) = buffer;
                            },
                            else => {
                                return error.UnsupportedFieldType;
                            },
                        },
                        else => {
                            return error.UnsupportedFieldType;
                        },
                    }
                },
                // Add more cases for other types as needed
                else => {
                    self.lua.pop(2); // Pop the value and table
                    return error.UnsupportedFieldType;
                },
            }

            // Pop the value, keep the table
            self.lua.pop(1);
        }

        // Pop the global `config` table
        self.lua.pop(1);

        return myStruct;
    }
};
