const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const zopengl = pixzig.zopengl;
const gl = zopengl.bindings;

// Need to reference the OpenGL bindings to ensure they get compiled in test mode.
// Otherwise we end up with missing linker symbols in zgui.  This only happens because
// the tests are not specifically referencing the PixzigEngine initialization necessarily.
comptime {
    @setEvalBranchQuota(20_000);
    _ = std.testing.refAllDeclsRecursive(zopengl);
}

const Tests = testz.discoverTests(.{
    testz.Group{ .name = "Tilemap Tests", .tag = "tile", .mod = @import("./tile_tests.zig") },
    testz.Group{ .name = "Keymap Tests", .tag = "keymap", .mod = @import("./keymap_tests.zig") },
    testz.Group{ .name = "Collision Tests", .tag = "collision", .mod = @import("./collision_tests.zig") },
    testz.Group{ .name = "A* Tests", .tag = "a_star", .mod = @import("./a_star_tests.zig") },
    testz.Group{ .name = "Sprite Tests", .tag = "sprite", .mod = @import("./sprite_tests.zig") },
    testz.Group{ .name = "Scripting Tests", .tag = "script", .mod = @import("./scripting_tests.zig") },
    testz.Group{ .name = "Font Tests", .tag = "font", .mod = @import("./font_tests.zig") },
}, .{});

pub fn main() !void {
    try testz.testzRunner(Tests);
}
