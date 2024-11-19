const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const Path = pixzig.a_star.Path;
const AStarPathFinder = pixzig.a_star.AStarPathFinder;
const TileLayer = pixzig.tile.TileLayer;
const BasicTileMapPathChecker = pixzig.a_star.BasicTileMapPathChecker;

pub fn basicMoveRightGoalTest() !void {
    var path = Path.init(std.heap.page_allocator);

    const tl = try TileLayer.initEmpty(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 32, .y = 32 });
    const checker = BasicTileMapPathChecker.init(&tl);
    var pathFinder = try AStarPathFinder(BasicTileMapPathChecker).init(checker, std.heap.page_allocator, .{ .x = 10, .y = 10 });

    try pathFinder.findPath(.{ .x = 0, .y = 0 }, .{ .x = 2, .y = 0 }, &path);
    try testz.expectEqual(path.items.len, 2);
    try testz.expectTrue(path.items[0].equals(.{ .x = 1, .y = 0 }));
    try testz.expectTrue(path.items[1].equals(.{ .x = 2, .y = 0 }));
}

pub fn basicMoveLeftGoalTest() !void {
    var path = Path.init(std.heap.page_allocator);

    const tl = try TileLayer.initEmpty(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 32, .y = 32 });
    const checker = BasicTileMapPathChecker.init(&tl);
    var pathFinder = try AStarPathFinder(BasicTileMapPathChecker).init(checker, std.heap.page_allocator, .{ .x = 10, .y = 10 });

    try pathFinder.findPath(.{ .x = 4, .y = 0 }, .{ .x = 2, .y = 0 }, &path);
    try testz.expectEqual(path.items.len, 2);
    try testz.expectTrue(path.items[0].equals(.{ .x = 3, .y = 0 }));
    try testz.expectTrue(path.items[1].equals(.{ .x = 2, .y = 0 }));
}
