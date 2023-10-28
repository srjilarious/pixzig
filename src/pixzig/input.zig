// zig fmt: off
const std = @import("std");
const sdl = @import("zsdl");
const comp = @import("./comp.zig");

const NumKeys = comp.numEnumFields(sdl.Scancode);
pub const KeyboardState = struct {
    keys: std.StaticBitSet(NumKeys),

    pub fn init() KeyboardState {
        const keys = std.StaticBitSet(NumKeys).initEmpty();
        return .{ 
            .keys = keys
        };
    }

    pub fn down(self: *KeyboardState, key: sdl.Scancode) bool {
        const idx : usize = @intCast(@intFromEnum(key));
        var res = self.keys.isSet(idx);
        // std.debug.print("Index: {} - val = {}\n", .{ idx, res});
        return res;
    }

    pub fn set(self: *KeyboardState, key: sdl.Scancode, val: bool) void {
        var idx : usize = @intCast(@intFromEnum(key));
        if(val) {
            std.debug.print("Setting {}\n", .{idx });
            self.keys.set(idx);
        }
        else {
            self.keys.unset(idx);
        }
    }
};

pub const Keyboard = struct {
    currIdx: usize,
    prevIdx: usize,
    keyBuffers: [2]KeyboardState,

    pub fn init(_alloc: std.mem.Allocator) Keyboard {
        _ = _alloc;
        var res: Keyboard = .{
            .currIdx = 0, 
            .prevIdx = 1,
            .keyBuffers = .{
                KeyboardState.init(),
                KeyboardState.init()
            } 
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
        var temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        var curr = self.currKeys();
        var prev = self.prevKeys();
        curr.keys.setRangeValue(.{.start=0, .end=NumKeys}, false);
        curr.keys.setUnion(prev.keys);
    }

    pub fn keyEvent(self: *Keyboard, key: sdl.Scancode, keyDown: bool) void {
        self.currKeys().set(key, keyDown);
    }

    pub fn up(self: *Keyboard, key:sdl.Scancode ) bool {
        return self.currKeys().down(key) == false;
    }

    pub fn down(self: *Keyboard, key:sdl.Scancode ) bool {
        return self.currKeys().down(key);
    }

    pub fn pressed(self: *Keyboard, key: sdl.Scancode) bool {
        return (self.currKeys().down(key) and !self.prevKeys().down(key));
    }

    pub fn released(self: *Keyboard, key: sdl.Scancode) bool {
        return (!self.currKeys().down(key) and self.prevKeys().down(key));
    }
};

