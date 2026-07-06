const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const zopengl = pixzig.zopengl;

const Tests = blk: {
    @setEvalBranchQuota(10000);
    break :blk testz.discoverTests(.{
    testz.Group{ .name = "Tilemap Tests", .tag = "tile", .mod = @import("./tile_tests.zig") },
    testz.Group{ .name = "Keymap Tests", .tag = "keymap", .mod = @import("./keymap_tests.zig") },
    testz.Group{ .name = "Collision Tests", .tag = "collision", .mod = @import("./collision_tests.zig") },
    testz.Group{ .name = "A* Tests", .tag = "a_star", .mod = @import("./a_star_tests.zig") },
    testz.Group{ .name = "Sprite Tests", .tag = "sprite", .mod = @import("./sprite_tests.zig") },
    testz.Group{ .name = "Scripting Tests", .tag = "script", .mod = @import("./scripting_tests.zig") },
    testz.Group{ .name = "Font Tests", .tag = "font", .mod = @import("./font_tests.zig") },
    testz.Group{ .name = "Event Tests", .tag = "event", .mod = @import("./event_tests.zig") },
    testz.Group{ .name = "Common Tests", .tag = "common", .mod = @import("./common_tests.zig") },
    testz.Group{ .name = "Sequencer Tests", .tag = "seq", .mod = @import("./sequencer_tests.zig") },
    testz.Group{ .name = "Utils Tests", .tag = "utils", .mod = @import("./utils_tests.zig") },
    testz.Group{ .name = "GameState Tests", .tag = "gamestate", .mod = @import("./gamestate_tests.zig") },
    testz.Group{ .name = "ActionMap Tests", .tag = "actions", .mod = @import("./action_tests.zig") },
    testz.Group{ .name = "Viewport Tests", .tag = "viewport", .mod = @import("./viewport_tests.zig") },
    testz.Group{ .name = "Camera Tests", .tag = "camera", .mod = @import("./camera_tests.zig") },
    testz.Group{ .name = "Resources Tests", .tag = "resources", .mod = @import("./resources_tests.zig") },
    testz.Group{ .name = "GL Renderer Tests", .tag = "gl", .mod = @import("./gl_renderer_tests.zig") },
}, .{});
};

pub fn main(init: std.process.Init) !void {
    try pixzig.GlTestContext.initGlobal();
    defer pixzig.GlTestContext.deinitGlobal();
    try testz.testzRunner(Tests, init.minimal.args);
}
