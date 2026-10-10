const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const FpsCounter = pixzig.utils.FpsCounter;
const Timer = pixzig.utils.Timer;
const baseNameFromPath = pixzig.utils.baseNameFromPath;
const addExtension = pixzig.utils.addExtension;

// --- FpsCounter ---

pub fn fpsCounterInitTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const counter = FpsCounter.init();
    try testz.expectEqual(counter.lastFps, 0);
    try testz.expectEqual(counter.windowFrames, 0);
    try testz.expectEqual(counter.elapsedMs, 0.0);
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
    _ = counter.update(1001.0); // trigger, windowFrames resets to 0

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
    try testz.expectEqual(counter.elapsedMs, 200.0);
}

// --- Timer ---

pub fn timerNotFiredBeforePeriodTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var t: Timer(u32) = .{ .period = 10 };
    try testz.expectFalse(t.update(5));
    try testz.expectEqual(t.elapsed, 5);
}

pub fn timerFiresAtPeriodTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    // Ticking by one fires on exactly the period-th tick.
    var t: Timer(u32) = .{ .period = 3 };
    try testz.expectFalse(t.update(1));
    try testz.expectFalse(t.update(1));
    try testz.expectTrue(t.update(1));
    try testz.expectEqual(t.elapsed, 0);
}

pub fn timerCarriesOvershootTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var t: Timer(f64) = .{ .period = 100.0 };
    try testz.expectTrue(t.update(130.0));
    try testz.expectEqual(t.elapsed, 30.0);
    // The 30 ms overshoot counts toward the next period.
    try testz.expectTrue(t.update(70.0));
    try testz.expectEqual(t.elapsed, 0.0);
}

pub fn timerResetAndProgressTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var t: Timer(f32) = .{ .period = 4.0 };
    _ = t.update(1.0);
    try testz.expectEqual(t.progress(), 0.25);
    t.reset();
    try testz.expectEqual(t.progress(), 0.0);

    var ticks: Timer(u8) = .{ .period = 4 };
    _ = ticks.update(2);
    try testz.expectEqual(ticks.progress(), 0.5);
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
