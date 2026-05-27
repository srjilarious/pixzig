const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const Camera2D = pixzig.Camera2D;
const Viewport = pixzig.Viewport;
const ScalePolicy = pixzig.ScalePolicy;
const Vec2F = pixzig.Vec2F;
const RectF = pixzig.RectF;

fn approxEq(a: f32, b: f32) bool {
    return @abs(a - b) < 0.01;
}

pub fn cameraInitDefaultsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const cam = Camera2D.init(.{ .x = 800, .y = 600 });
    try testz.expectTrue(approxEq(cam.pos.x, 0.0));
    try testz.expectTrue(approxEq(cam.pos.y, 0.0));
    try testz.expectTrue(approxEq(cam.zoom, 1.0));
    try testz.expectTrue(approxEq(cam.rotation, 0.0));
}

pub fn cameraViewRectZoom1Test(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // logical 800x600, pos (0,0), zoom 1 -> half = (400, 300)
    const cam = Camera2D.init(.{ .x = 800, .y = 600 });
    const r = cam.viewRect();
    try testz.expectTrue(approxEq(r.l, -400.0));
    try testz.expectTrue(approxEq(r.t, -300.0));
    try testz.expectTrue(approxEq(r.r, 400.0));
    try testz.expectTrue(approxEq(r.b, 300.0));
}

pub fn cameraViewRectFollowsPositionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.pos = .{ .x = 100, .y = 50 };
    const r = cam.viewRect();
    try testz.expectTrue(approxEq(r.l, -300.0));
    try testz.expectTrue(approxEq(r.t, -250.0));
    try testz.expectTrue(approxEq(r.r, 500.0));
    try testz.expectTrue(approxEq(r.b, 350.0));
}

pub fn cameraViewRectZoom2Test(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // zoom=2 halves the visible world area: half = (200, 150)
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.zoom = 2.0;
    const r = cam.viewRect();
    try testz.expectTrue(approxEq(r.l, -200.0));
    try testz.expectTrue(approxEq(r.t, -150.0));
    try testz.expectTrue(approxEq(r.r, 200.0));
    try testz.expectTrue(approxEq(r.b, 150.0));
}

pub fn cameraWorldToLogicalCenterTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // The camera pos is the center: worldToLogical(pos) should return the logical center.
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.pos = .{ .x = 100, .y = 50 };
    const lc = cam.worldToLogical(cam.pos);
    try testz.expectTrue(approxEq(lc.x, 400.0));
    try testz.expectTrue(approxEq(lc.y, 300.0));
}

pub fn cameraWorldToLogicalRoundTripTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.pos = .{ .x = 50, .y = 25 };
    cam.zoom = 2.0;
    const world = Vec2F{ .x = 80, .y = 60 };
    const logical = cam.worldToLogical(world);
    const back = cam.logicalToWorld(logical);
    try testz.expectTrue(approxEq(back.x, world.x));
    try testz.expectTrue(approxEq(back.y, world.y));
}

pub fn cameraLogicalToWorldOriginTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // With camera at (0,0), logical (0,0) is the top-left, which in world space is (-logical_w/2, -logical_h/2).
    const cam = Camera2D.init(.{ .x = 800, .y = 600 });
    const w = cam.logicalToWorld(.{ .x = 0, .y = 0 });
    try testz.expectTrue(approxEq(w.x, -400.0));
    try testz.expectTrue(approxEq(w.y, -300.0));
}

pub fn cameraViewRectWidthHeightTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // At zoom=1 the view rect dimensions match the logical size.
    const cam = Camera2D.init(.{ .x = 320, .y = 180 });
    const r = cam.viewRect();
    try testz.expectTrue(approxEq(r.r - r.l, 320.0));
    try testz.expectTrue(approxEq(r.b - r.t, 180.0));
}

// --- bounds clamping --------------------------------------------------------

pub fn cameraBoundsNoBoundsUnchangedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Without bounds, pos is unchanged even outside the world.
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.pos = .{ .x = -999, .y = -999 };
    const r = cam.viewRect();
    try testz.expectTrue(approxEq(r.l, -999 - 400.0));
}

pub fn cameraBoundsTopLeftCornerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Camera trying to center on world origin (0,0) with a 800x600 viewport in a
    // 3200x2400 world. The viewport half-size is 400x300, so the min clamped pos
    // is (400, 300). The player appears at the top-left of the screen.
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.bounds = .{ .l = 0, .t = 0, .r = 3200, .b = 2400 };
    cam.pos = .{ .x = 0, .y = 0 };
    const r = cam.viewRect();
    try testz.expectTrue(approxEq(r.l, 0.0));
    try testz.expectTrue(approxEq(r.t, 0.0));
    try testz.expectTrue(approxEq(r.r, 800.0));
    try testz.expectTrue(approxEq(r.b, 600.0));
}

pub fn cameraBoundsBottomRightCornerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Camera trying to go past the bottom-right edge of the world.
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.bounds = .{ .l = 0, .t = 0, .r = 3200, .b = 2400 };
    cam.pos = .{ .x = 9999, .y = 9999 };
    const r = cam.viewRect();
    try testz.expectTrue(approxEq(r.r, 3200.0));
    try testz.expectTrue(approxEq(r.b, 2400.0));
}

pub fn cameraBoundsMidwayUnclampedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Camera centered in a large world stays unchanged.
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.bounds = .{ .l = 0, .t = 0, .r = 3200, .b = 2400 };
    cam.pos = .{ .x = 1600, .y = 1200 };
    const r = cam.viewRect();
    try testz.expectTrue(approxEq(r.l, 1200.0));
    try testz.expectTrue(approxEq(r.t, 900.0));
    try testz.expectTrue(approxEq(r.r, 2000.0));
    try testz.expectTrue(approxEq(r.b, 1500.0));
}

pub fn cameraBoundsSmallWorldCenteredTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // World smaller than the viewport: camera centers on the world regardless of pos.
    // Logical 800x600, world 200x100 -> center at (100, 50).
    var cam = Camera2D.init(.{ .x = 800, .y = 600 });
    cam.bounds = .{ .l = 0, .t = 0, .r = 200, .b = 100 };
    cam.pos = .{ .x = 9999, .y = 9999 };
    const r = cam.viewRect();
    // Centered: effective pos = (100, 50), view extends by half the logical size.
    try testz.expectTrue(approxEq(r.l + r.r, 200.0)); // midpoint == world center x
    try testz.expectTrue(approxEq(r.t + r.b, 100.0)); // midpoint == world center y
}
