const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const Path = pixzig.a_star.Path;
const AStarPathFinder = pixzig.a_star.AStarPathFinder;
const TileLayer = pixzig.tile.TileLayer;
const TileSet = pixzig.tile.TileSet;
const Tile = pixzig.tile.Tile;

const BasicTileMapPathChecker = pixzig.a_star.BasicTileMapPathChecker;

pub fn basicMoveRightGoalTest() !void {
    var path: Path = .{};

    const tl = try TileLayer.initEmpty(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 32, .y = 32 });
    const checker = BasicTileMapPathChecker.init(&tl);
    var pathFinder = try AStarPathFinder(BasicTileMapPathChecker).init(checker, std.heap.page_allocator, .{ .x = 10, .y = 10 });

    try pathFinder.findPath(.{ .x = 0, .y = 0 }, .{ .x = 2, .y = 0 }, &path);
    try testz.expectEqual(path.items.len, 2);
    try testz.expectTrue(path.items[0].equals(.{ .x = 1, .y = 0 }));
    try testz.expectTrue(path.items[1].equals(.{ .x = 2, .y = 0 }));
}

pub fn basicMoveLeftGoalTest() !void {
    var path: Path = .{}; //Path.init(std.heap.page_allocator);

    const tl = try TileLayer.initEmpty(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 32, .y = 32 });
    const checker = BasicTileMapPathChecker.init(&tl);
    var pathFinder = try AStarPathFinder(BasicTileMapPathChecker).init(checker, std.heap.page_allocator, .{ .x = 10, .y = 10 });

    try pathFinder.findPath(.{ .x = 4, .y = 0 }, .{ .x = 2, .y = 0 }, &path);
    try testz.expectEqual(path.items.len, 2);
    try testz.expectTrue(path.items[0].equals(.{ .x = 3, .y = 0 }));
    try testz.expectTrue(path.items[1].equals(.{ .x = 2, .y = 0 }));
}

pub fn basicMoveRightWithWallGoalTest() !void {
    const alloc = std.heap.page_allocator;
    var path: Path = .{};

    var tl = try TileLayer.initEmpty(alloc, .{ .x = 10, .y = 10 }, .{ .x = 32, .y = 32 });
    tl.setTileData(1, 0, 1);
    var ts = try TileSet.init(alloc);
    try ts.tiles.append(alloc, Tile{
        .core = pixzig.tile.Clear,
        .properties = null,
        .alloc = alloc,
    });
    try ts.tiles.append(alloc, Tile{
        .core = pixzig.tile.BlocksAll,
        .properties = null,
        .alloc = alloc,
    });
    tl.tileset = &ts;

    const checker = BasicTileMapPathChecker.init(&tl);
    var pathFinder = try AStarPathFinder(BasicTileMapPathChecker).init(checker, std.heap.page_allocator, .{ .x = 10, .y = 10 });

    try pathFinder.findPath(.{ .x = 0, .y = 0 }, .{ .x = 2, .y = 0 }, &path);
    try testz.expectEqual(path.items.len, 4);
    try testz.expectTrue(path.items[0].equals(.{ .x = 0, .y = 1 }));
    try testz.expectTrue(path.items[1].equals(.{ .x = 1, .y = 1 }));
    try testz.expectTrue(path.items[2].equals(.{ .x = 2, .y = 1 }));
    try testz.expectTrue(path.items[3].equals(.{ .x = 2, .y = 0 }));
}
