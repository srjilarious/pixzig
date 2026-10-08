const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const ScriptEngine = pixzig.scripting.ScriptEngine;
const ziglua = pixzig.ziglua;

const TestSettings: type = struct {
    music_volume: f32 = 1.0,
    sound_effects: bool = false,
};

const TestConfig = struct {
    fullscreen: bool = false,
    scale: i32 = 4,
    title: ?[]u8 = null,
    //settings: TestSettings = .{},

    pub fn deinit(self: *const TestConfig, alloc: std.mem.Allocator) void {
        if (self.title != null) {
            alloc.free(self.title.?);
        }
    }
};

const configLuaScript =
    \\    -- Lua configuration script
    \\    config = {
    \\        fullscreen = true,
    \\        scale = 2,
    \\        title = "My Game",
    \\    }
    \\
    \\    settings = {
    \\        music_volume = 0.8,
    \\        sound_effects = true
    \\    }
;

pub fn structFromLuaLoadingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    // Define the global config table in lua.
    try eng.run(configLuaScript);

    // Extract some values from the table
    var conf = eng.loadStruct(TestConfig, "config") catch |err| {
        std.log.err("ERROR: {}\n", .{err});
        return err;
    };
    defer conf.deinit(alloc);

    try testz.expectEqual(conf.scale, 2);
    try testz.expectTrue(conf.fullscreen);
    try testz.expectEqualStr(conf.title.?, "My Game");

    const settings = eng.loadStruct(TestSettings, "settings") catch |err| {
        std.log.err("ERROR: {}\n", .{err});
        return err;
    };
    try testz.expectEqual(settings.sound_effects, true);
    try testz.expectEqual(settings.music_volume, 0.8);
}

// --- run ---

// run executes Lua code and the result is visible in subsequent calls.
pub fn runExecutesCodeAndAccumulatesStateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    try eng.run("x = 42");
    _ = try eng.lua.getGlobal("x");
    const val = try eng.lua.toInteger(-1);
    eng.lua.pop(1);
    try testz.expectEqual(val, 42);
}

// A second run call can read globals set by the first.
pub fn runAccumulatesAcrossCallsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    try eng.run("a = 10");
    try eng.run("b = a + 5");

    _ = try eng.lua.getGlobal("b");
    const val = try eng.lua.toInteger(-1);
    eng.lua.pop(1);
    try testz.expectEqual(val, 15);
}

// run returns error.SyntaxError for invalid Lua syntax.
pub fn runSyntaxErrorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    var got_error = false;
    eng.run("@@ not valid lua @@") catch |err| {
        try testz.expectEqual(err, error.SyntaxError);
        got_error = true;
    };
    try testz.expectTrue(got_error);
}

// run returns error.ScriptError for a Lua runtime error.
pub fn runRuntimeErrorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    var got_error = false;
    eng.run("error('something went wrong')") catch |err| {
        try testz.expectEqual(err, error.ScriptError);
        got_error = true;
    };
    try testz.expectTrue(got_error);
}

// --- registerFunc ---

// Module-level variable so the Lua C callback can store its result.
var registeredFuncResult: i64 = 0;

fn doubleFunc(lua: *ziglua.Lua) i32 {
    const n = lua.toInteger(1) catch 0;
    lua.pushInteger(n * 2);
    return 1;
}

fn captureFunc(lua: *ziglua.Lua) i32 {
    registeredFuncResult = lua.toInteger(1) catch 0;
    return 0;
}

// A function registered with registerFunc is callable from Lua.
pub fn registerFuncCallableFromLuaTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    try eng.registerFunc("double", doubleFunc);
    try eng.run("result = double(21)");

    _ = try eng.lua.getGlobal("result");
    const val = try eng.lua.toInteger(-1);
    eng.lua.pop(1);
    try testz.expectEqual(val, 42);
}

// Multiple functions can be registered independently.
pub fn registerFuncMultipleFunctionsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    try eng.registerFunc("double", doubleFunc);
    try eng.registerFunc("capture", captureFunc);

    registeredFuncResult = 0;
    try eng.run("capture(99)");
    try testz.expectEqual(registeredFuncResult, 99);

    try eng.run("result = double(7)");
    _ = try eng.lua.getGlobal("result");
    const val = try eng.lua.toInteger(-1);
    eng.lua.pop(1);
    try testz.expectEqual(val, 14);
}

// --- registerMethod / globals ---

const Counter = struct {
    total: i64 = 0,

    fn luaAdd(self: *Counter, lua: *ziglua.Lua) i32 {
        self.total += lua.toInteger(1) catch 0;
        lua.pushInteger(self.total);
        return 1;
    }
};

// registerMethod hands each call its own context, so two registrations
// with different contexts stay independent.
pub fn registerMethodPassesContextTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    var a = Counter{};
    var b = Counter{};
    try eng.registerMethod(Counter, &a, "add_a", Counter.luaAdd);
    try eng.registerMethod(Counter, &b, "add_b", Counter.luaAdd);

    try eng.run("add_a(2); r = add_a(3); add_b(10)");
    try testz.expectEqual(a.total, 5);
    try testz.expectEqual(b.total, 10);

    _ = eng.getGlobal("r");
    const val = try eng.lua.toInteger(-1);
    eng.lua.pop(1);
    try testz.expectEqual(val, 5);
}

// setGlobal/getGlobal take plain slices, so a name sliced out of a larger
// buffer (no sentinel) still works.
pub fn globalsTakeUnterminatedNamesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();

    const names = "speedlimit";
    eng.lua.pushInteger(7);
    eng.setGlobal(names[0..5]);

    try eng.run("doubled = speed * 2");
    try testz.expectEqual(eng.getGlobal("doubled"), .number);
    const val = try eng.lua.toInteger(-1);
    eng.lua.pop(1);
    try testz.expectEqual(val, 14);

    const code = "x = 1 -- trailing bytes";
    try eng.run(code[0..5]);
    try testz.expectEqual(eng.getGlobal("x"), .number);
    eng.lua.pop(1);
}
