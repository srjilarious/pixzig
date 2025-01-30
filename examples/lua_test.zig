const std = @import("std");

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const pixzig = @import("pixzig");
const scripting = pixzig.scripting;
const console = pixzig.console;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

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

pub fn main() !void {
    std.log.info("Lua test starting.", .{});

    // Create an allocator
    const alloc = std.heap.c_allocator;

    // Initialize the Lua vm
    std.log.debug("a", .{});
    var script = try scripting.ScriptEngine.init(alloc);
    defer script.deinit();

    std.log.debug("b", .{});
    try script.registerFunc("test", myFunc);
    std.log.debug("c", .{});
    try script.registerFunc("log", log);

    std.log.debug("d", .{});
    try script.run("test()");
    std.log.debug("e", .{});
    try script.run("log('My message here!')");

    std.log.debug("f", .{});
    const cons = try console.Console.init(alloc, &script, .{});
    defer cons.deinit();

    std.log.debug("g", .{});
    try script.run("con:log('test from example inline run.')");

    std.log.debug("h", .{});
    try script.runScript("assets/test.lua");

    std.log.debug("i", .{});
    std.log.debug("Console entries:\n", .{});
    for (cons.history.items) |entry| {
        std.log.debug("{s}\n", .{entry});
    }

    // Add an integer to the Lua stack and retrieve it
    //lua.pushInteger(42);
    //std.debug.print("{}\n", .{try lua.toInteger(1)});
}
