const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const ScriptEngine = pixzig.scripting.ScriptEngine;

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

pub fn structFromLuaLoading() !void {
    var eng = try ScriptEngine.init(std.heap.page_allocator);
    // Define the global config table in lua.
    try eng.run(configLuaScript);

    // Extract some values from the table
    var conf = eng.loadStruct(TestConfig, "config") catch |err| {
        std.debug.print("ERROR: {}\n", .{err});
        return err;
    };
    defer conf.deinit(std.heap.page_allocator);

    try testz.expectEqual(conf.scale, 2);
    try testz.expectTrue(conf.fullscreen);
    try testz.expectEqualStr(conf.title.?, "My Game");

    const settings = eng.loadStruct(TestSettings, "settings") catch |err| {
        std.debug.print("ERROR: {}\n", .{err});
        return err;
    };

    try testz.expectEqual(settings.sound_effects, true);
    try testz.expectEqual(settings.music_volume, 0.8);
}
