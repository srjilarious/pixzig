const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const FpsCounter = pixzig.utils.FpsCounter;
const Delay = pixzig.utils.Delay;
const DelayF = pixzig.utils.DelayF;
const baseNameFromPath = pixzig.utils.baseNameFromPath;
const addExtension = pixzig.utils.addExtension;

// --- FpsCounter ---

pub fn fpsCounterInitTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const counter = FpsCounter.init();
    try testz.expectEqual(counter.mFps, 0);
    try testz.expectEqual(counter.mFrames, 0);
    try testz.expectEqual(counter.mElapsed, 0.0);
}

pub fn fpsCounterUpdateNotTriggeredBeforeThresholdTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var counter = FpsCounter.init();
    const triggered = counter.update(500.0);
    try testz.expectFalse(triggered);
    try testz.expectEqual(counter.fps(), 0);
}

pub fn fpsCounterUpdateTriggeredAfterOneSecondTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var counter = FpsCounter.init();

    // Simulate 60 render ticks before the second elapses.
    for (0..60) |_| counter.renderTick();

    const triggered = counter.update(1001.0);
    try testz.expectTrue(triggered);
    try testz.expectEqual(counter.fps(), 60);
}

pub fn fpsCounterFramesResetAfterTriggerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var counter = FpsCounter.init();
    for (0..30) |_| counter.renderTick();
    _ = counter.update(1001.0); // trigger, mFrames resets to 0

    // After reset, a sub-second update should not trigger again.
    const triggered = counter.update(400.0);
    try testz.expectFalse(triggered);
    // fps is still the snapshotted value from the trigger.
    try testz.expectEqual(counter.fps(), 30);
}

pub fn fpsCounterAccumulatesElapsedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var counter = FpsCounter.init();
    for (0..10) |_| counter.renderTick();

    // Four sub-second updates should not trigger.
    try testz.expectFalse(counter.update(300.0));
    try testz.expectFalse(counter.update(300.0));
    try testz.expectFalse(counter.update(300.0));

    // The fourth pushes over 1000 ms total.
    const triggered = counter.update(200.0);
    try testz.expectTrue(triggered);
    try testz.expectEqual(counter.fps(), 10);
}

pub fn fpsCounterElapsedSubtractedOnTriggerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var counter = FpsCounter.init();
    // Overshoot by 200 ms so that 200 ms carry over to the next window.
    _ = counter.update(1200.0);
    // Elapsed should now be 200 (1200 - 1000).
    try testz.expectEqual(counter.mElapsed, 200.0);
}

// --- Delay ---

pub fn delayNotTriggeredBeforeMaxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = Delay{ .max = 10 };
    try testz.expectFalse(d.update(5));
    try testz.expectEqual(d.curr, 5);
}

pub fn delayTriggeredWhenExceedingMaxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = Delay{ .max = 10 };
    try testz.expectTrue(d.update(11));
}

pub fn delayResetsAfterTriggerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = Delay{ .max = 10 };
    _ = d.update(11); // trigger
    try testz.expectEqual(d.curr, 0);
    // Should not trigger immediately after reset.
    try testz.expectFalse(d.update(5));
}

pub fn delayAccumulatesAcrossCallsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = Delay{ .max = 10 };
    try testz.expectFalse(d.update(4));
    try testz.expectFalse(d.update(4));
    try testz.expectTrue(d.update(4)); // 12 > 10
}

pub fn delayExactlyAtMaxNotTriggeredTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = Delay{ .max = 10 };
    // curr > max uses strict greater-than, so exactly at max does not trigger.
    try testz.expectFalse(d.update(10));
}

// --- DelayF ---

pub fn delayFNotTriggeredBeforeMaxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = DelayF{ .max = 100.0 };
    try testz.expectFalse(d.update(50.0));
    try testz.expectEqual(d.curr, 50.0);
}

pub fn delayFTriggeredWhenExceedingMaxTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = DelayF{ .max = 100.0 };
    try testz.expectTrue(d.update(101.0));
}

pub fn delayFResetsAfterTriggerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = DelayF{ .max = 100.0 };
    _ = d.update(101.0);
    try testz.expectEqual(d.curr, 0.0);
    try testz.expectFalse(d.update(50.0));
}

pub fn delayFAccumulatesAcrossCallsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var d = DelayF{ .max = 1.0 };
    try testz.expectFalse(d.update(0.4));
    try testz.expectFalse(d.update(0.4));
    try testz.expectTrue(d.update(0.4)); // 1.2 > 1.0
}

// --- baseNameFromPath ---

pub fn baseNameFromPathWithDirAndExtTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const name = baseNameFromPath("assets/foo.png");
    try testz.expectEqualStr(name, "foo");
}

pub fn baseNameFromPathNoDirectoryTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const name = baseNameFromPath("foo.png");
    try testz.expectEqualStr(name, "foo");
}

pub fn baseNameFromPathDeepPathTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const name = baseNameFromPath("a/b/c.lua");
    try testz.expectEqualStr(name, "c");
}

pub fn baseNameFromPathNoExtTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const name = baseNameFromPath("noext");
    try testz.expectEqualStr(name, "noext");
}

pub fn baseNameFromPathDirNoExtTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const name = baseNameFromPath("assets/noext");
    try testz.expectEqualStr(name, "noext");
}

// --- addExtension ---

pub fn addExtensionAppendsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const result = try addExtension(alloc, "foo", ".png");
    defer alloc.free(result);
    try testz.expectEqualStr(result, "foo.png");
}

pub fn addExtensionFullPathTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const result = try addExtension(alloc, "assets/atlas", ".json");
    defer alloc.free(result);
    try testz.expectEqualStr(result, "assets/atlas.json");
}
