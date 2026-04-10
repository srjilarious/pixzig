const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const FpsCounter = pixzig.utils.FpsCounter;
const Delay = pixzig.utils.Delay;
const DelayF = pixzig.utils.DelayF;
const baseNameFromPath = pixzig.utils.baseNameFromPath;
const addExtension = pixzig.utils.addExtension;

// --- FpsCounter ---

pub fn fpsCounterInitTest() !void {
    const counter = FpsCounter.init();
    try testz.expectEqual(counter.mFps, 0);
    try testz.expectEqual(counter.mFrames, 0);
    try testz.expectEqual(counter.mElapsed, 0.0);
}

pub fn fpsCounterUpdateNotTriggeredBeforeThresholdTest() !void {
    var counter = FpsCounter.init();
    const triggered = counter.update(500.0);
    try testz.expectFalse(triggered);
    try testz.expectEqual(counter.fps(), 0);
}

pub fn fpsCounterUpdateTriggeredAfterOneSecondTest() !void {
    var counter = FpsCounter.init();

    // Simulate 60 render ticks before the second elapses.
    for (0..60) |_| counter.renderTick();

    const triggered = counter.update(1001.0);
    try testz.expectTrue(triggered);
    try testz.expectEqual(counter.fps(), 60);
}

pub fn fpsCounterFramesResetAfterTriggerTest() !void {
    var counter = FpsCounter.init();
    for (0..30) |_| counter.renderTick();
    _ = counter.update(1001.0); // trigger, mFrames resets to 0

    // After reset, a sub-second update should not trigger again.
    const triggered = counter.update(400.0);
    try testz.expectFalse(triggered);
    // fps is still the snapshotted value from the trigger.
    try testz.expectEqual(counter.fps(), 30);
}

pub fn fpsCounterAccumulatesElapsedTest() !void {
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

pub fn fpsCounterElapsedSubtractedOnTriggerTest() !void {
    var counter = FpsCounter.init();
    // Overshoot by 200 ms so that 200 ms carry over to the next window.
    _ = counter.update(1200.0);
    // Elapsed should now be 200 (1200 - 1000).
    try testz.expectEqual(counter.mElapsed, 200.0);
}

// --- Delay ---

pub fn delayNotTriggeredBeforeMaxTest() !void {
    var d = Delay{ .max = 10 };
    try testz.expectFalse(d.update(5));
    try testz.expectEqual(d.curr, 5);
}

pub fn delayTriggeredWhenExceedingMaxTest() !void {
    var d = Delay{ .max = 10 };
    try testz.expectTrue(d.update(11));
}

pub fn delayResetsAfterTriggerTest() !void {
    var d = Delay{ .max = 10 };
    _ = d.update(11); // trigger
    try testz.expectEqual(d.curr, 0);
    // Should not trigger immediately after reset.
    try testz.expectFalse(d.update(5));
}

pub fn delayAccumulatesAcrossCallsTest() !void {
    var d = Delay{ .max = 10 };
    try testz.expectFalse(d.update(4));
    try testz.expectFalse(d.update(4));
    try testz.expectTrue(d.update(4)); // 12 > 10
}

pub fn delayExactlyAtMaxNotTriggeredTest() !void {
    var d = Delay{ .max = 10 };
    // curr > max uses strict greater-than, so exactly at max does not trigger.
    try testz.expectFalse(d.update(10));
}

// --- DelayF ---

pub fn delayFNotTriggeredBeforeMaxTest() !void {
    var d = DelayF{ .max = 100.0 };
    try testz.expectFalse(d.update(50.0));
    try testz.expectEqual(d.curr, 50.0);
}

pub fn delayFTriggeredWhenExceedingMaxTest() !void {
    var d = DelayF{ .max = 100.0 };
    try testz.expectTrue(d.update(101.0));
}

pub fn delayFResetsAfterTriggerTest() !void {
    var d = DelayF{ .max = 100.0 };
    _ = d.update(101.0);
    try testz.expectEqual(d.curr, 0.0);
    try testz.expectFalse(d.update(50.0));
}

pub fn delayFAccumulatesAcrossCallsTest() !void {
    var d = DelayF{ .max = 1.0 };
    try testz.expectFalse(d.update(0.4));
    try testz.expectFalse(d.update(0.4));
    try testz.expectTrue(d.update(0.4)); // 1.2 > 1.0
}

// --- baseNameFromPath ---

pub fn baseNameFromPathWithDirAndExtTest() !void {
    const name = baseNameFromPath("assets/foo.png");
    try testz.expectEqualStr(name, "foo");
}

pub fn baseNameFromPathNoDirectoryTest() !void {
    const name = baseNameFromPath("foo.png");
    try testz.expectEqualStr(name, "foo");
}

pub fn baseNameFromPathDeepPathTest() !void {
    const name = baseNameFromPath("a/b/c.lua");
    try testz.expectEqualStr(name, "c");
}

pub fn baseNameFromPathNoExtTest() !void {
    const name = baseNameFromPath("noext");
    try testz.expectEqualStr(name, "noext");
}

pub fn baseNameFromPathDirNoExtTest() !void {
    const name = baseNameFromPath("assets/noext");
    try testz.expectEqualStr(name, "noext");
}

// --- addExtension ---

pub fn addExtensionAppendsTest() !void {
    const result = try addExtension(std.heap.page_allocator, "foo", ".png");
    defer std.heap.page_allocator.free(result);
    try testz.expectEqualStr(result, "foo.png");
}

pub fn addExtensionFullPathTest() !void {
    const result = try addExtension(std.heap.page_allocator, "assets/atlas", ".json");
    defer std.heap.page_allocator.free(result);
    try testz.expectEqualStr(result, "assets/atlas.json");
}
