const std = @import("std");
const ziglua = @import("ziglua");
const paths = @import("./paths.zig");

const Lua = ziglua.Lua;

/// Signature required by `registerFunc`. Arguments are read off the Lua stack
/// by index (1-based); the return value is the number of values pushed back
/// onto the stack for Lua to receive.
pub const LuaFunc = fn (*Lua) i32;

/// Wraps a Lua 5.3 state (via `ziglua`) with the standard libraries opened.
/// Owns the underlying `*Lua`; call `deinit()` to close it.
pub const ScriptEngine = struct {
    lua: *Lua,
    /// Kept for resolving script paths in `runScript`; the Lua state has its
    /// own copy for its internal allocations.
    alloc: std.mem.Allocator,

    /// Creates a new Lua state and opens the standard libraries (string,
    /// table, math, etc).
    pub fn init(allocator: std.mem.Allocator) !ScriptEngine {
        var lua = try Lua.init(allocator);
        lua.openLibs();
        return .{ .lua = lua, .alloc = allocator };
    }

    pub fn deinit(self: *ScriptEngine) void {
        self.lua.deinit();
    }

    /// Registers `func` as a global Lua function named `name`. Prefer
    /// stateless functions here; use a context struct (see
    /// `sequencer.SeqScriptingContext`) when the function needs to touch
    /// engine state.
    pub fn registerFunc(self: *ScriptEngine, name: []const u8, comptime func: LuaFunc) !void {
        self.lua.pushFunction(ziglua.wrap(func));
        self.setGlobal(name);
    }

    /// Registers `method` as a global Lua function named `name` that is
    /// called with `ctx`, so a binding can reach its own state without a
    /// global. `ctx` is stored as a light userdata upvalue and must outlive
    /// the Lua state (or the function must be unregistered first).
    pub fn registerMethod(
        self: *ScriptEngine,
        comptime T: type,
        ctx: *T,
        name: []const u8,
        comptime method: fn (*T, *Lua) i32,
    ) !void {
        const Thunk = struct {
            fn call(lua: *Lua) i32 {
                const self_ptr = lua.toUserdata(T, Lua.upvalueIndex(1)) catch {
                    lua.raiseErrorStr("registerMethod: missing context upvalue", .{});
                };
                return method(self_ptr, lua);
            }
        };
        self.lua.pushLightUserdata(ctx);
        self.lua.pushClosure(ziglua.wrap(Thunk.call), 1);
        self.setGlobal(name);
    }

    /// Pops the value on top of the stack into the global `name`.
    pub fn setGlobal(self: *ScriptEngine, name: []const u8) void {
        self.lua.pushGlobalTable();
        _ = self.lua.pushString(name);
        self.lua.rotate(-3, -1); // value, globals, name -> globals, name, value
        self.lua.setTable(-3);
        self.lua.pop(1);
    }

    /// Pushes the global `name` onto the stack and returns its type.
    pub fn getGlobal(self: *const ScriptEngine, name: []const u8) ziglua.LuaType {
        self.lua.pushGlobalTable();
        _ = self.lua.pushString(name);
        const kind = self.lua.getTable(-2);
        self.lua.remove(-2);
        return kind;
    }

    /// Compiles and runs an inline Lua code string. On a syntax or runtime
    /// error, logs the Lua error message and returns `error.SyntaxError` /
    /// `error.ScriptError`.
    pub fn run(self: *ScriptEngine, code: []const u8) !void {
        const codeZ = try std.mem.concatWithSentinel(self.alloc, u8, &.{code}, 0);
        defer self.alloc.free(codeZ);

        // Compile a line of Lua code
        self.lua.loadString(codeZ) catch {
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

    /// Runs a Lua file from disk. A relative path is resolved against the
    /// executable's own directory (see `paths`), so a packaged game finds
    /// its scripts wherever it is launched from. Like `run()`, logs the Lua
    /// error message and returns `error.SyntaxError` / `error.ScriptError`
    /// on syntax or runtime failure, plus `error.ScriptFileError` when the
    /// file can't be opened or read.
    pub fn runScript(self: *ScriptEngine, file: []const u8) !void {
        const resolved = try paths.resolveZ(self.alloc, file);
        defer self.alloc.free(resolved);

        // Lua leaves an error message on the stack for every load failure.
        self.lua.loadFile(resolved, .binary_text) catch |err| {
            std.log.err("{s}\n", .{self.lua.toString(-1) catch unreachable});
            self.lua.pop(1);
            return switch (err) {
                error.LuaFile => error.ScriptFileError,
                error.OutOfMemory => error.OutOfMemory,
                else => error.SyntaxError,
            };
        };

        self.lua.protectedCall(.{ .args = 0, .results = 0, .msg_handler = 0 }) catch {
            std.log.err("{s}\n", .{self.lua.toString(-1) catch unreachable});
            self.lua.pop(1);
            return error.ScriptError;
        };
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
        globalName: []const u8,
    ) !T {
        // Push the global `config` table onto the stack
        _ = self.getGlobal(globalName);

        // Ensure the global `config` is a table
        if (!self.lua.isTable(-1)) {
            self.lua.pop(1); // Pop the `config` table
            return error.InvalidConfigTable;
        }

        var myStruct: T = .{};
        // Iterate over fields of the struct at comptime
        inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |field_name, field_type| {

            // Get the value from Lua
            _ = self.lua.getField(-1, field_name); // Pushes `config.<field_name>` onto the stack

            // Match the field type and retrieve the value
            switch (@typeInfo(field_type)) {
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
