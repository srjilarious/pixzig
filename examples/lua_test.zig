const std = @import("std");

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const scripting = @import("pixzig").scripting;
const console = @import("pixzig").console;

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
    var script = try scripting.ScriptEngine.init(&allocator);
    defer script.deinit();

    try script.registerFunc("test", myFunc);
    try script.registerFunc("log", log);

    try script.run("test()");
    try script.run("log('My message here!')");

    const cons = try console.Console.init(allocator, &script, .{});
    defer cons.deinit();

    try script.run("my_console:log('test from example inline run.')");

    try script.runScript("assets/test.lua");

    std.debug.print("Console entries:\n", .{});
    for (cons.history.items) |entry| {
        std.debug.print("{s}\n", .{entry});
    }

    // Add an integer to the Lua stack and retrieve it
    //lua.pushInteger(42);
    //std.debug.print("{}\n", .{try lua.toInteger(1)});
}
