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
    pos: Vec2F,

    pub fn init() MouseState {
        const buttons = std.StaticBitSet(NumMouseButtons).initEmpty();
        return .{ .buttons = buttons, .pos = .{ .x = 0, .y = 0 } };
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

    pub fn setPos(self: *MouseState, pos: [2]f64) void {
        self.pos = .{ .x = @floatCast(pos[0]), .y = @floatCast(pos[1]) };
    }

    pub fn clear(self: *MouseState) void {
        self.buttons.setRangeValue(.{ .start = 0, .end = NumMouseButtons }, false);
        self.pos = .{ .x = 0, .y = 0 };
    }
};

pub const Mouse = struct {
    currIdx: usize,
    prevIdx: usize,
    mouseBuffers: [2]MouseState,

    pub fn init() Mouse {
        const res: Mouse = .{
            .currIdx = 0,
            .prevIdx = 1,
            .mouseBuffers = .{
                MouseState.init(),
                MouseState.init(),
            },
        };

        return res;
    }

    pub fn update(
        self: *Mouse,
        window: *glfw.Window,
    ) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        var state = self.curr();

        // Update the current keys
        const enumTypeInfo = @typeInfo(glfw.MouseButton).@"enum";
        comptime var btnIdx = 0;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.MouseButton, field.name);
            state.setIdx(btnIdx, window.getMouseButton(enumValue) == .press);
            btnIdx += 1;
        }

        const cursorPos = window.getCursorPos();
        state.setPos(cursorPos);
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

    pub fn pos(self: *const Mouse) Vec2F {
        return self.curr().pos;
    }

    pub fn lastPos(self: *const Mouse) Vec2F {
        return self.prev().pos;
    }
};
