const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

const LuaFunc = fn (*Lua) i32;
pub const ScriptEngine = struct {
    lua: *Lua,

    pub fn init(allocator: std.mem.Allocator) !ScriptEngine {
        std.log.debug("init a", .{});
        var lua = try Lua.init(allocator);
        std.log.debug("init b", .{});
        lua.openLibs();
        std.log.debug("init c", .{});
        return .{ .lua = lua };
    }

    pub fn deinit(self: *ScriptEngine) void {
        self.lua.deinit();
    }

    pub fn registerFunc(self: *ScriptEngine, name: [:0]const u8, comptime func: LuaFunc) !void {
        self.lua.pushFunction(ziglua.wrap(func));
        self.lua.setGlobal(name);
    }

    pub fn run(self: *ScriptEngine, code: [:0]const u8) !void {
        // Compile a line of Lua code
        self.lua.loadString(code) catch {
            // If there was an error, Lua will place an error string on the top of the stack.
            // Here we print out the string to inform the user of the issue.
            std.debug.print("{s}\n", .{self.lua.toString(-1) catch unreachable});

            // Remove the error from the stack and go back to the prompt
            self.lua.pop(1);
            return error.SyntaxError;
        };

        // Execute a line of Lua code
        self.lua.protectedCall(.{ .args = 0, .results = 0, .msg_handler = 0 }) catch {
            // Error handling here is the same as above.
            std.debug.print("{s}\n", .{self.lua.toString(-1) catch unreachable});
            self.lua.pop(1);
            return error.ScriptError;
        };
    }

    pub fn runScript(self: *ScriptEngine, file: [:0]const u8) !void {
        try self.lua.doFile(file);
    }

    // pub fn getValue(self: *const ScriptEngine)
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
                // Handle integers
                .int, .float => {
                    if (!self.lua.isInteger(-1)) {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidFieldType;
                    }
                    @field(myStruct, field_name) = @intCast(try self.lua.toInteger(-1));
                },
                .optional => |opt| {
                    switch (@typeInfo(opt.child)) {
                        .pointer => |ptr_info| switch (ptr_info.size) {
                            .Slice => {
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
