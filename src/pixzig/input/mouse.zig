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

    pub fn down(self: *MouseState, keyIdx: usize) bool {
        const res = self.buttons.isSet(keyIdx);
        return res;
    }

    pub fn set(self: *MouseState, btnIdx: usize, val: bool) void {
        if (val) {
            self.buttons.set(btnIdx);
        } else {
            self.buttons.unset(btnIdx);
        }
    }

    pub fn setPos(self: *MouseState, pos: [2]f64) void {
        self.pos = .{ .x = @floatCast(pos[0]), .y = @floatCast(pos[1]) };
    }
};

pub const Mouse = struct {
    currIdx: usize,
    prevIdx: usize,
    mouseBuffers: [2]MouseState,
    window: *glfw.Window,
    allocator: std.mem.Allocator,

    pub fn init(win: *glfw.Window, alloc: std.mem.Allocator) Mouse {
        const res: Mouse = .{ .currIdx = 0, .prevIdx = 1, .mouseBuffers = .{ MouseState.init(), MouseState.init() }, .window = win, .allocator = alloc };

        return res;
    }

    pub fn update(self: *Mouse) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        var state = self.curr();
        //const prev = self.prevKeys();
        // curr.keys.setRangeValue(.{.start=0, .end=NumKeys}, false);

        // Update the current keys
        const enumTypeInfo = @typeInfo(glfw.MouseButton).@"enum";
        comptime var btnIdx = 0;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.MouseButton, field.name);
            state.set(btnIdx, self.window.getMouseButton(enumValue) == .press);
            btnIdx += 1;
        }

        const cursorPos = self.window.getCursorPos();
        // const contentScale = self.window.getContentScale();
        // cursorPos[0] /= contentScale[0];
        // cursorPos[1] /= contentScale[1];
        state.setPos(cursorPos);
    }

    fn curr(self: *Mouse) *MouseState {
        return &self.mouseBuffers[self.currIdx];
    }

    fn prev(self: *Mouse) *MouseState {
        return &self.mouseBuffers[self.prevIdx];
    }

    pub fn up(self: *Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return self.curr().down(btnIdx) == false;
    }

    pub fn down(self: *Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return self.curr().down(btnIdx);
    }

    pub fn pressed(self: *Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return (self.curr().down(btnIdx) and !self.prev().down(btnIdx));
    }

    pub fn released(self: *Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return (!self.curr().down(btnIdx) and self.prev().down(btnIdx));
    }

    pub fn pos(self: *Mouse) Vec2F {
        return self.curr().pos;
    }

    pub fn lastPos(self: *Mouse) Vec2F {
        return self.prev().pos;
    }
};
