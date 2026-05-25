const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const windowing = pixzig.windowing;
const Viewport = windowing.Viewport;
const ScalePolicy = windowing.ScalePolicy;
const Vec2F = pixzig.Vec2F;

// --- helpers ----------------------------------------------------------------

fn approxEq(a: f32, b: f32) bool {
    return @abs(a - b) < 0.01;
}

// --- stretch ----------------------------------------------------------------

pub fn viewportStretchFillsFramebufferTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const vp = Viewport.init(.{ .x = 800, .y = 600 }, .{ .x = 800, .y = 600 }, .stretch);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 800), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 600), vp.viewport_px.b);
    try testz.expectTrue(approxEq(vp.scale.x, 1.0));
    try testz.expectTrue(approxEq(vp.scale.y, 1.0));
}

pub fn viewportStretchScalesIndependentlyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // 320x180 logical into 1920x1080 framebuffer -> x scale=6, y scale=6
    const vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 1920, .y = 1080 }, .stretch);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 1920), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 1080), vp.viewport_px.b);
    try testz.expectTrue(approxEq(vp.scale.x, 6.0));
    try testz.expectTrue(approxEq(vp.scale.y, 6.0));
}

// --- fit --------------------------------------------------------------------

pub fn viewportFitExactAspectTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // 320x180 in 1920x1080: both axes scale 6, no letterbox
    const vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 1920, .y = 1080 }, .fit);
    try testz.expectTrue(approxEq(vp.scale.x, 6.0));
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 1920), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 1080), vp.viewport_px.b);
}

pub fn viewportFitPillarboxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // 320x240 in 1920x1080: x scale=6, y scale=4.5 -> fit=4.5
    // vw=1440, vh=1080, ox=240, oy=0
    const vp = Viewport.init(.{ .x = 320, .y = 240 }, .{ .x = 1920, .y = 1080 }, .fit);
    try testz.expectTrue(approxEq(vp.scale.x, 4.5));
    try testz.expectEqual(@as(i32, 240), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 1680), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 1080), vp.viewport_px.b);
}

pub fn viewportFitLetterboxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // 320x180 in 1024x768: x=3.2, y=4.266 -> fit=3.2
    // vw=1024, vh=576, ox=0, oy=96
    const vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 1024, .y = 768 }, .fit);
    try testz.expectTrue(approxEq(vp.scale.x, 3.2));
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 96), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 1024), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 672), vp.viewport_px.b);
}

// --- integer_fit ------------------------------------------------------------

pub fn viewportIntegerFitExactTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // 320x180 in 1920x1080: floor(6)=6, floor(6)=6 -> s=6
    const vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 1920, .y = 1080 }, .integer_fit);
    try testz.expectTrue(approxEq(vp.scale.x, 6.0));
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 1920), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 1080), vp.viewport_px.b);
}

pub fn viewportIntegerFitLetterboxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // 320x240 in 1920x1080: floor(6)=6, floor(4.5)=4 -> s=4
    // vw=1280, vh=960, ox=320, oy=60
    const vp = Viewport.init(.{ .x = 320, .y = 240 }, .{ .x = 1920, .y = 1080 }, .integer_fit);
    try testz.expectTrue(approxEq(vp.scale.x, 4.0));
    try testz.expectEqual(@as(i32, 320), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 60), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 1600), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 1020), vp.viewport_px.b);
}

pub fn viewportIntegerFitMinScaleClampTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Window smaller than logical: floor(100/320)=0 -> clamped to 1
    const vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 100, .y = 100 }, .integer_fit);
    try testz.expectTrue(approxEq(vp.scale.x, 1.0));
    try testz.expectTrue(approxEq(vp.scale.y, 1.0));
}

pub fn viewportIntegerFit1600x900Test(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // 320x180 in 1600x900: floor(5)=5, floor(5)=5 -> s=5
    const vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 1600, .y = 900 }, .integer_fit);
    try testz.expectTrue(approxEq(vp.scale.x, 5.0));
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 1600), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 900), vp.viewport_px.b);
}

// --- coordinate conversion --------------------------------------------------

pub fn viewportFramebufferToLogicalNullInLetterboxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // fit: 320x240 in 1920x1080 -> pillarbox at x<240 and x>=1680
    const vp = Viewport.init(.{ .x = 320, .y = 240 }, .{ .x = 1920, .y = 1080 }, .fit);
    try testz.expectTrue(vp.framebufferToLogical(.{ .x = 100, .y = 500 }) == null);
    try testz.expectTrue(vp.framebufferToLogical(.{ .x = 1700, .y = 500 }) == null);
}

pub fn viewportFramebufferToLogicalValidTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // fit: 320x240 in 1920x1080 -> scale=4.5, viewport_px=(240,0,1680,1080)
    // fb (240+45, 0+45) -> logical (10, 10)
    const vp = Viewport.init(.{ .x = 320, .y = 240 }, .{ .x = 1920, .y = 1080 }, .fit);
    const result = vp.framebufferToLogical(.{ .x = 285, .y = 45 });
    try testz.expectTrue(result != null);
    if (result) |r| {
        try testz.expectTrue(approxEq(r.x, 10.0));
        try testz.expectTrue(approxEq(r.y, 10.0));
    }
}

pub fn viewportLogicalToFramebufferRoundTripTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const vp = Viewport.init(.{ .x = 320, .y = 240 }, .{ .x = 1920, .y = 1080 }, .fit);
    const logical = Vec2F{ .x = 100, .y = 50 };
    const fb = vp.logicalToFramebuffer(logical);
    const back = vp.framebufferToLogical(fb);
    try testz.expectTrue(back != null);
    if (back) |b| {
        try testz.expectTrue(approxEq(b.x, logical.x));
        try testz.expectTrue(approxEq(b.y, logical.y));
    }
}

pub fn viewportLogicalToFramebufferIntegerFitTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // integer_fit: 320x240 in 1920x1080, scale=4, viewport_px=(320,60,...)
    // logical (0,0) -> fb (320, 60)
    const vp = Viewport.init(.{ .x = 320, .y = 240 }, .{ .x = 1920, .y = 1080 }, .integer_fit);
    const fb = vp.logicalToFramebuffer(.{ .x = 0, .y = 0 });
    try testz.expectTrue(approxEq(fb.x, 320.0));
    try testz.expectTrue(approxEq(fb.y, 60.0));
}

// --- updateFramebufferSize --------------------------------------------------

pub fn viewportUpdateFramebufferSizeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 1920, .y = 1080 }, .integer_fit);
    try testz.expectTrue(approxEq(vp.scale.x, 6.0));

    vp.updateFramebufferSize(.{ .x = 1600, .y = 900 });
    try testz.expectTrue(approxEq(vp.scale.x, 5.0));
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 0), vp.viewport_px.t);
}

pub fn viewportUpdateFramebufferSizeLetterboxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // After resize to 1024x768: 320x180, integer_fit
    // floor(1024/320)=3, floor(768/180)=4 -> s=3
    // vw=960, vh=540, ox=32, oy=114
    var vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 1920, .y = 1080 }, .integer_fit);
    vp.updateFramebufferSize(.{ .x = 1024, .y = 768 });
    try testz.expectTrue(approxEq(vp.scale.x, 3.0));
    try testz.expectEqual(@as(i32, 32), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 114), vp.viewport_px.t);
}

// --- fixed ------------------------------------------------------------------

pub fn viewportFixedScaleTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // fixed 3.0: 320x180 -> 960x540, centered in 1920x1080 -> ox=480, oy=270
    const vp = Viewport.init(.{ .x = 320, .y = 180 }, .{ .x = 1920, .y = 1080 }, .{ .fixed = 3.0 });
    try testz.expectTrue(approxEq(vp.scale.x, 3.0));
    try testz.expectEqual(@as(i32, 480), vp.viewport_px.l);
    try testz.expectEqual(@as(i32, 270), vp.viewport_px.t);
    try testz.expectEqual(@as(i32, 1440), vp.viewport_px.r);
    try testz.expectEqual(@as(i32, 810), vp.viewport_px.b);
}
