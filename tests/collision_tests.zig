const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const CollisionGrid = pixzig.collision.CollisionGrid;
const IntCollisionGrid = CollisionGrid(i32, 2);

pub fn insertionTest() !void {

    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
    defer grid.deinit();

    grid.insert(.{ .x = 0, .y = 0 }, 100) catch {
        try testz.fail();
    };
    grid.insert(.{ .x = 4, .y = 4 }, 200) catch {
        try testz.fail();
    };

    // Make sure we handle running out of space
    if (grid.insert(.{ .x = 2, .y = 2 }, 300)) |_| {
        try testz.fail();
    } else |_| {}

    var hits: [2]?i32 = .{ null, null };
    const res = grid.checkPoint(.{ .x = 3, .y = 3 }, &hits[0..]) catch {
        try testz.fail();
    };

    try testz.expectTrue(res);
    try testz.expectNotEqual(hits[0], null);
    try testz.expectEqual(hits[0].?, 100);

    try testz.expectNotEqual(hits[1], null);
    try testz.expectEqual(hits[1].?, 200);
}

pub fn insertRectTest() !void {

    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
    defer grid.deinit();

    grid.insertRect(.{ .t = 0, .l = 0, .r = 15, .b = 20 }, 100) catch {
        try testz.fail();
    };

    grid.insertRect(.{ .t = 6, .l = 10, .r = 25, .b = 15 }, 200) catch {
        try testz.fail();
    };

    var hits: [2]?i32 = .{ null, null };
    var res = grid.checkPoint(.{ .x = 3, .y = 3 }, &hits[0..]) catch {
        try testz.fail();
    };

    try testz.expectTrue(res);
    try testz.expectNotEqual(hits[0], null);
    try testz.expectEqual(hits[0].?, 100);
    try testz.expectEqual(hits[1], null);

    // Try one with no objets.
    res = grid.checkPoint(.{ .x = 40, .y = 40 }, &hits[0..]) catch {
        try testz.fail();
    };
    try testz.expectFalse(res);

    // Make sure our hit list got nulled out properly.
    try testz.expectEqual(hits[0], null);
    try testz.expectEqual(hits[1], null);

    // Try one with two objects
    res = grid.checkPoint(.{ .x = 12, .y = 8 }, &hits[0..]) catch {
        try testz.fail();
    };

    try testz.expectTrue(res);
    try testz.expectNotEqual(hits[0], null);
    try testz.expectEqual(hits[0].?, 100);

    try testz.expectNotEqual(hits[1], null);
    try testz.expectEqual(hits[1].?, 200);
}
