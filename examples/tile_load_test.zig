const std = @import("std");
const pixzig = @import("pixzig");
const tile = pixzig.tile;

pub fn main() !void {
    std.debug.print("Tile load test\n", .{});
    const map = try tile.TileMap.initFromFile("assets/level1a.tmx", std.heap.page_allocator);
    _ = map;
}
