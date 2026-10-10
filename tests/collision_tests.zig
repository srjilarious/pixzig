const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const CollisionGrid = pixzig.collision.CollisionGrid;
const IntCollisionGrid = CollisionGrid(i32, 2);

pub fn insertionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;

    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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

pub fn insertRectTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;

    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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

pub fn checkHorzTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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

pub fn checkVertTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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

    // Check that an out of bounds left line doesn't error out.
    {
        const res = try grid.checkVert(-3, 0, 9, &hitList[0..]);
        try testz.expectEqual(res, 0);
    }

    // Check that an out of bounds right line doesn't error out.
    {
        const res = try grid.checkVert(12, 0, 9, &hitList[0..]);
        try testz.expectEqual(res, 0);
    }

    // Check case where we hit both rects, extending off beginning of grid.
    {
        const res = grid.checkVert(2, -10, 2, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 2);
    }

    // Check case where we hit both rects, extending off end of grid.
    {
        const res = grid.checkVert(2, 0, 20, &hitList[0..]) catch |err| {
            try testz.failWith(err);
            return error.Fail;
        };

        try testz.expectEqual(res, 2);
    }
}

pub fn checkLeftTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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

pub fn checkRightTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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

pub fn checkUpTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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

pub fn checkDownTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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

pub fn checkRemoveTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // creates a 10x10 grid with cells 5x5 pixels
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 10, .y = 10 }, .{ .x = 5, .y = 5 });
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
    _ = grid.removeRect(.{ .t = 0, .l = 0, .r = 15, .b = 20 }, 100) catch {
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

pub fn insertRectStraddlesCellEdgeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 4, .y = 4 }, .{ .x = 16, .y = 16 });
    defer grid.deinit();

    // 10 wide starting at 15 covers cells 0 and 1, though it's narrower than a cell.
    const bounds: pixzig.RectF = .{ .l = 15, .t = 0, .r = 25, .b = 10 };
    try grid.insertRect(bounds, 100);

    var hits: [2]?i32 = .{ null, null };
    try testz.expectEqual(try grid.checkPoint(.{ .x = 15, .y = 5 }, &hits[0..]), 1);
    try testz.expectEqual(try grid.checkPoint(.{ .x = 20, .y = 5 }, &hits[0..]), 1);

    // A rect ending exactly on a cell boundary doesn't spill into the next cell.
    try grid.insertRect(.{ .l = 32, .t = 0, .r = 48, .b = 16 }, 200);
    try testz.expectEqual(try grid.checkPoint(.{ .x = 48, .y = 5 }, &hits[0..]), 0);

    try testz.expectEqual(try grid.removeRect(bounds, 100), 2);
    try testz.expectEqual(try grid.checkPoint(.{ .x = 20, .y = 5 }, &hits[0..]), 0);
}

pub fn insertRectNegativeBoundsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 4, .y = 4 }, .{ .x = 16, .y = 16 });
    defer grid.deinit();

    // Partly off the top-left: only the on-grid cell is filled.
    const bounds: pixzig.RectF = .{ .l = -8, .t = -8, .r = 8, .b = 8 };
    try grid.insertRect(bounds, 100);

    var hits: [2]?i32 = .{ null, null };
    try testz.expectEqual(try grid.checkPoint(.{ .x = 2, .y = 2 }, &hits[0..]), 1);

    // Entirely off-grid is a no-op rather than a panic.
    try grid.insertRect(.{ .l = -40, .t = -40, .r = -20, .b = -20 }, 200);
    try grid.insertRect(.{ .l = 100, .t = 0, .r = 120, .b = 10 }, 300);

    try testz.expectEqual(try grid.removeRect(bounds, 100), 1);
    try testz.expectEqual(try grid.removeRect(.{ .l = -40, .t = -40, .r = -20, .b = -20 }, 200), 0);
}

pub fn checkHorzSkippedDuplicatesFitTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var grid = try IntCollisionGrid.init(alloc, .{ .x = 4, .y = 4 }, .{ .x = 16, .y = 16 });
    defer grid.deinit();

    // 100 spans cells 0 and 1 (both axes); 200 only cell 1, after the repeated 100.
    try grid.insertRect(.{ .l = 0, .t = 0, .r = 32, .b = 32 }, 100);
    try grid.insertRect(.{ .l = 16, .t = 0, .r = 32, .b = 16 }, 200);
    try grid.insertRect(.{ .l = 0, .t = 16, .r = 16, .b = 32 }, 300);

    // Exactly two unique hits fit in a two-slot list.
    var hits: [2]?i32 = .{ null, null };
    try testz.expectEqual(try grid.checkHorz(0, 1, 0, &hits[0..]), 2);
    try testz.expectEqual(hits[1].?, 200);
    try testz.expectEqual(try grid.checkVert(0, 0, 1, &hits[0..]), 2);
    try testz.expectEqual(hits[1].?, 300);
}
