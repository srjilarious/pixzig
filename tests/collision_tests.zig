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

// Narrow phase (collision/shapes.zig).

const col = pixzig.collision;
const Vec2F = pixzig.common.Vec2F;
const RectF = pixzig.common.RectF;

fn near(a: f32, b: f32) bool {
    return @abs(a - b) < 0.0001;
}

pub fn circleCircleTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const a: col.Circle = .{ .center = .{ .x = 0, .y = 0 }, .radius = 2 };
    const b: col.Circle = .{ .center = .{ .x = 3, .y = 0 }, .radius = 2 };
    const hit = col.circleCircle(a, b) orelse return testz.fail();
    // Normal points from b toward a.
    try testz.expectTrue(near(hit.normal.x, -1) and near(hit.normal.y, 0));
    try testz.expectTrue(near(hit.depth, 1));
    try testz.expectTrue(near(hit.mtv().x, -1));

    // Touching is not a collision.
    const touching: col.Circle = .{ .center = .{ .x = 4, .y = 0 }, .radius = 2 };
    try testz.expectTrue(col.circleCircle(a, touching) == null);

    // Same center still gets a usable normal.
    const same = col.circleCircle(a, a) orelse return testz.fail();
    try testz.expectTrue(near(same.normal.length(), 1) and near(same.depth, 4));
}

pub fn circleRectTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const r = RectF.fromPosSize(0, 0, 10, 10);

    // Overlapping the right edge from outside.
    const right = col.circleRect(.{ .center = .{ .x = 12, .y = 5 }, .radius = 3 }, r) orelse return testz.fail();
    try testz.expectTrue(near(right.normal.x, 1) and near(right.normal.y, 0));
    try testz.expectTrue(near(right.depth, 1));

    // Near a corner the normal is diagonal.
    const corner = col.circleRect(.{ .center = .{ .x = 11, .y = 11 }, .radius = 2 }, r) orelse return testz.fail();
    try testz.expectTrue(near(corner.normal.x, corner.normal.y) and corner.normal.x > 0);

    // Center inside: pushed out of the nearest edge (top here).
    const inside = col.circleRect(.{ .center = .{ .x = 5, .y = 1 }, .radius = 2 }, r) orelse return testz.fail();
    try testz.expectTrue(near(inside.normal.y, -1) and near(inside.depth, 3));

    try testz.expectTrue(col.circleRect(.{ .center = .{ .x = 14, .y = 5 }, .radius = 3 }, r) == null);
}

pub fn rectRectTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const b = RectF.fromPosSize(0, 0, 10, 10);

    // `a` sits mostly to the right, overlapping 2 in x and 8 in y.
    const a = RectF.fromPosSize(8, 1, 10, 8);
    const hit = col.rectRect(a, b) orelse return testz.fail();
    try testz.expectTrue(near(hit.normal.x, 1) and near(hit.normal.y, 0) and near(hit.depth, 2));

    // Moving `a` by the MTV separates it.
    const mtv = hit.mtv();
    const moved = RectF.fromPosSize(a.l + mtv.x, a.t + mtv.y, a.width(), a.height());
    try testz.expectTrue(col.rectRect(moved, b) == null);

    // Overlapping from above.
    const above = col.rectRect(RectF.fromPosSize(2, -3, 4, 4), b) orelse return testz.fail();
    try testz.expectTrue(near(above.normal.y, -1) and near(above.depth, 1));

    // Shared edge only.
    try testz.expectTrue(col.rectRect(RectF.fromPosSize(10, 0, 5, 5), b) == null);
}

pub fn segmentCircleTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const c: col.Circle = .{ .center = .{ .x = 10, .y = 0 }, .radius = 2 };

    const hit = col.segmentCircle(.{ .a = .{ .x = 0, .y = 0 }, .b = .{ .x = 20, .y = 0 } }, c) orelse return testz.fail();
    try testz.expectTrue(near(hit.t, 0.4) and near(hit.point.x, 8) and near(hit.normal.x, -1));

    // Stops short of the circle.
    try testz.expectTrue(col.segmentCircle(.{ .a = .{ .x = 0, .y = 0 }, .b = .{ .x = 7, .y = 0 } }, c) == null);
    // Passes beside it.
    try testz.expectTrue(col.segmentCircle(.{ .a = .{ .x = 0, .y = 3 }, .b = .{ .x = 20, .y = 3 } }, c) == null);
    // Starts inside.
    const inside = col.segmentCircle(.{ .a = .{ .x = 10, .y = 0 }, .b = .{ .x = 20, .y = 0 } }, c) orelse return testz.fail();
    try testz.expectTrue(inside.t == 0 and inside.normal.lengthSq() == 0);
}

pub fn segmentRectTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const r = RectF.fromPosSize(10, 10, 10, 10);

    // Enters through the left face.
    const left = col.segmentRect(.{ .a = .{ .x = 0, .y = 15 }, .b = .{ .x = 30, .y = 15 } }, r) orelse return testz.fail();
    try testz.expectTrue(near(left.t, 1.0 / 3.0) and near(left.point.x, 10) and near(left.normal.x, -1));

    // Diagonal from below-right enters through the bottom face.
    const bottom = col.segmentRect(.{ .a = .{ .x = 18, .y = 30 }, .b = .{ .x = 12, .y = 0 } }, r) orelse return testz.fail();
    try testz.expectTrue(near(bottom.normal.y, 1) and near(bottom.point.y, 20));

    // Misses, and stops short.
    try testz.expectTrue(col.segmentRect(.{ .a = .{ .x = 0, .y = 0 }, .b = .{ .x = 30, .y = 5 } }, r) == null);
    try testz.expectTrue(col.segmentRect(.{ .a = .{ .x = 0, .y = 15 }, .b = .{ .x = 9, .y = 15 } }, r) == null);

    // Vertical segment (zero x delta) through the rect.
    const vert = col.segmentRect(.{ .a = .{ .x = 15, .y = 0 }, .b = .{ .x = 15, .y = 30 } }, r) orelse return testz.fail();
    try testz.expectTrue(near(vert.point.y, 10) and near(vert.normal.y, -1));

    // Starts inside.
    const inside = col.segmentRect(.{ .a = .{ .x = 15, .y = 15 }, .b = .{ .x = 30, .y = 15 } }, r) orelse return testz.fail();
    try testz.expectTrue(inside.t == 0);
}

pub fn pointInPolygonTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // An L shape (concave).
    const poly = [_]Vec2F{
        .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 10, .y = 4 },
        .{ .x = 4, .y = 4 }, .{ .x = 4, .y = 10 }, .{ .x = 0, .y = 10 },
    };
    try testz.expectTrue(col.pointInPolygon(.{ .x = 2, .y = 8 }, &poly));
    try testz.expectTrue(col.pointInPolygon(.{ .x = 8, .y = 2 }, &poly));
    try testz.expectFalse(col.pointInPolygon(.{ .x = 8, .y = 8 }, &poly));
    try testz.expectFalse(col.pointInPolygon(.{ .x = -1, .y = 2 }, &poly));
    try testz.expectFalse(col.pointInPolygon(.{ .x = 1, .y = 1 }, poly[0..2]));

    try testz.expectTrue(col.pointInCircle(.{ .x = 1, .y = 1 }, .{ .center = .{ .x = 0, .y = 0 }, .radius = 2 }));
    try testz.expectFalse(col.pointInCircle(.{ .x = 2, .y = 2 }, .{ .center = .{ .x = 0, .y = 0 }, .radius = 2 }));
}
