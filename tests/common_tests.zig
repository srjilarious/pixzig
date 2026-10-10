const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const RectF = pixzig.RectF;
const RectI = pixzig.RectI;

pub fn rectFIntersectsOverlappingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const rect1 = RectF.fromPosSize(0, 0, 10, 10);
    const rect2 = RectF.fromPosSize(5, 5, 10, 10);

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));
}

pub fn rectFIntersectsNonOverlappingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const rect1 = RectF.fromPosSize(0, 0, 10, 10);
    const rect2 = RectF.fromPosSize(20, 20, 10, 10);

    try testz.expectFalse(rect1.intersects(&rect2));
    try testz.expectFalse(rect2.intersects(&rect1));
}

pub fn rectFIntersectsAdjacentTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Touching but not overlapping
    const rect1 = RectF.fromPosSize(0, 0, 10, 10);
    const rect2 = RectF.fromPosSize(10, 0, 10, 10); // Touching right edge

    try testz.expectFalse(rect1.intersects(&rect2));
    try testz.expectFalse(rect2.intersects(&rect1));

    const rect3 = RectF.fromPosSize(0, 10, 10, 10); // Touching bottom edge
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));
}

pub fn rectFIntersectsContainedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // One rectangle completely inside another
    const outer = RectF.fromPosSize(0, 0, 100, 100);
    const inner = RectF.fromPosSize(10, 10, 20, 20);

    try testz.expectTrue(outer.intersects(&inner));
    try testz.expectTrue(inner.intersects(&outer));
}

pub fn rectFIntersectsPartialOverlapTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Partial overlap on one axis
    const rect1 = RectF.fromPosSize(0, 0, 10, 10);
    const rect2 = RectF.fromPosSize(5, 0, 10, 10); // Overlaps horizontally but aligned vertically

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectF.fromPosSize(0, 5, 10, 10); // Overlaps vertically but aligned horizontally
    try testz.expectTrue(rect1.intersects(&rect3));
    try testz.expectTrue(rect3.intersects(&rect1));
}

pub fn rectFIntersectsZeroSizeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Zero-size rectangles (points)
    const rect1 = RectF.fromPosSize(5, 5, 0, 0); // Point at (5, 5)
    const rect2 = RectF.fromPosSize(0, 0, 10, 10);

    // Point inside the rectangle should intersect
    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectF.fromPosSize(20, 20, 0, 0); // Point outside
    // Point outside should not intersect
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));

    // Point on edge doesn't intersect (strict inequality)
    const rect4 = RectF.fromPosSize(0, 0, 0, 0); // Point at (0, 0)
    const rect5 = RectF.fromPosSize(0, 0, 10, 10);
    try testz.expectFalse(rect4.intersects(&rect5));
    try testz.expectFalse(rect5.intersects(&rect4));
}

pub fn rectFIntersectsFloatPrecisionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Test with floating point values
    const rect1 = RectF{ .l = 0.5, .t = 0.5, .r = 10.5, .b = 10.5 };
    const rect2 = RectF{ .l = 10.4, .t = 0.5, .r = 20.5, .b = 10.5 };

    // Should intersect due to 10.4 < 10.5
    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectF{ .l = 10.6, .t = 0.5, .r = 20.5, .b = 10.5 };
    // Should not intersect
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));
}

pub fn rectIIntersectsOverlappingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const rect1 = RectI.init(0, 0, 10, 10);
    const rect2 = RectI.init(5, 5, 10, 10);

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));
}

pub fn rectIIntersectsNonOverlappingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const rect1 = RectI.init(0, 0, 10, 10);
    const rect2 = RectI.init(20, 20, 10, 10);

    try testz.expectFalse(rect1.intersects(&rect2));
    try testz.expectFalse(rect2.intersects(&rect1));
}

pub fn rectIIntersectsAdjacentTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Touching but not overlapping
    const rect1 = RectI.init(0, 0, 10, 10);
    const rect2 = RectI.init(10, 0, 10, 10); // Touching right edge

    try testz.expectFalse(rect1.intersects(&rect2));
    try testz.expectFalse(rect2.intersects(&rect1));

    const rect3 = RectI.init(0, 10, 10, 10); // Touching bottom edge
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));
}

pub fn rectIIntersectsContainedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // One rectangle completely inside another
    const outer = RectI.init(0, 0, 100, 100);
    const inner = RectI.init(10, 10, 20, 20);

    try testz.expectTrue(outer.intersects(&inner));
    try testz.expectTrue(inner.intersects(&outer));
}

pub fn rectIIntersectsPartialOverlapTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Partial overlap on one axis
    const rect1 = RectI.init(0, 0, 10, 10);
    const rect2 = RectI.init(5, 0, 10, 10); // Overlaps horizontally but aligned vertically

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectI.init(0, 5, 10, 10); // Overlaps vertically but aligned horizontally
    try testz.expectTrue(rect1.intersects(&rect3));
    try testz.expectTrue(rect3.intersects(&rect1));
}

pub fn rectIIntersectsZeroSizeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Zero-size rectangles (points)
    const rect1 = RectI.init(5, 5, 0, 0); // Point at (5, 5)
    const rect2 = RectI.init(0, 0, 10, 10);

    // Point inside the rectangle should intersect
    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectI.init(20, 20, 0, 0); // Point outside
    // Point outside should not intersect
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));

    // Point on edge doesn't intersect (strict inequality)
    const rect4 = RectI.init(0, 0, 0, 0); // Point at (0, 0)
    const rect5 = RectI.init(0, 0, 10, 10);
    try testz.expectFalse(rect4.intersects(&rect5));
    try testz.expectFalse(rect5.intersects(&rect4));
}

pub fn rectIIntersectsNegativeCoordsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Test with negative coordinates
    const rect1 = RectI.init(-10, -10, 10, 10);
    const rect2 = RectI.init(-5, -5, 10, 10);

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectI.init(0, 0, 10, 10);
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));
}

// --- Vec2F ---

const Vec2F = pixzig.Vec2F;

fn approxEq(a: f32, b: f32) bool {
    return @abs(a - b) < 0.0001;
}

/// testz's expectEqual can't compare structs, so compare component-wise.
fn expectVec(actual: Vec2F, expected: Vec2F) !void {
    try testz.expectEqual(actual.x, expected.x);
    try testz.expectEqual(actual.y, expected.y);
}

pub fn vec2FArithmeticTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const a = Vec2F{ .x = 3, .y = 4 };
    const b = Vec2F{ .x = 1, .y = -2 };

    try expectVec(a.add(b), Vec2F{ .x = 4, .y = 2 });
    try expectVec(a.sub(b), Vec2F{ .x = 2, .y = 6 });
    try expectVec(a.scale(2), Vec2F{ .x = 6, .y = 8 });
    try expectVec(a.mul(b), Vec2F{ .x = 3, .y = -8 });
    try expectVec(a.neg(), Vec2F{ .x = -3, .y = -4 });
    try testz.expectEqual(a.dot(b), -5);
    try testz.expectEqual(a.cross(b), -10);
    try testz.expectEqual(a.lengthSq(), 25);
    try testz.expectEqual(a.length(), 5);
    try testz.expectEqual(a.distance(Vec2F.zero), 5);

    // Chains read left to right.
    try expectVec(Vec2F.zero.add(a).scale(0.5), Vec2F{ .x = 1.5, .y = 2 });
}

pub fn vec2FNormalizeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const n = (Vec2F{ .x = 3, .y = 4 }).normalize();
    try testz.expectTrue(approxEq(n.x, 0.6));
    try testz.expectTrue(approxEq(n.y, 0.8));
    try testz.expectTrue(approxEq(n.length(), 1));

    // Zero stays zero instead of producing NaNs.
    try expectVec(Vec2F.zero.normalize(), Vec2F.zero);
}

pub fn vec2FLerpTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const a = Vec2F{ .x = 0, .y = 10 };
    const b = Vec2F{ .x = 10, .y = 30 };
    try expectVec(a.lerp(b, 0), a);
    try expectVec(a.lerp(b, 1), b);
    try expectVec(a.lerp(b, 0.5), Vec2F{ .x = 5, .y = 20 });
}

pub fn vec2FRotateAndAngleTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // A quarter turn takes +x to +y: clockwise on a y-down screen.
    const r = (Vec2F{ .x = 1, .y = 0 }).rotate(std.math.pi / 2.0);
    try testz.expectTrue(approxEq(r.x, 0));
    try testz.expectTrue(approxEq(r.y, 1));

    // fromAngle and angle invert each other.
    const v = Vec2F.fromAngle(0.75);
    try testz.expectTrue(approxEq(v.length(), 1));
    try testz.expectTrue(approxEq(v.angle(), 0.75));

    // cross is positive when the second vector is clockwise from the first.
    try testz.expectTrue((Vec2F{ .x = 1, .y = 0 }).cross(r) > 0);
}
