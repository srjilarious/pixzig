const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const screenshot = pixzig.screenshot;
const InputEvent = screenshot.InputEvent;
const InputManager = pixzig.input.InputManager;

const StepMs = 10.0;

pub fn parseSizeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const size = try screenshot.parseSize("800x480");
    try testz.expectEqual(size.x, 800);
    try testz.expectEqual(size.y, 480);

    try testz.expectError(screenshot.parseSize("800"), error.BadScreenshotSize);
    try testz.expectError(screenshot.parseSize("800x480x2"), error.BadScreenshotSize);
    try testz.expectError(screenshot.parseSize("wide x tall"), error.BadScreenshotSize);
}

/// A tap is a press and a release one step later.
pub fn parseInputTapTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const events = try screenshot.parseInput(alloc, "300 tap F1", StepMs);
    defer alloc.free(events);

    try testz.expectEqual(events.len, 2);
    try testz.expectEqual(events[0].atMs, 300.0);
    try testz.expectTrue(events[0].action == .keyDown and events[0].action.keyDown == .F1);
    try testz.expectEqual(events[1].atMs, 310.0);
    try testz.expectTrue(events[1].action == .keyUp and events[1].action.keyUp == .F1);
}

/// Text keeps its own spacing and arrives one codepoint per step.
pub fn parseInputTextTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const events = try screenshot.parseInput(alloc, "100 text a bé", StepMs);
    defer alloc.free(events);

    const expected = [_][]const u8{ "a", " ", "b", "é" };
    try testz.expectEqual(events.len, expected.len);
    for (events, expected, 0..) |ev, want, i| {
        try testz.expectEqual(ev.atMs, 100.0 + @as(f64, @floatFromInt(i)) * StepMs);
        try testz.expectEqualStr(ev.action.text, want);
    }
}

/// Entries come back sorted by time, keeping script order for ties.
pub fn parseInputSortsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const events = try screenshot.parseInput(alloc, "500 down a; 100 move 3 4; ; 100 click left; 500 up b", StepMs);
    defer alloc.free(events);

    try testz.expectEqual(events.len, 5);
    try testz.expectTrue(events[0].action == .move);
    try testz.expectEqual(events[0].action.move.x, 3.0);
    try testz.expectEqual(events[0].action.move.y, 4.0);
    try testz.expectTrue(events[1].action == .buttonDown);
    try testz.expectTrue(events[2].action == .buttonUp);
    try testz.expectEqual(events[2].atMs, 110.0);
    try testz.expectTrue(events[3].action == .keyDown and events[3].action.keyDown == .a);
    try testz.expectTrue(events[4].action == .keyUp and events[4].action.keyUp == .b);
}

pub fn parseInputErrorsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    try testz.expectError(screenshot.parseInput(alloc, "100 tap not_a_key", StepMs), error.BadScreenshotInput);
    try testz.expectError(screenshot.parseInput(alloc, "soon tap a", StepMs), error.BadScreenshotInput);
    try testz.expectError(screenshot.parseInput(alloc, "100 wiggle a", StepMs), error.BadScreenshotInput);
    try testz.expectError(screenshot.parseInput(alloc, "100 move 3", StepMs), error.BadScreenshotInput);
    try testz.expectError(screenshot.parseInput(alloc, "100 click nose", StepMs), error.BadScreenshotInput);
}

/// Only events due by the given time reach the input manager, so a tap is
/// a press on one tick and a release on the next.
pub fn applyInputTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var hook: screenshot.ScreenshotHook = .{
        .alloc = alloc,
        .path = "unused.png",
        .captureAtMs = 1000,
        .windowSize = null,
        .seed = 1,
        .events = try screenshot.parseInput(alloc, "20 tap space; 20 text q", StepMs),
    };
    defer hook.deinit();

    var inputs = InputManager.init(.{});
    defer inputs.deinit();

    hook.applyInput(&inputs, 10.0);
    try testz.expectFalse(inputs.keyboard.currKeys().down(.space));

    hook.applyInput(&inputs, 20.0);
    try testz.expectTrue(inputs.keyboard.currKeys().down(.space));
    _ = inputs.keyboard.update();
    var buf: [8]u8 = undefined;
    try testz.expectEqualStr(buf[0..inputs.keyboard.text(&buf)], "q");
    inputs.finishTick();

    hook.applyInput(&inputs, 30.0);
    try testz.expectFalse(inputs.keyboard.currKeys().down(.space));
    try testz.expectFalse(hook.due(990.0));
    try testz.expectTrue(hook.due(1000.0));
}
