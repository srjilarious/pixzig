const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

const LuaFunc = fn (*Lua) i32;
pub const ScriptEngine = struct {
    lua: Lua,

    pub fn init(allocator: std.mem.Allocator) !ScriptEngine {
        var lua = try Lua.init(allocator);
        lua.openLibs();
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
            return;
        };

        // Execute a line of Lua code
        self.lua.protectedCall(0, 0, 0) catch {
            // Error handling here is the same as above.
            std.debug.print("{s}\n", .{self.lua.toString(-1) catch unreachable});
            self.lua.pop(1);
        };
    }
};

fn myFunc(lua: *Lua) i32 {
    _ = lua;
    std.debug.print("Test function called.\n", .{});
    return 0;
}

fn log(lua: *Lua) i32 {
    const msg = lua.toString(1) catch {
        std.debug.print("log(): Bad msg parameter.\n", .{});
        return 0;
    };
    std.debug.print("LOG: {s}\n", .{msg});
    return 0;
}

pub fn main() anyerror!void {
    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize the Lua vm
    var script = try ScriptEngine.init(allocator);
    defer script.deinit();

    try script.registerFunc("test", myFunc);
    try script.registerFunc("log", log);

    try script.run("test()");
    try script.run("log('My message here!')");
    // Add an integer to the Lua stack and retrieve it
    //lua.pushInteger(42);
    //std.debug.print("{}\n", .{try lua.toInteger(1)});
}
