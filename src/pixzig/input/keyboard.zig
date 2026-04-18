const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("../comp.zig");
const common = @import("../common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

const NumKeys = comp.numEnumFields(glfw.Key);

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

pub const KeyModifier = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    super: bool = false,
};

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

pub const KeyboardState = struct {
    keys: std.StaticBitSet(NumKeys),

    pub fn init() KeyboardState {
        const keys = std.StaticBitSet(NumKeys).initEmpty();
        return .{ .keys = keys };
    }

    pub fn up(self: *const KeyboardState, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return !self.keys.isSet(keyIdx);
    }

    pub fn down(self: *const KeyboardState, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return self.keys.isSet(keyIdx);
    }

    pub fn downIdx(self: *const KeyboardState, keyIdx: usize) bool {
        const res = self.keys.isSet(keyIdx);
        return res;
    }

    pub fn set(self: *KeyboardState, key: glfw.Key, val: bool) void {
        const keyIdx = getIndexForKey(key);
        self.setIdx(keyIdx, val);
    }

    pub fn setIdx(self: *KeyboardState, keyIdx: usize, val: bool) void {
        if (val) {
            self.keys.set(keyIdx);
        } else {
            self.keys.unset(keyIdx);
        }
    }

    pub fn clear(self: *KeyboardState) void {
        self.keys.setRangeValue(.{ .start = 0, .end = NumKeys }, false);
    }

    pub fn modifiers(self: *const KeyboardState) KeyModifier {
        return .{
            .alt = self.down(.left_alt) or self.down(.right_alt),
            .ctrl = self.down(.left_control) or self.down(.right_control),
            .shift = self.down(.left_shift) or self.down(.right_shift),
            .super = self.down(.left_super) or self.down(.right_super),
        };
    }

    pub fn shift(self: *const KeyboardState) bool {
        return self.down(.left_shift) or self.down(.right_shift);
    }

    pub fn ctrl(self: *const KeyboardState) bool {
        return self.down(.left_control) or self.down(.right_control);
    }

    pub fn alt(self: *const KeyboardState) bool {
        return self.down(.left_alt) or self.down(.right_alt);
    }

    pub fn super(self: *const KeyboardState) bool {
        return self.down(.left_super) or self.down(.right_super);
    }
};

pub const Keyboard = struct {
    currIdx: usize,
    prevIdx: usize,
    keyBuffers: [2]KeyboardState,
    // window: *glfw.Window,
    // allocator: std.mem.Allocator,

    pub fn init() Keyboard {
        const res: Keyboard = .{ .currIdx = 0, .prevIdx = 1, .keyBuffers = .{ KeyboardState.init(), KeyboardState.init() } };

        return res;
    }

    pub fn currKeys(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.currIdx];
    }

    pub fn prevKeys(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.prevIdx];
    }

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

    pub fn up(self: *Keyboard, key: glfw.Key) bool {
        return self.currKeys().up(key) == false;
    }

    pub fn down(self: *Keyboard, key: glfw.Key) bool {
        return self.currKeys().down(key);
    }

    pub fn pressed(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (self.currKeys().downIdx(keyIdx) and !self.prevKeys().downIdx(keyIdx));
    }

    pub fn released(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (!self.currKeys().downIdx(keyIdx) and self.prevKeys().downIdx(keyIdx));
    }

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
