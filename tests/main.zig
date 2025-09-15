// zig fmt: off
const std = @import("std");
const testz = @import("testz");

const Tests = testz.discoverTests(.{ 
    testz.Group{ .name = "Tilemap Tests", .tag = "tile", .mod = @import("./tile_tests.zig")},
    testz.Group{ .name = "Keymap Tests", .tag = "keymap", .mod = @import("./keymap_tests.zig")},
    testz.Group{ .name = "Collision Tests", .tag = "collision", .mod = @import("./collision_tests.zig")},
    testz.Group{ .name = "A* Tests", .tag = "a_star", .mod = @import("./a_star_tests.zig")},
    testz.Group{ .name = "Sprite Tests", .tag = "sprite", .mod = @import("./sprite_tests.zig")},
    testz.Group{ .name = "Scripting Tests", .tag = "script", .mod = @import("./scripting_tests.zig")},
    testz.Group{ .name = "Font Tests", .tag = "font", .mod = @import("./font_tests.zig")},
}, .{});

pub fn main() !void {
    try testz.testzRunner(Tests);
}
