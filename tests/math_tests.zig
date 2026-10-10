const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const Rng = pixzig.Rng;
const Ease = pixzig.Ease;

fn approxEq(a: f32, b: f32) bool {
    return @abs(a - b) < 0.0001;
}

// --- Rng ---

pub fn rngSameSeedSameSequenceTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var a = Rng.init(1234);
    var b = Rng.init(1234);
    for (0..20) |_| {
        try testz.expectEqual(a.float(), b.float());
        try testz.expectEqual(a.intRange(i32, -5, 5), b.intRange(i32, -5, 5));
    }

    // reseed restarts the sequence.
    var c = Rng.init(99);
    const first = c.float();
    _ = c.float();
    c.reseed(99);
    try testz.expectEqual(c.float(), first);
}

pub fn rngRangesStayInBoundsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var rng = Rng.init(7);
    for (0..500) |_| {
        const f = rng.floatRange(-2.0, 3.0);
        try testz.expectTrue(f >= -2.0 and f < 3.0);

        // intRange includes both ends.
        const i = rng.intRange(u8, 1, 3);
        try testz.expectTrue(i >= 1 and i <= 3);

        try testz.expectTrue(approxEq(rng.direction().length(), 1));
    }

    try testz.expectFalse(rng.chance(0));
    try testz.expectTrue(rng.chance(1));
}

pub fn rngPickTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var rng = Rng.init(3);
    const items = [_]u32{ 10, 20, 30 };
    for (0..50) |_| {
        const v = rng.pick(u32, &items).?;
        try testz.expectTrue(v == 10 or v == 20 or v == 30);
    }

    const none: []const u32 = &.{};
    try testz.expectTrue(rng.pick(u32, none) == null);
}

// --- easing ---

pub fn easeEndpointsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Every curve starts at 0 and ends at 1.
    inline for (@typeInfo(Ease).@"enum".field_names) |name| {
        const ease: Ease = @field(Ease, name);
        try testz.expectTrue(approxEq(ease.apply(0), 0));
        try testz.expectTrue(approxEq(ease.apply(1), 1));
    }
}

pub fn easeShapesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    try testz.expectEqual(Ease.linear.apply(0.25), 0.25);
    // _in curves lag behind linear early, _out curves lead it.
    try testz.expectTrue(Ease.quad_in.apply(0.25) < 0.25);
    try testz.expectTrue(Ease.quad_out.apply(0.25) > 0.25);
    // _in_out curves are symmetric around the midpoint.
    try testz.expectTrue(approxEq(Ease.cubic_in_out.apply(0.5), 0.5));
    // back_out overshoots past the target before settling.
    try testz.expectTrue(Ease.back_out.apply(0.7) > 1.0);
    // t outside [0, 1] is clamped.
    try testz.expectEqual(Ease.quad_in.apply(2.0), 1.0);
    try testz.expectEqual(Ease.quad_in.apply(-1.0), 0.0);
}

pub fn easingTweenTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    try testz.expectEqual(pixzig.easing.tween(.linear, 10, 20, 0.5), 15);
    try testz.expectEqual(pixzig.easing.tween(.quad_in, 10, 20, 0.5), 12.5);
}
