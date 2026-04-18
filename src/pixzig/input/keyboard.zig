const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("../comp.zig");
const common = @import("../common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

const NumKeys = comp.numEnumFields(glfw.Key);

/// Returns the index of the given key in the keyboard state bitset. This is
/// necessary because the glfw.Key enum values are not guaranteed to be
/// contiguous or start at 0, so we need to map them to a dense range of
/// indices for our bitset.
pub fn getIndexForKey(key: glfw.Key) usize {
    const enumTypeInfo = @typeInfo(glfw.Key).@"enum";
    comptime var keyIdx: usize = 0;
    inline for (enumTypeInfo.fields) |field| {
        const fieldKey = @field(glfw.Key, field.name);
        if (key == fieldKey) return keyIdx;
        keyIdx += 1;
    }

    return 0;
}

/// Represents the state of modifier keys (ctrl, alt, shift, super) at a
/// given time.
pub const KeyModifier = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    super: bool = false,
};

/// Converts a glfw.Key and shift state to the corresponding ASCII character.
pub fn charFromKey(key: glfw.Key, shift: bool) ?u8 {
    const keyInt = @intFromEnum(key);
    if (keyInt >= @intFromEnum(glfw.Key.space) and keyInt <= @intFromEnum(glfw.Key.grave_accent)) {
        if (!shift) {
            if (keyInt >= 'A' and keyInt <= 'Z') {
                // Convert to lower case.
                return @intCast(keyInt + 32);
            } else {
                return @intCast(keyInt);
            }
        } else {
            return switch (key) {
                .a => 'A',
                .b => 'B',
                .c => 'C',
                .d => 'D',
                .e => 'E',
                .f => 'F',
                .g => 'G',
                .h => 'H',
                .i => 'I',
                .j => 'J',
                .k => 'K',
                .l => 'L',
                .m => 'M',
                .n => 'N',
                .o => 'O',
                .p => 'P',
                .q => 'Q',
                .r => 'R',
                .s => 'S',
                .t => 'T',
                .u => 'U',
                .v => 'V',
                .w => 'W',
                .x => 'X',
                .y => 'Y',
                .z => 'Z',
                .one => '!',
                .two => '@',
                .three => '#',
                .four => '$',
                .five => '%',
                .six => '^',
                .seven => '&',
                .eight => '*',
                .nine => '(',
                .zero => ')',

                .space => ' ',
                .apostrophe => '"',
                .comma => '<',
                .minus => '-',
                .period => '>',
                .slash => '?',
                .semicolon => ':',
                .equal => '+',
                .left_bracket => '{',
                .backslash => '|',
                .right_bracket => '}',
                .grave_accent => '~',
                else => null,
            };
        }
    }

    return null;
}

/// Represents the state of the keyboard at a given time, including which keys
/// are currently down and which modifier keys are active.
pub const KeyboardState = struct {
    keys: std.StaticBitSet(NumKeys),

    /// Initializes a new KeyboardState with all keys up.
    pub fn init() KeyboardState {
        const keys = std.StaticBitSet(NumKeys).initEmpty();
        return .{ .keys = keys };
    }

    /// Returns true if the provided key is currently up in this state.
    pub fn up(self: *const KeyboardState, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return !self.keys.isSet(keyIdx);
    }

    /// Returns true if the provided key is currently down in this state.
    pub fn down(self: *const KeyboardState, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return self.keys.isSet(keyIdx);
    }

    /// Returns true if the provided key index is currently down in this state.
    pub fn downIdx(self: *const KeyboardState, keyIdx: usize) bool {
        const res = self.keys.isSet(keyIdx);
        return res;
    }

    /// Sets the provided key to the given value (true for down, false for
    /// up) in this state.  This is used for testing.
    pub fn set(self: *KeyboardState, key: glfw.Key, val: bool) void {
        const keyIdx = getIndexForKey(key);
        self.setIdx(keyIdx, val);
    }

    /// Sets the provided key index to the given value (true for down, false
    /// for up) in this state.  This is used for testing.
    pub fn setIdx(self: *KeyboardState, keyIdx: usize, val: bool) void {
        if (val) {
            self.keys.set(keyIdx);
        } else {
            self.keys.unset(keyIdx);
        }
    }

    /// Clears the keyboard state by setting all keys to up.
    pub fn clear(self: *KeyboardState) void {
        self.keys.setRangeValue(.{ .start = 0, .end = NumKeys }, false);
    }

    /// Returns a KeyModifier struct representing the state of the modifier
    /// keys (ctrl, alt, shift, super) based on the current keyboard state.
    /// It checks if either the left or right version of each modifier key
    /// is down and sets the corresponding field in the KeyModifier struct
    /// accordingly.
    pub fn modifiers(self: *const KeyboardState) KeyModifier {
        return .{
            .alt = self.down(.left_alt) or self.down(.right_alt),
            .ctrl = self.down(.left_control) or self.down(.right_control),
            .shift = self.down(.left_shift) or self.down(.right_shift),
            .super = self.down(.left_super) or self.down(.right_super),
        };
    }

    /// Returns true if either shift key is currently down in this state.
    pub fn shift(self: *const KeyboardState) bool {
        return self.down(.left_shift) or self.down(.right_shift);
    }

    /// Returns true if either control key is currently down in this state.
    pub fn ctrl(self: *const KeyboardState) bool {
        return self.down(.left_control) or self.down(.right_control);
    }

    /// Returns true if either alt key is currently down in this state.
    pub fn alt(self: *const KeyboardState) bool {
        return self.down(.left_alt) or self.down(.right_alt);
    }

    /// Returns true if either super/win key is currently down in this state.
    pub fn super(self: *const KeyboardState) bool {
        return self.down(.left_super) or self.down(.right_super);
    }
};

/// Manages the state of the keyboard across frames, allowing for querying of key
/// presses, releases, and holds. It maintains two buffers of KeyboardState to
/// track the current and previous state of the keyboard, and provides methods to
/// query key values and text input.
pub const Keyboard = struct {
    currIdx: usize,
    prevIdx: usize,
    keyBuffers: [2]KeyboardState,

    /// Initializes a new Keyboard instance with two empty KeyboardState buffers.
    pub fn init() Keyboard {
        const res: Keyboard = .{ .currIdx = 0, .prevIdx = 1, .keyBuffers = .{ KeyboardState.init(), KeyboardState.init() } };

        return res;
    }

    /// Returns a pointer to the current KeyboardState buffer, which
    /// represents the state of the keyboard in the current frame.
    pub fn currKeys(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.currIdx];
    }

    /// Returns a pointer to the previous KeyboardState buffer, which
    /// represents the state of the keyboard in the previous frame.
    pub fn prevKeys(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.prevIdx];
    }

    /// Updates the keyboard state by swapping the current and previous
    /// buffers and then polling the current state of the keyboard from
    /// the given GLFW window.
    pub fn update(self: *Keyboard, window: *glfw.Window) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        // Update the current keys
        var curr = self.currKeys();
        const enumTypeInfo = @typeInfo(glfw.Key).@"enum";
        comptime var keyIdx = 0;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.Key, field.name);
            curr.setIdx(keyIdx, window.getKey(enumValue) == .press);
            keyIdx += 1;
        }
    }

    /// Returns true if the provided key is currently up in the current state.
    pub fn up(self: *Keyboard, key: glfw.Key) bool {
        return self.currKeys().up(key) == false;
    }

    /// Returns true if the provided key is currently down in the current state.
    pub fn down(self: *Keyboard, key: glfw.Key) bool {
        return self.currKeys().down(key);
    }

    /// Returns true if the provided key was pressed in the current frame
    /// (i.e., it is down in the current state but was up in the previous state).
    pub fn pressed(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (self.currKeys().downIdx(keyIdx) and !self.prevKeys().downIdx(keyIdx));
    }

    /// Returns true if the provided key was released in the current frame
    /// (i.e., it is up in the current state but was down in the previous state).
    pub fn released(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (!self.currKeys().downIdx(keyIdx) and self.prevKeys().downIdx(keyIdx));
    }

    /// Fills the provided buffer with ASCII characters corresponding to the
    /// keys that were pressed in the current frame. It checks each key to
    /// see if it was pressed, and if so, it converts it to a character using
    /// the charFromKey function (taking into account the shift state) and
    /// appends it to the buffer. It returns the number of characters written
    /// to the buffer. This can be used to capture text input from the keyboard.
    pub fn text(self: *Keyboard, buf: []u8) usize {
        const shiftDown = self.currKeys().shift();
        var bufIdx: usize = 0;

        const enumTypeInfo = @typeInfo(glfw.Key).@"enum";
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.Key, field.name);
            if (self.pressed(enumValue)) {
                if (charFromKey(enumValue, shiftDown)) |c| {
                    buf[bufIdx] = c;
                    bufIdx += 1;
                    if (bufIdx >= buf.len) break;
                }
            }
        }

        return bufIdx;
    }
};
