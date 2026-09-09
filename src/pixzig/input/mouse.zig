const std = @import("std");
const keys = @import("./keys.zig");
const common = @import("../common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

pub const MouseButton = keys.MouseButton;
pub const NumMouseButtons = keys.NumMouseButtons;

pub const MouseState = struct {
    buttons: std.StaticBitSet(NumMouseButtons),
    /// Cursor position in window coordinates, as SDL reports it.
    raw_pos: Vec2F,
    /// Cursor position in framebuffer pixels (raw_pos * scale_factor).
    /// Suitable for passing to any Viewport.framebufferToLogical() call.
    fb_pos: Vec2F,
    /// Logical game coordinates after viewport mapping.  Set to (-1, -1) when
    /// the cursor is outside the viewport (letterbox / pillarbox region).
    logical_pos: Vec2F,
    /// Mouse movement accumulated during the current tick, in SDL window
    /// coordinates. In captured/relative mode this is the unbounded motion.
    raw_delta: Vec2F,
    /// Scroll wheel delta accumulated during the current tick (x = horizontal, y = vertical).
    scroll_delta: Vec2F,

    pub fn init() MouseState {
        const buttons = std.StaticBitSet(NumMouseButtons).empty;
        return .{
            .buttons = buttons,
            .raw_pos = .{ .x = 0, .y = 0 },
            .fb_pos = .{ .x = 0, .y = 0 },
            .logical_pos = .{ .x = -1, .y = -1 },
            .raw_delta = .{ .x = 0, .y = 0 },
            .scroll_delta = .{ .x = 0, .y = 0 },
        };
    }

    pub fn down(self: *const MouseState, keyIdx: usize) bool {
        return self.buttons.isSet(keyIdx);
    }

    pub fn set(self: *MouseState, btn: MouseButton, val: bool) void {
        self.setIdx(keys.mouseButtonIndex(btn), val);
    }

    pub fn setIdx(self: *MouseState, btnIdx: usize, val: bool) void {
        if (val) {
            self.buttons.set(btnIdx);
        } else {
            self.buttons.unset(btnIdx);
        }
    }

    pub fn setRawPos(self: *MouseState, x: f32, y: f32) void {
        self.raw_pos = .{ .x = x, .y = y };
    }

    pub fn addRawMotion(self: *MouseState, x: f32, y: f32, dx: f32, dy: f32) void {
        self.raw_pos = .{ .x = x, .y = y };
        self.raw_delta.x += dx;
        self.raw_delta.y += dy;
    }

    pub fn clear(self: *MouseState) void {
        self.buttons.setRangeValue(.{ .start = 0, .end = NumMouseButtons }, false);
        self.raw_pos = .{ .x = 0, .y = 0 };
        self.fb_pos = .{ .x = 0, .y = 0 };
        self.logical_pos = .{ .x = -1, .y = -1 };
        self.raw_delta = .{ .x = 0, .y = 0 };
        self.scroll_delta = .{ .x = 0, .y = 0 };
    }
};

/// Tracks the mouse across ticks. Like `Keyboard`, this is fed by SDL
/// events through `InputManager.handleEvent` rather than polled, so button
/// state and cursor position update the moment the event pump runs.
pub const Mouse = struct {
    currIdx: usize,
    prevIdx: usize,
    mouseBuffers: [2]MouseState,

    pub fn init() Mouse {
        return .{
            .currIdx = 0,
            .prevIdx = 1,
            .mouseBuffers = .{
                MouseState.init(),
                MouseState.init(),
            },
        };
    }

    /// Ends a tick: the current state becomes the previous state for the
    /// next tick's edge detection, and the accumulated scroll delta is
    /// consumed.
    pub fn finishTick(self: *Mouse) void {
        self.mouseBuffers[self.prevIdx] = self.mouseBuffers[self.currIdx];
        self.curr_mut().raw_delta = .{ .x = 0, .y = 0 };
        self.curr_mut().scroll_delta = .{ .x = 0, .y = 0 };
    }

    /// Drops all button state, for window focus loss where the
    /// button-up events would otherwise never arrive.
    pub fn clear(self: *Mouse) void {
        self.mouseBuffers[0].clear();
        self.mouseBuffers[1].clear();
    }

    pub fn curr(self: *const Mouse) *const MouseState {
        return &self.mouseBuffers[self.currIdx];
    }

    pub fn curr_mut(self: *Mouse) *MouseState {
        return &self.mouseBuffers[self.currIdx];
    }

    pub fn prev(self: *const Mouse) *const MouseState {
        return &self.mouseBuffers[self.prevIdx];
    }

    pub fn up(self: *const Mouse, btn: MouseButton) bool {
        return !self.curr().down(keys.mouseButtonIndex(btn));
    }

    pub fn down(self: *const Mouse, btn: MouseButton) bool {
        return self.curr().down(keys.mouseButtonIndex(btn));
    }

    pub fn pressed(self: *const Mouse, btn: MouseButton) bool {
        const btnIdx = keys.mouseButtonIndex(btn);
        return (self.curr().down(btnIdx) and !self.prev().down(btnIdx));
    }

    pub fn released(self: *const Mouse, btn: MouseButton) bool {
        const btnIdx = keys.mouseButtonIndex(btn);
        return (!self.curr().down(btnIdx) and self.prev().down(btnIdx));
    }

    /// Logical game coordinates for the current tick.  Returns (-1, -1) when
    /// the cursor is outside the viewport (letterbox / pillarbox region).
    pub fn pos(self: *const Mouse) Vec2F {
        return self.curr().logical_pos;
    }

    /// Logical game coordinates for the previous tick.
    pub fn lastPos(self: *const Mouse) Vec2F {
        return self.prev().logical_pos;
    }

    /// Cursor position in window coordinates for the current tick.
    pub fn rawPos(self: *const Mouse) Vec2F {
        return self.curr().raw_pos;
    }

    /// Cursor position in window coordinates for the previous tick.
    pub fn lastRawPos(self: *const Mouse) Vec2F {
        return self.prev().raw_pos;
    }

    /// Cursor position in framebuffer pixels for the current tick.
    /// Use with Viewport.framebufferToLogical() to map into any coordinate space.
    pub fn fbPos(self: *const Mouse) Vec2F {
        return self.curr().fb_pos;
    }

    /// Cursor position in framebuffer pixels for the previous tick.
    pub fn lastFbPos(self: *const Mouse) Vec2F {
        return self.prev().fb_pos;
    }

    /// Mouse movement accumulated during the current tick, in SDL window
    /// coordinates. This is valid in both normal and captured cursor modes.
    pub fn delta(self: *const Mouse) Vec2F {
        return self.curr().raw_delta;
    }

    /// Scroll wheel delta for the current tick (x = horizontal, y = vertical).
    pub fn scroll(self: *const Mouse) Vec2F {
        return self.curr().scroll_delta;
    }
};
