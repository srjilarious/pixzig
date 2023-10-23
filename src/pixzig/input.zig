// zig fmt: off
const std = @import("std");
const sdl = @import("zsdl");
const comp = @import("./comp.zig");

const NumKeys = comp.numEnumFields(sdl.Keycode);
pub const KeyboardState = struct {
    keys: std.StaticBitSet(NumKeys),

    pub fn init() KeyboardState {
        return .{ 
            .keys = std.StaticBitSet(NumKeys).initEmpty()
        };
    }

    pub fn down(self: *KeyboardState, key: sdl.Keycode) bool {
        return self.keys.isSet(@intCast(@intFromEnum(key)));
    }

    pub fn set(self: *KeyboardState, key: sdl.Keycode, val: bool) void {
        var idx : usize = @intCast(@intFromEnum(key));
        if(val) {
            self.keys.set(idx);
        }
        else {
            self.keys.unset(idx);
        }
    }
};

pub const Keyboard = struct {
    currKeys: *KeyboardState,
    prevKeys: *KeyboardState,
    keyBuffers: [2]KeyboardState,

    pub fn init(_alloc: std.mem.Allocator) Keyboard {
        _ = _alloc;
        var buffers : [2]KeyboardState = .{
            KeyboardState.init(),
            KeyboardState.init()
        };
        return .{
            .currKeys = &buffers[0],
            .prevKeys = &buffers[1],
            .keyBuffers = buffers
        };
    }

    pub fn update(self: *Keyboard) void { //deltaUs: i64) void {
        var temp = self.currKeys;
        self.currKeys = self.prevKeys;
        self.prevKeys = temp;

    }

    pub fn keyEvent(self: *Keyboard, key: sdl.Keycode, keyDown: bool) void {
        self.currKeys.set(key, keyDown);
    }

    pub fn up(self: *Keyboard, key:sdl.Keycode ) bool {
        return self.currKeys.down(key) == false;
    }

    pub fn down(self: *Keyboard, key:sdl.Keycode ) bool {
        return self.currKeys.down(key);
    }

    pub fn pressed(self: *Keyboard, key: sdl.Keycode) bool {
        return (self.currKeys.down(key) and !self.prevKeys.down(key));
    }

    pub fn released(self: *Keyboard, key: sdl.Keycode) bool {
        return (!self.currKeys.down(key) and self.prevKeys.down(key));
    }
};

