// zig fmt: off
const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("./comp.zig");

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

