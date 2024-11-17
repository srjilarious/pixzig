const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const Path = pixzig.a_star.Path;
const AStarPathFinder = pixzig.a_star.AStarPathFinder;

pub fn basicMoveRightGoalTest() !void {
    var path = Path.init(std.heap.page_allocator);

    var pathFinder = try AStarPathFinder.init(std.heap.page_allocator, .{ .x = 10, .y = 10 });

    try pathFinder.findPath(.{ .x = 0, .y = 0 }, .{ .x = 2, .y = 0 }, &path);
    try testz.expectEqual(path.items.len, 2);
    try testz.expectTrue(path.items[0].equals(.{ .x = 1, .y = 0 }));
    try testz.expectTrue(path.items[1].equals(.{ .x = 2, .y = 0 }));
}
