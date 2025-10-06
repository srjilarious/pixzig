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

    try testz.expectEqual(res, 2);
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

    try testz.expectEqual(res, 1);
    try testz.expectNotEqual(hits[0], null);
    try testz.expectEqual(hits[0].?, 100);
    try testz.expectEqual(hits[1], null);

    // Try one with no objets.
    res = grid.checkPoint(.{ .x = 40, .y = 40 }, &hits[0..]) catch {
        try testz.fail();
    };
    try testz.expectEqual(res, 0);

    // Make sure our hit list got nulled out properly.
    try testz.expectEqual(hits[0], null);
    try testz.expectEqual(hits[1], null);

    // Try one with two objects
    res = grid.checkPoint(.{ .x = 12, .y = 8 }, &hits[0..]) catch {
        try testz.fail();
    };

    try testz.expectEqual(res, 2);
    try testz.expectNotEqual(hits[0], null);
    try testz.expectEqual(hits[0].?, 100);

    try testz.expectNotEqual(hits[1], null);
    try testz.expectEqual(hits[1].?, 200);
}

pub fn checkHorzTest() !void {
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
    defer grid.deinit();

    grid.insertRect(.{ .t = 0, .l = 0, .r = 15, .b = 20 }, 100) catch {
        try testz.fail();
    };

    grid.insertRect(.{ .t = 6, .l = 10, .r = 25, .b = 15 }, 200) catch {
        try testz.fail();
    };

    var hitList: [5]?i32 = .{ null, null, null, null, null };

    // Check case where we hit both rects.
    {
        const res = grid.checkHorz(0, 3, 1, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 2);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 100);

        try testz.expectNotEqual(hitList[1], null);
        try testz.expectEqual(hitList[1].?, 200);

        // Rest should be null
        for (2..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Test that a line without items doesn't pick anything up.
    {
        const res = try grid.checkHorz(0, 1, 7, &hitList[0..]);
        try testz.expectEqual(res, 0);
        for (0..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }
}

pub fn checkVertTest() !void {
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
    defer grid.deinit();

    grid.insertRect(.{ .t = 0, .l = 0, .r = 15, .b = 20 }, 100) catch {
        try testz.fail();
    };

    grid.insertRect(.{ .t = 6, .l = 10, .r = 25, .b = 15 }, 200) catch {
        try testz.fail();
    };

    var hitList: [5]?i32 = .{ null, null, null, null, null };

    // Check case where we hit both rects.
    {
        const res = grid.checkVert(2, 0, 2, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 2);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 100);

        try testz.expectNotEqual(hitList[1], null);
        try testz.expectEqual(hitList[1].?, 200);

        // Rest should be null
        for (2..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Test that a line without items doesn't pick anything up.
    {
        const res = try grid.checkVert(7, 0, 9, &hitList[0..]);
        try testz.expectEqual(res, 0);
        for (0..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }
}

pub fn checkLeftTest() !void {
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
    defer grid.deinit();

    grid.insertRect(.{ .t = 0, .l = 0, .r = 15, .b = 20 }, 100) catch {
        try testz.fail();
    };

    grid.insertRect(.{ .t = 6, .l = 10, .r = 25, .b = 15 }, 200) catch {
        try testz.fail();
    };

    var hitList: [5]?i32 = .{ null, null, null, null, null };

    // Check case where we hit both rects.
    {
        const res = grid.checkLeft(&.{ .t = 3, .l = 12, .b = 8, .r = 27 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 2);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 100);

        try testz.expectNotEqual(hitList[1], null);
        try testz.expectEqual(hitList[1].?, 200);

        // Rest should be null
        for (2..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Check case where we hit one rect.
    {
        const res = grid.checkLeft(&.{ .t = 3, .l = 20, .b = 8, .r = 36 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 1);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 200);

        // Rest should be null
        for (1..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }
}

pub fn checkRightTest() !void {
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
    defer grid.deinit();

    grid.insertRect(.{ .t = 0, .l = 0, .r = 15, .b = 20 }, 100) catch {
        try testz.fail();
    };

    grid.insertRect(.{ .t = 6, .l = 10, .r = 25, .b = 15 }, 200) catch {
        try testz.fail();
    };

    var hitList: [5]?i32 = .{ null, null, null, null, null };

    // Check case where we hit both rects.
    {
        const res = grid.checkRight(&.{ .t = 3, .l = 1, .b = 8, .r = 12 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 2);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 100);

        try testz.expectNotEqual(hitList[1], null);
        try testz.expectEqual(hitList[1].?, 200);

        // Rest should be null
        for (2..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Check case where we hit one rect.
    {
        const res = grid.checkRight(&.{ .t = 3, .l = 1, .b = 8, .r = 20 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 1);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 200);

        // Rest should be null
        for (1..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Case where we hit no rects
    {
        const res = grid.checkRight(&.{ .t = 3, .l = 12, .b = 8, .r = 27 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 0);

        // All should be null
        for (0..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }
}

pub fn checkUpTest() !void {
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
    defer grid.deinit();

    grid.insertRect(.{ .t = 4, .l = 2, .r = 15, .b = 20 }, 100) catch {
        try testz.fail();
    };

    grid.insertRect(.{ .t = 10, .l = 10, .r = 25, .b = 15 }, 200) catch {
        try testz.fail();
    };

    var hitList: [5]?i32 = .{ null, null, null, null, null };

    // Check case where we hit both rects.
    {
        const res = grid.checkUp(&.{ .t = 12, .l = 1, .b = 18, .r = 12 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 2);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 100);

        try testz.expectNotEqual(hitList[1], null);
        try testz.expectEqual(hitList[1].?, 200);

        // Rest should be null
        for (2..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Check case where we hit one rect.
    {
        const res = grid.checkUp(&.{ .t = 3, .l = 1, .b = 8, .r = 20 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 1);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 100);

        // Rest should be null
        for (1..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Case where we hit no rects
    {
        const res = grid.checkUp(&.{ .t = 30, .l = 12, .b = 38, .r = 27 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 0);

        // All should be null
        for (0..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }
}

pub fn checkDownTest() !void {
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(std.heap.page_allocator, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
    defer grid.deinit();

    grid.insertRect(.{ .t = 4, .l = 2, .r = 15, .b = 15 }, 100) catch {
        try testz.fail();
    };

    grid.insertRect(.{ .t = 10, .l = 10, .r = 25, .b = 20 }, 200) catch {
        try testz.fail();
    };

    var hitList: [5]?i32 = .{ null, null, null, null, null };

    // Check case where we hit both rects.
    {
        const res = grid.checkDown(&.{ .t = 2, .l = 1, .b = 12, .r = 12 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 2);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 100);

        try testz.expectNotEqual(hitList[1], null);
        try testz.expectEqual(hitList[1].?, 200);

        // Rest should be null
        for (2..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Check case where we hit one rect.
    {
        const res = grid.checkDown(&.{ .t = 3, .l = 1, .b = 18, .r = 20 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 1);
        try testz.expectNotEqual(hitList[0], null);
        try testz.expectEqual(hitList[0].?, 200);

        // Rest should be null
        for (1..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }

    // Case where we hit no rects
    {
        const res = grid.checkDown(&.{ .t = 10, .l = 12, .b = 38, .r = 27 }, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 0);

        // All should be null
        for (0..hitList.len) |idx| {
            try testz.expectEqual(hitList[idx], null);
        }
    }
}

pub fn checkRemoveTest() !void {
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

    try testz.expectEqual(res, 1);
    try testz.expectNotEqual(hits[0], null);
    try testz.expectEqual(hits[0].?, 100);

    try testz.expectEqual(hits[1], null);

    // Now remove the rect and make sure we don't hit it anymore.
    grid.removeRect(.{ .t = 0, .l = 0, .r = 15, .b = 20 }, 100) catch {
        try testz.fail();
    };

    hits = .{ null, null };
    res = grid.checkPoint(.{ .x = 3, .y = 3 }, &hits[0..]) catch {
        try testz.fail();
    };

    try testz.expectEqual(res, 0);
    try testz.expectEqual(hits[0], null);
    try testz.expectEqual(hits[1], null);

    // Make sure we can still hit the other rect.
    res = grid.checkPoint(.{ .x = 12, .y = 12 }, &hits[0..]) catch {
        try testz.fail();
    };
    try testz.expectEqual(res, 1);
    try testz.expectNotEqual(hits[0], null);
    try testz.expectEqual(hits[0].?, 200);

    try testz.expectEqual(hits[1], null);
}
