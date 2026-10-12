//! An opt-in hook that lets a tool drive an `AppRunner` app to a known
//! state, capture one frame to a PNG and exit. `tools/screenshots.py` uses
//! it to regenerate the doc screenshots.
//!
//! It is compiled in only when `EngineOptions.screenshotHook` is set, and
//! does nothing unless `PIXZIG_SCREENSHOT` is in the environment:
//!
//! - `PIXZIG_SCREENSHOT`: the PNG path to write.
//! - `PIXZIG_SCREENSHOT_MS`: game time to capture at, default 1000.
//! - `PIXZIG_SCREENSHOT_SIZE`: window size as `WxH`, overriding the app's.
//! - `PIXZIG_SCREENSHOT_SEED`: seed for `Engine.rng`, default 1.
//! - `PIXZIG_SCREENSHOT_INPUT`: a `;`-separated input script, see `parseInput`.
//!
//! While the hook is active the runner runs exactly one update per frame,
//! so game time is a tick count and a capture lands on the same tick every
//! run, however fast the machine renders.

const std = @import("std");
const common = @import("./common.zig");
const input = @import("./input.zig");

const Vec2I = common.Vec2I;
const Key = input.Key;
const MouseButton = input.MouseButton;
const InputManager = input.InputManager;

/// One scripted input, applied at the first tick at or after `atMs`.
pub const InputEvent = struct {
    atMs: f64,
    action: Action,

    pub const Action = union(enum) {
        keyDown: Key,
        keyUp: Key,
        text: []const u8,
        /// Cursor position in window coordinates.
        move: struct { x: f32, y: f32 },
        buttonDown: MouseButton,
        buttonUp: MouseButton,
    };
};

pub const ScreenshotHook = struct {
    alloc: std.mem.Allocator,
    path: []const u8,
    captureAtMs: f64,
    windowSize: ?Vec2I,
    seed: u64,
    events: []InputEvent,
    nextEvent: usize = 0,

    const Self = @This();

    /// Reads the hook's settings from the environment. Returns null when
    /// `PIXZIG_SCREENSHOT` is unset. `stepMs` is the runner's update step,
    /// which taps and clicks use to space their release one tick after the
    /// press.
    pub fn fromEnv(alloc: std.mem.Allocator, stepMs: f64) !?Self {
        const path = getEnv("PIXZIG_SCREENSHOT") orelse return null;

        const captureAtMs = if (getEnv("PIXZIG_SCREENSHOT_MS")) |ms|
            std.fmt.parseFloat(f64, ms) catch return error.BadScreenshotMs
        else
            1000.0;

        const windowSize = if (getEnv("PIXZIG_SCREENSHOT_SIZE")) |size|
            try parseSize(size)
        else
            null;

        const seed = if (getEnv("PIXZIG_SCREENSHOT_SEED")) |s|
            std.fmt.parseInt(u64, s, 10) catch return error.BadScreenshotSeed
        else
            1;

        const events = if (getEnv("PIXZIG_SCREENSHOT_INPUT")) |script|
            try parseInput(alloc, script, stepMs)
        else
            try alloc.alloc(InputEvent, 0);

        return .{
            .alloc = alloc,
            .path = path,
            .captureAtMs = captureAtMs,
            .windowSize = windowSize,
            .seed = seed,
            .events = events,
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.events);
    }

    /// Feeds every scripted event due by `gameMs` into `inputs`. Call
    /// before `InputManager.update` so the tick sees them like real events.
    pub fn applyInput(self: *Self, inputs: *InputManager, gameMs: f64) void {
        while (self.nextEvent < self.events.len and self.events[self.nextEvent].atMs <= gameMs) {
            switch (self.events[self.nextEvent].action) {
                .keyDown => |k| inputs.keyboard.setKey(k, k, true),
                .keyUp => |k| inputs.keyboard.setKey(k, k, false),
                .text => |t| inputs.keyboard.pushText(t),
                .move => |p| inputs.mouse.currPtr().setRawPos(p.x, p.y),
                .buttonDown => |b| inputs.mouse.currPtr().set(b, true),
                .buttonUp => |b| inputs.mouse.currPtr().set(b, false),
            }
            self.nextEvent += 1;
        }
    }

    /// Whether the frame rendered after `gameMs` of game time is the one
    /// to capture.
    pub fn due(self: *const Self, gameMs: f64) bool {
        return gameMs >= self.captureAtMs;
    }
};

fn getEnv(name: [*:0]const u8) ?[]const u8 {
    const val = std.c.getenv(name) orelse return null;
    return std.mem.span(val);
}

/// Parses a `WxH` window size, e.g. `800x480`.
pub fn parseSize(text: []const u8) !Vec2I {
    var it = std.mem.splitScalar(u8, text, 'x');
    const w = it.next() orelse return error.BadScreenshotSize;
    const h = it.next() orelse return error.BadScreenshotSize;
    if (it.next() != null) return error.BadScreenshotSize;
    return .{
        .x = std.fmt.parseInt(i32, w, 10) catch return error.BadScreenshotSize,
        .y = std.fmt.parseInt(i32, h, 10) catch return error.BadScreenshotSize,
    };
}

/// Parses an input script into events sorted by time. Entries are
/// separated by `;` and each is `<ms> <verb> <args>`:
///
/// - `tap <key>`: presses a key and releases it one tick later.
/// - `down <key>` / `up <key>`: presses or releases a key.
/// - `text <utf8>`: types the rest of the entry one codepoint per tick, so
///   it can't hold a `;`.
/// - `move <x> <y>`: puts the cursor at a window-coordinate position.
/// - `click <button>`: presses a mouse button and releases it one tick later.
/// - `mdown <button>` / `mup <button>`: presses or releases a mouse button.
///
/// Keys and buttons are `Key` and `MouseButton` tag names, e.g.
/// `"300 tap f1; 500 text print(1); 600 tap enter"`.
pub fn parseInput(alloc: std.mem.Allocator, script: []const u8, stepMs: f64) ![]InputEvent {
    var events: std.ArrayList(InputEvent) = .empty;
    errdefer events.deinit(alloc);

    var entries = std.mem.splitScalar(u8, script, ';');
    while (entries.next()) |raw| {
        const entry = std.mem.trim(u8, raw, " \t\n");
        if (entry.len == 0) continue;

        var words = std.mem.tokenizeScalar(u8, entry, ' ');
        const msText = words.next() orelse return error.BadScreenshotInput;
        const ms = std.fmt.parseFloat(f64, msText) catch return error.BadScreenshotInput;
        const verb = words.next() orelse return error.BadScreenshotInput;

        if (std.mem.eql(u8, verb, "text")) {
            // Everything after the single space following the verb, so
            // the typed text keeps its own spacing.
            const text = if (words.index < entry.len) entry[words.index + 1 ..] else "";
            // One codepoint per tick, the way a keyboard delivers it.
            var view = std.unicode.Utf8View.init(text) catch return error.BadScreenshotInput;
            var it = view.iterator();
            var i: f64 = 0;
            while (it.nextCodepointSlice()) |cp| : (i += 1) {
                try events.append(alloc, .{ .atMs = ms + i * stepMs, .action = .{ .text = cp } });
            }
            continue;
        }

        const arg = words.next() orelse return error.BadScreenshotInput;
        if (std.mem.eql(u8, verb, "tap")) {
            const key = try parseKey(arg);
            try events.append(alloc, .{ .atMs = ms, .action = .{ .keyDown = key } });
            try events.append(alloc, .{ .atMs = ms + stepMs, .action = .{ .keyUp = key } });
        } else if (std.mem.eql(u8, verb, "down")) {
            try events.append(alloc, .{ .atMs = ms, .action = .{ .keyDown = try parseKey(arg) } });
        } else if (std.mem.eql(u8, verb, "up")) {
            try events.append(alloc, .{ .atMs = ms, .action = .{ .keyUp = try parseKey(arg) } });
        } else if (std.mem.eql(u8, verb, "move")) {
            const yText = words.next() orelse return error.BadScreenshotInput;
            const x = std.fmt.parseFloat(f32, arg) catch return error.BadScreenshotInput;
            const y = std.fmt.parseFloat(f32, yText) catch return error.BadScreenshotInput;
            try events.append(alloc, .{ .atMs = ms, .action = .{ .move = .{ .x = x, .y = y } } });
        } else if (std.mem.eql(u8, verb, "click")) {
            const btn = try parseButton(arg);
            try events.append(alloc, .{ .atMs = ms, .action = .{ .buttonDown = btn } });
            try events.append(alloc, .{ .atMs = ms + stepMs, .action = .{ .buttonUp = btn } });
        } else if (std.mem.eql(u8, verb, "mdown")) {
            try events.append(alloc, .{ .atMs = ms, .action = .{ .buttonDown = try parseButton(arg) } });
        } else if (std.mem.eql(u8, verb, "mup")) {
            try events.append(alloc, .{ .atMs = ms, .action = .{ .buttonUp = try parseButton(arg) } });
        } else {
            std.log.err("Unknown screenshot input verb '{s}'", .{verb});
            return error.BadScreenshotInput;
        }
    }

    // Insertion sort is stable, so events at the same time keep their
    // script order.
    std.sort.insertion(InputEvent, events.items, {}, struct {
        fn lessThan(_: void, a: InputEvent, b: InputEvent) bool {
            return a.atMs < b.atMs;
        }
    }.lessThan);
    return events.toOwnedSlice(alloc);
}

fn parseKey(name: []const u8) !Key {
    return std.meta.stringToEnum(Key, name) orelse {
        std.log.err("Unknown screenshot input key '{s}'", .{name});
        return error.BadScreenshotInput;
    };
}

fn parseButton(name: []const u8) !MouseButton {
    return std.meta.stringToEnum(MouseButton, name) orelse {
        std.log.err("Unknown screenshot input mouse button '{s}'", .{name});
        return error.BadScreenshotInput;
    };
}
