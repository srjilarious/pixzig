const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const zmath = pixzig.zmath;

const Camera2D = pixzig.Camera2D;
const Viewport = pixzig.Viewport;
const ScalePolicy = pixzig.ScalePolicy;
const Vec2F = pixzig.Vec2F;
const RectF = pixzig.RectF;

fn approxEq(a: f32, b: f32) bool {
    return @abs(a - b) < 0.01;
}

/// A viewport whose logical size matches its framebuffer, for the camera
/// math that only reads the logical size.
fn testViewport(w: i32, h: i32) Viewport {
    return Viewport.init(.{ .x = w, .y = h }, .{ .x = w, .y = h }, .stretch);
}

pub fn cameraInitDefaultsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const cam = Camera2D.init();
    try testz.expectTrue(approxEq(cam.pos.x, 0.0));
    try testz.expectTrue(approxEq(cam.pos.y, 0.0));
    try testz.expectTrue(approxEq(cam.zoom, 1.0));
    try testz.expectTrue(approxEq(cam.rotation, 0.0));
}

pub fn cameraViewRectZoom1Test(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // logical 800x600, pos (0,0), zoom 1 -> half = (400, 300)
    const vp = testViewport(800, 600);
    const cam = Camera2D.init();
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.l, -400.0));
    try testz.expectTrue(approxEq(r.t, -300.0));
    try testz.expectTrue(approxEq(r.r, 400.0));
    try testz.expectTrue(approxEq(r.b, 300.0));
}

pub fn cameraViewRectFollowsPositionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.pos = .{ .x = 100, .y = 50 };
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.l, -300.0));
    try testz.expectTrue(approxEq(r.t, -250.0));
    try testz.expectTrue(approxEq(r.r, 500.0));
    try testz.expectTrue(approxEq(r.b, 350.0));
}

pub fn cameraViewRectZoom2Test(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // zoom=2 halves the visible world area: half = (200, 150)
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.zoom = 2.0;
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.l, -200.0));
    try testz.expectTrue(approxEq(r.t, -150.0));
    try testz.expectTrue(approxEq(r.r, 200.0));
    try testz.expectTrue(approxEq(r.b, 150.0));
}

pub fn cameraWorldToLogicalCenterTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // The camera pos is the center: worldToLogical(pos) should return the logical center.
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.pos = .{ .x = 100, .y = 50 };
    const lc = cam.worldToLogical(&vp, cam.pos);
    try testz.expectTrue(approxEq(lc.x, 400.0));
    try testz.expectTrue(approxEq(lc.y, 300.0));
}

pub fn cameraWorldToLogicalRoundTripTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.pos = .{ .x = 50, .y = 25 };
    cam.zoom = 2.0;
    const world = Vec2F{ .x = 80, .y = 60 };
    const logical = cam.worldToLogical(&vp, world);
    const back = cam.logicalToWorld(&vp, logical);
    try testz.expectTrue(approxEq(back.x, world.x));
    try testz.expectTrue(approxEq(back.y, world.y));
}

pub fn cameraLogicalToWorldOriginTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // With camera at (0,0), logical (0,0) is the top-left, which in world space is (-logical_w/2, -logical_h/2).
    const vp = testViewport(800, 600);
    const cam = Camera2D.init();
    const w = cam.logicalToWorld(&vp, .{ .x = 0, .y = 0 });
    try testz.expectTrue(approxEq(w.x, -400.0));
    try testz.expectTrue(approxEq(w.y, -300.0));
}

pub fn cameraViewRectWidthHeightTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // At zoom=1 the view rect dimensions match the logical size.
    const vp = testViewport(320, 180);
    const cam = Camera2D.init();
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.r - r.l, 320.0));
    try testz.expectTrue(approxEq(r.b - r.t, 180.0));
}

// --- bounds clamping --------------------------------------------------------

pub fn cameraBoundsNoBoundsUnchangedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Without bounds, pos is unchanged even outside the world.
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.pos = .{ .x = -999, .y = -999 };
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.l, -999 - 400.0));
}

pub fn cameraBoundsTopLeftCornerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Camera trying to center on world origin (0,0) with a 800x600 viewport in a
    // 3200x2400 world. The viewport half-size is 400x300, so the min clamped pos
    // is (400, 300). The player appears at the top-left of the screen.
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.bounds = .{ .l = 0, .t = 0, .r = 3200, .b = 2400 };
    cam.pos = .{ .x = 0, .y = 0 };
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.l, 0.0));
    try testz.expectTrue(approxEq(r.t, 0.0));
    try testz.expectTrue(approxEq(r.r, 800.0));
    try testz.expectTrue(approxEq(r.b, 600.0));
}

pub fn cameraBoundsBottomRightCornerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Camera trying to go past the bottom-right edge of the world.
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.bounds = .{ .l = 0, .t = 0, .r = 3200, .b = 2400 };
    cam.pos = .{ .x = 9999, .y = 9999 };
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.r, 3200.0));
    try testz.expectTrue(approxEq(r.b, 2400.0));
}

pub fn cameraBoundsMidwayUnclampedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Camera centered in a large world stays unchanged.
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.bounds = .{ .l = 0, .t = 0, .r = 3200, .b = 2400 };
    cam.pos = .{ .x = 1600, .y = 1200 };
    const r = cam.viewRect(&vp);
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
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.bounds = .{ .l = 0, .t = 0, .r = 200, .b = 100 };
    cam.pos = .{ .x = 9999, .y = 9999 };
    const r = cam.viewRect(&vp);
    // Centered: effective pos = (100, 50), view extends by half the logical size.
    try testz.expectTrue(approxEq(r.l + r.r, 200.0)); // midpoint == world center x
    try testz.expectTrue(approxEq(r.t + r.b, 100.0)); // midpoint == world center y
}

// --- rotation + viewport-following size ------------------------------------

/// Maps a world point through `cam.matrix` to logical coordinates, for
/// checking the CPU-side conversions against what the GPU draws.
fn matrixToLogical(cam: *const Camera2D, vp: *const Viewport, world: Vec2F) Vec2F {
    const ndc = zmath.mul(zmath.f32x4(world.x, world.y, 0, 1), cam.matrix(vp));
    const lw: f32 = @floatFromInt(vp.logicalSize.x);
    const lh: f32 = @floatFromInt(vp.logicalSize.y);
    return .{ .x = (ndc[0] + 1) * 0.5 * lw, .y = (1 - ndc[1]) * 0.5 * lh };
}

pub fn cameraRotatedWorldToLogicalMatchesMatrixTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.pos = .{ .x = 50, .y = 25 };
    cam.zoom = 2.0;
    cam.rotation = 0.6;

    const world = Vec2F{ .x = 80, .y = -40 };
    const expected = matrixToLogical(&cam, &vp, world);
    const logical = cam.worldToLogical(&vp, world);
    try testz.expectTrue(approxEq(logical.x, expected.x));
    try testz.expectTrue(approxEq(logical.y, expected.y));

    const back = cam.logicalToWorld(&vp, logical);
    try testz.expectTrue(approxEq(back.x, world.x));
    try testz.expectTrue(approxEq(back.y, world.y));
}

pub fn cameraRotatedViewRectCoversCornersTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // A quarter turn swaps the visible width and height.
    const vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.rotation = std.math.pi / 2.0;
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.r - r.l, 600.0));
    try testz.expectTrue(approxEq(r.b - r.t, 800.0));

    // Every corner of the screen maps inside the rect at any angle.
    cam.rotation = 0.3;
    const box = cam.viewRect(&vp);
    const corners = [_]Vec2F{ .{ .x = 0, .y = 0 }, .{ .x = 800, .y = 0 }, .{ .x = 0, .y = 600 }, .{ .x = 800, .y = 600 } };
    for (corners) |c| {
        const w = cam.logicalToWorld(&vp, c);
        try testz.expectTrue(w.x >= box.l - 0.01 and w.x <= box.r + 0.01);
        try testz.expectTrue(w.y >= box.t - 0.01 and w.y <= box.b + 0.01);
    }
}

pub fn cameraFollowsViewportResizeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // The camera reads the logical size from the viewport, so a viewport
    // that grows with the window keeps the camera position centered.
    var vp = testViewport(800, 600);
    var cam = Camera2D.init();
    cam.pos = .{ .x = 100, .y = 100 };

    vp.logicalSize = .{ .x = 1024, .y = 768 };
    const center = cam.worldToLogical(&vp, cam.pos);
    try testz.expectTrue(approxEq(center.x, 512.0));
    try testz.expectTrue(approxEq(center.y, 384.0));
    const r = cam.viewRect(&vp);
    try testz.expectTrue(approxEq(r.r - r.l, 1024.0));
}
