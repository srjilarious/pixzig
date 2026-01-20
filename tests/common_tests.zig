const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const RectF = pixzig.RectF;
const RectI = pixzig.RectI;

pub fn rectFIntersectsOverlappingTest() !void {
    const rect1 = RectF.fromPosSize(0, 0, 10, 10);
    const rect2 = RectF.fromPosSize(5, 5, 10, 10);

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));
}

pub fn rectFIntersectsNonOverlappingTest() !void {
    const rect1 = RectF.fromPosSize(0, 0, 10, 10);
    const rect2 = RectF.fromPosSize(20, 20, 10, 10);

    try testz.expectFalse(rect1.intersects(&rect2));
    try testz.expectFalse(rect2.intersects(&rect1));
}

pub fn rectFIntersectsAdjacentTest() !void {
    // Touching but not overlapping
    const rect1 = RectF.fromPosSize(0, 0, 10, 10);
    const rect2 = RectF.fromPosSize(10, 0, 10, 10); // Touching right edge

    try testz.expectFalse(rect1.intersects(&rect2));
    try testz.expectFalse(rect2.intersects(&rect1));

    const rect3 = RectF.fromPosSize(0, 10, 10, 10); // Touching bottom edge
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));
}

pub fn rectFIntersectsContainedTest() !void {
    // One rectangle completely inside another
    const outer = RectF.fromPosSize(0, 0, 100, 100);
    const inner = RectF.fromPosSize(10, 10, 20, 20);

    try testz.expectTrue(outer.intersects(&inner));
    try testz.expectTrue(inner.intersects(&outer));
}

pub fn rectFIntersectsPartialOverlapTest() !void {
    // Partial overlap on one axis
    const rect1 = RectF.fromPosSize(0, 0, 10, 10);
    const rect2 = RectF.fromPosSize(5, 0, 10, 10); // Overlaps horizontally but aligned vertically

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectF.fromPosSize(0, 5, 10, 10); // Overlaps vertically but aligned horizontally
    try testz.expectTrue(rect1.intersects(&rect3));
    try testz.expectTrue(rect3.intersects(&rect1));
}

pub fn rectFIntersectsZeroSizeTest() !void {
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

pub fn rectFIntersectsFloatPrecisionTest() !void {
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

pub fn rectIIntersectsOverlappingTest() !void {
    const rect1 = RectI.init(0, 0, 10, 10);
    const rect2 = RectI.init(5, 5, 10, 10);

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));
}

pub fn rectIIntersectsNonOverlappingTest() !void {
    const rect1 = RectI.init(0, 0, 10, 10);
    const rect2 = RectI.init(20, 20, 10, 10);

    try testz.expectFalse(rect1.intersects(&rect2));
    try testz.expectFalse(rect2.intersects(&rect1));
}

pub fn rectIIntersectsAdjacentTest() !void {
    // Touching but not overlapping
    const rect1 = RectI.init(0, 0, 10, 10);
    const rect2 = RectI.init(10, 0, 10, 10); // Touching right edge

    try testz.expectFalse(rect1.intersects(&rect2));
    try testz.expectFalse(rect2.intersects(&rect1));

    const rect3 = RectI.init(0, 10, 10, 10); // Touching bottom edge
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));
}

pub fn rectIIntersectsContainedTest() !void {
    // One rectangle completely inside another
    const outer = RectI.init(0, 0, 100, 100);
    const inner = RectI.init(10, 10, 20, 20);

    try testz.expectTrue(outer.intersects(&inner));
    try testz.expectTrue(inner.intersects(&outer));
}

pub fn rectIIntersectsPartialOverlapTest() !void {
    // Partial overlap on one axis
    const rect1 = RectI.init(0, 0, 10, 10);
    const rect2 = RectI.init(5, 0, 10, 10); // Overlaps horizontally but aligned vertically

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectI.init(0, 5, 10, 10); // Overlaps vertically but aligned horizontally
    try testz.expectTrue(rect1.intersects(&rect3));
    try testz.expectTrue(rect3.intersects(&rect1));
}

pub fn rectIIntersectsZeroSizeTest() !void {
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

pub fn rectIIntersectsNegativeCoordsTest() !void {
    // Test with negative coordinates
    const rect1 = RectI.init(-10, -10, 10, 10);
    const rect2 = RectI.init(-5, -5, 10, 10);

    try testz.expectTrue(rect1.intersects(&rect2));
    try testz.expectTrue(rect2.intersects(&rect1));

    const rect3 = RectI.init(0, 0, 10, 10);
    try testz.expectFalse(rect1.intersects(&rect3));
    try testz.expectFalse(rect3.intersects(&rect1));
}
