const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("../comp.zig");
const common = @import("../common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

const NumMouseButtons = comp.numEnumFields(glfw.MouseButton);

fn getIndexForMouseButton(key: glfw.MouseButton) usize {
    const enumTypeInfo = @typeInfo(glfw.MouseButton).@"enum";
    comptime var keyIdx: usize = 0;
    inline for (enumTypeInfo.fields) |field| {
        const fieldKey = @field(glfw.MouseButton, field.name);
        if (key == fieldKey) return keyIdx;
        keyIdx += 1;
    }

    return 0;
}

pub const MouseState = struct {
    buttons: std.StaticBitSet(NumMouseButtons),
    /// Raw GLFW cursor position in window coordinates (from getCursorPos()).
    raw_pos: Vec2F,
    /// Logical game coordinates after viewport mapping.  Set to (-1, -1) when
    /// the cursor is outside the viewport (letterbox / pillarbox region).
    logical_pos: Vec2F,
    /// Scroll wheel delta accumulated during the current frame (x = horizontal, y = vertical).
    scroll_delta: Vec2F,

    pub fn init() MouseState {
        const buttons = std.StaticBitSet(NumMouseButtons).initEmpty();
        return .{
            .buttons = buttons,
            .raw_pos = .{ .x = 0, .y = 0 },
            .logical_pos = .{ .x = -1, .y = -1 },
            .scroll_delta = .{ .x = 0, .y = 0 },
        };
    }

    pub fn down(self: *const MouseState, keyIdx: usize) bool {
        const res = self.buttons.isSet(keyIdx);
        return res;
    }

    pub fn set(self: *MouseState, btn: glfw.MouseButton, val: bool) void {
        const btnIdx = getIndexForMouseButton(btn);
        if (val) {
            self.buttons.set(btnIdx);
        } else {
            self.buttons.unset(btnIdx);
        }
    }

    pub fn setIdx(self: *MouseState, btnIdx: usize, val: bool) void {
        if (val) {
            self.buttons.set(btnIdx);
        } else {
            self.buttons.unset(btnIdx);
        }
    }

    pub fn setRawPos(self: *MouseState, pos: [2]f64) void {
        self.raw_pos = .{ .x = @floatCast(pos[0]), .y = @floatCast(pos[1]) };
    }

    pub fn clear(self: *MouseState) void {
        self.buttons.setRangeValue(.{ .start = 0, .end = NumMouseButtons }, false);
        self.raw_pos = .{ .x = 0, .y = 0 };
        self.logical_pos = .{ .x = -1, .y = -1 };
        self.scroll_delta = .{ .x = 0, .y = 0 };
    }
};

/// Module-level pointer used by the C scroll callback to reach the Mouse instance.
var g_scroll_mouse: ?*Mouse = null;

pub fn setScrollTarget(m: *Mouse) void {
    g_scroll_mouse = m;
}

pub fn scrollCallback(window: *glfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = window;
    if (g_scroll_mouse) |m| {
        m.pending_scroll.x += @floatCast(xoffset);
        m.pending_scroll.y += @floatCast(yoffset);
    }
}

pub const Mouse = struct {
    currIdx: usize,
    prevIdx: usize,
    mouseBuffers: [2]MouseState,
    /// Scroll delta accumulated by the scroll callback since the last update().
    pending_scroll: Vec2F,

    pub fn init() Mouse {
        const res: Mouse = .{
            .currIdx = 0,
            .prevIdx = 1,
            .mouseBuffers = .{
                MouseState.init(),
                MouseState.init(),
            },
            .pending_scroll = .{ .x = 0, .y = 0 },
        };

        return res;
    }

    /// Reads button state and raw cursor position from the GLFW window.
    /// logical_pos is left unchanged here — InputManager sets it after calling
    /// this so it can apply the viewport transformation.
    /// Moves pending_scroll (accumulated by the scroll callback) into the
    /// current frame's scroll_delta and resets the accumulator.
    pub fn update(
        self: *Mouse,
        window: *glfw.Window,
    ) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        var state = self.curr_mut();

        const enumTypeInfo = @typeInfo(glfw.MouseButton).@"enum";
        comptime var btnIdx = 0;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.MouseButton, field.name);
            state.setIdx(btnIdx, window.getMouseButton(enumValue) == .press);
            btnIdx += 1;
        }

        const cursorPos = window.getCursorPos();
        state.setRawPos(cursorPos);

        state.scroll_delta = self.pending_scroll;
        self.pending_scroll = .{ .x = 0, .y = 0 };
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

    pub fn up(self: *const Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return self.curr().down(btnIdx) == false;
    }

    pub fn down(self: *const Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return self.curr().down(btnIdx);
    }

    pub fn pressed(self: *const Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return (self.curr().down(btnIdx) and !self.prev().down(btnIdx));
    }

    pub fn released(self: *const Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return (!self.curr().down(btnIdx) and self.prev().down(btnIdx));
    }

    /// Logical game coordinates for the current frame.  Returns (-1, -1) when
    /// the cursor is outside the viewport (letterbox / pillarbox region).
    pub fn pos(self: *const Mouse) Vec2F {
        return self.curr().logical_pos;
    }

    /// Logical game coordinates for the previous frame.
    pub fn lastPos(self: *const Mouse) Vec2F {
        return self.prev().logical_pos;
    }

    /// Raw GLFW cursor position in window coordinates for the current frame.
    pub fn rawPos(self: *const Mouse) Vec2F {
        return self.curr().raw_pos;
    }

    /// Raw GLFW cursor position in window coordinates for the previous frame.
    pub fn lastRawPos(self: *const Mouse) Vec2F {
        return self.prev().raw_pos;
    }

    /// Scroll wheel delta for the current frame (x = horizontal, y = vertical).
    pub fn scroll(self: *const Mouse) Vec2F {
        return self.curr().scroll_delta;
    }
};
