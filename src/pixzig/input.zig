// zig fmt: off
const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("./comp.zig");
const common = @import("./common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

const NumKeys = comp.numEnumFields(glfw.Key);

fn getIndexForKey(key: glfw.Key) usize {
   const enumTypeInfo = @typeInfo(glfw.Key).Enum;
    comptime var keyIdx: usize = 0;
    inline for (enumTypeInfo.fields) |field| {
        const fieldKey = @field(glfw.Key, field.name);
        if (key == fieldKey) return keyIdx;
        keyIdx += 1;
    }

    return 0;
}

pub const KeyboardState = struct {
    keys: std.StaticBitSet(NumKeys),

    pub fn init() KeyboardState {
        const keys = std.StaticBitSet(NumKeys).initEmpty();
        return .{ 
            .keys = keys
        };
    }

    pub fn down(self: *KeyboardState, keyIdx: usize) bool {
        const res = self.keys.isSet(keyIdx);
        return res;
    }

    pub fn set(self: *KeyboardState, keyIdx: usize, val: bool) void {
        if(val) {
            self.keys.set(keyIdx);
        }
        else {
            self.keys.unset(keyIdx);
        }
    }
};

pub const Keyboard = struct {
    currIdx: usize,
    prevIdx: usize,
    keyBuffers: [2]KeyboardState,
    window: *glfw.Window,
    allocator: std.mem.Allocator,

    pub fn init(win: *glfw.Window, alloc: std.mem.Allocator) Keyboard {
        const res: Keyboard = .{
            .currIdx = 0, 
            .prevIdx = 1,
            .keyBuffers = .{
                KeyboardState.init(),
                KeyboardState.init()
            },
            .window = win,
            .allocator = alloc
        };

        return res;
    }

    fn currKeys(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.currIdx];
    }
    fn prevKeys(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.prevIdx];
    }

    pub fn update(self: *Keyboard) void { //deltaUs: i64) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        var curr = self.currKeys();
        //const prev = self.prevKeys();
        // curr.keys.setRangeValue(.{.start=0, .end=NumKeys}, false);
       
        // Update the current keys
        const enumTypeInfo = @typeInfo(glfw.Key).Enum;
        comptime var keyIdx = 0;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.Key, field.name);
            curr.set(keyIdx, self.window.getKey(enumValue) == .press);
            keyIdx += 1;
        }

        // curr.keys.setUnion(prev.keys);
    }

    pub fn up(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return self.currKeys().down(keyIdx) == false;
    }

    pub fn down(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return self.currKeys().down(keyIdx);
    }

    pub fn pressed(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (self.currKeys().down(keyIdx) and !self.prevKeys().down(keyIdx));
    }

    pub fn released(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (!self.currKeys().down(keyIdx) and self.prevKeys().down(keyIdx));
    }
};


// ----------------------------------------------------------------------------
// Mouse functionality
const NumMouseButtons = comp.numEnumFields(glfw.MouseButton);

fn getIndexForMouseButton(key: glfw.MouseButton) usize {
   const enumTypeInfo = @typeInfo(glfw.MouseButton).Enum;
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
        return .{ 
            .buttons = buttons,
            .pos = .{ .x = 0, .y = 0 }
        };
    }

    pub fn down(self: *MouseState, keyIdx: usize) bool {
        const res = self.buttons.isSet(keyIdx);
        return res;
    }

    pub fn set(self: *MouseState, btnIdx: usize, val: bool) void {
        if(val) {
            self.buttons.set(btnIdx);
        }
        else {
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
        const res: Mouse = .{
            .currIdx = 0, 
            .prevIdx = 1,
            .mouseBuffers = .{
                MouseState.init(),
                MouseState.init()
            },
            .window = win,
            .allocator = alloc
        };

        return res;
    }

    pub fn update(self: *Mouse) void { //deltaUs: i64) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        var state = self.curr();
        //const prev = self.prevKeys();
        // curr.keys.setRangeValue(.{.start=0, .end=NumKeys}, false);
       
        // Update the current keys
        const enumTypeInfo = @typeInfo(glfw.MouseButton).Enum;
        comptime var btnIdx = 0;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.MouseButton, field.name);
            state.set(btnIdx, self.window.getMouseButton(enumValue) == .press);
            btnIdx += 1;
        }

        state.setPos(self.window.getCursorPos());
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


