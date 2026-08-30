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
    /// Modifier state as reported by GLFW's key callback `mods` bitfield,
    /// or null before any key event has been seen. GLFW derives these bits
    /// from OS keymap state, so they reflect OS-level remaps (for example
    /// CapsLock remapped to Control) that the physical `keys` bitset can't:
    /// the remapped CapsLock key still polls as `.caps_lock`, never
    /// `.left_control`. When present, `modifiers()` ORs this with the
    /// physical-key reading so either source can satisfy a modifier query.
    mods_override: ?KeyModifier,

    /// Initializes a new KeyboardState with all keys up.
    pub fn init() KeyboardState {
        const keys = std.StaticBitSet(NumKeys).initEmpty();
        return .{ .keys = keys, .mods_override = null };
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
        self.mods_override = null;
    }

    /// Returns a KeyModifier struct representing the state of the modifier
    /// keys (ctrl, alt, shift, super) based on the current keyboard state.
    /// It checks if either the left or right version of each modifier key
    /// is down and sets the corresponding field in the KeyModifier struct
    /// accordingly.
    ///
    /// When `mods_override` is set (GLFW key callback has run at least
    /// once), its bits are OR-ed in so a modifier the OS produces from a
    /// remapped physical key (e.g. CapsLock acting as Control) is also
    /// reported, even though that physical key polls as something else.
    pub fn modifiers(self: *const KeyboardState) KeyModifier {
        var m: KeyModifier = .{
            .alt = self.down(.left_alt) or self.down(.right_alt),
            .ctrl = self.down(.left_control) or self.down(.right_control),
            .shift = self.down(.left_shift) or self.down(.right_shift),
            .super = self.down(.left_super) or self.down(.right_super),
        };
        if (self.mods_override) |o| {
            m.alt = m.alt or o.alt;
            m.ctrl = m.ctrl or o.ctrl;
            m.shift = m.shift or o.shift;
            m.super = m.super or o.super;
        }
        return m;
    }

    /// Returns true if either shift key is currently down in this state.
    pub fn shift(self: *const KeyboardState) bool {
        return self.modifiers().shift;
    }

    /// Returns true if either control key is currently down in this state.
    pub fn ctrl(self: *const KeyboardState) bool {
        return self.modifiers().ctrl;
    }

    /// Returns true if either alt key is currently down in this state.
    pub fn alt(self: *const KeyboardState) bool {
        return self.modifiers().alt;
    }

    /// Returns true if either super/win key is currently down in this state.
    pub fn super(self: *const KeyboardState) bool {
        return self.modifiers().super;
    }
};

/// Maximum number of text codepoints buffered between two `Keyboard.update`
/// calls. Anything typed past this in a single frame is dropped.
pub const TextBufLen = 32;

/// Module-level pointer used by the C key/char callbacks to reach the
/// Keyboard instance. Only one Keyboard receives callback events at a time,
/// the same single-target model as the mouse scroll callback.
var g_kb_target: ?*Keyboard = null;

/// Registers `kb` as the recipient of GLFW key/char callback events. Call
/// once after the Keyboard's address is final, before `glfw.pollEvents()`.
pub fn setKeyboardTarget(kb: *Keyboard) void {
    g_kb_target = kb;
}

/// GLFW char callback: delivers a fully layout/dead-key/IME-processed
/// Unicode codepoint. This is the only correct source of typed text; the
/// polled key bitset can't produce it for non-US layouts.
pub fn charCallback(window: *glfw.Window, codepoint: u32) callconv(.c) void {
    _ = window;
    if (g_kb_target) |kb| kb.pushChar(std.math.cast(u21, codepoint) orelse return);
}

/// GLFW key callback: used only to capture the `mods` bitfield GLFW derives
/// from OS keymap state (see `KeyboardState.mods_override`). Physical key
/// up/down is still read by polling in `update`.
pub fn keyCallback(
    window: *glfw.Window,
    key: glfw.Key,
    scancode: c_int,
    action: glfw.Action,
    mods: glfw.Mods,
) callconv(.c) void {
    _ = window;
    _ = key;
    _ = scancode;
    _ = action;
    if (g_kb_target) |kb| kb.setModsFromCallback(mods);
}

/// Manages the state of the keyboard across frames, allowing for querying of key
/// presses, releases, and holds. It maintains two buffers of KeyboardState to
/// track the current and previous state of the keyboard, and provides methods to
/// query key values and text input.
pub const Keyboard = struct {
    currIdx: usize,
    prevIdx: usize,
    keyBuffers: [2]KeyboardState,
    /// Codepoints accumulated by `charCallback` since the last `update`.
    pendingChars: [TextBufLen]u21,
    pendingCharCount: usize,
    /// The current frame's typed text, latched from `pendingChars` by
    /// `update` (or `latchText`). Read by `text()`.
    frameChars: [TextBufLen]u21,
    frameCharCount: usize,
    /// Latest modifier bits seen from `keyCallback`, or null before any key
    /// event. Copied into the current KeyboardState buffer each `update`.
    cbMods: ?KeyModifier,

    /// Initializes a new Keyboard instance with two empty KeyboardState buffers.
    pub fn init() Keyboard {
        const res: Keyboard = .{
            .currIdx = 0,
            .prevIdx = 1,
            .keyBuffers = .{
                KeyboardState.init(),
                KeyboardState.init(),
            },
            .pendingChars = undefined,
            .pendingCharCount = 0,
            .frameChars = undefined,
            .frameCharCount = 0,
            .cbMods = null,
        };

        return res;
    }

    /// Appends a typed codepoint to the pending buffer. Called by
    /// `charCallback`; also usable directly by tests that drive the
    /// keyboard without a GLFW window.
    pub fn pushChar(self: *Keyboard, cp: u21) void {
        if (self.pendingCharCount >= self.pendingChars.len) return;
        self.pendingChars[self.pendingCharCount] = cp;
        self.pendingCharCount += 1;
    }

    /// Stores modifier state from a GLFW key callback `mods` bitfield.
    pub fn setModsFromCallback(self: *Keyboard, mods: glfw.Mods) void {
        self.cbMods = .{
            .ctrl = mods.control,
            .alt = mods.alt,
            .shift = mods.shift,
            .super = mods.super,
        };
    }

    /// Moves codepoints accumulated since the last call into the current
    /// frame's text buffer and clears the pending buffer. Called by
    /// `update`; exposed for tests that don't have a GLFW window.
    pub fn latchText(self: *Keyboard) void {
        @memcpy(
            self.frameChars[0..self.pendingCharCount],
            self.pendingChars[0..self.pendingCharCount],
        );
        self.frameCharCount = self.pendingCharCount;
        self.pendingCharCount = 0;
    }

    /// Returns a pointer to the current KeyboardState buffer, which
    /// represents the state of the keyboard in the current frame.
    pub fn currKeys(self: *const Keyboard) *const KeyboardState {
        return &self.keyBuffers[self.currIdx];
    }

    pub fn currKeys_mut(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.currIdx];
    }

    /// Returns a pointer to the previous KeyboardState buffer, which
    /// represents the state of the keyboard in the previous frame.
    pub fn prevKeys(self: *const Keyboard) *const KeyboardState {
        return &self.keyBuffers[self.prevIdx];
    }

    /// Updates the keyboard state by swapping the current and previous
    /// buffers and then polling the current state of the keyboard from
    /// the given GLFW window. Also latches any text codepoints and
    /// modifier bits collected by the key/char callbacks since the last
    /// call. Call after `glfw.pollEvents()`.
    pub fn update(self: *Keyboard, window: *glfw.Window) bool {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        // Update the current keys
        var curr = self.currKeys_mut();
        const enumTypeInfo = @typeInfo(glfw.Key).@"enum";
        comptime var keyIdx = 0;
        var anyPressed: bool = false;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.Key, field.name);
            const currPressed = window.getKey(enumValue) == .press;
            curr.setIdx(keyIdx, currPressed);
            anyPressed |= currPressed;
            keyIdx += 1;
        }

        curr.mods_override = self.cbMods;
        self.latchText();

        return anyPressed;
    }

    /// Returns true if the provided key is currently up in the current state.
    pub fn up(self: *const Keyboard, key: glfw.Key) bool {
        return self.currKeys().up(key) == false;
    }

    /// Returns true if the provided key is currently down in the current state.
    pub fn down(self: *const Keyboard, key: glfw.Key) bool {
        return self.currKeys().down(key);
    }

    /// Returns whether a shift key is currently down.
    pub fn shift(self: *const Keyboard) bool {
        return self.currKeys().shift();
    }

    /// Returns whether a ctrl key is currently down.
    pub fn ctrl(self: *const Keyboard) bool {
        return self.currKeys().ctrl();
    }

    /// Returns whether an alt key is currently down.
    pub fn alt(self: *const Keyboard) bool {
        return self.currKeys().alt();
    }

    /// Returns whether a super (win) key is currently down.
    pub fn super(self: *const Keyboard) bool {
        return self.currKeys().super();
    }

    /// Returns true if the provided key was pressed in the current frame
    /// (i.e., it is down in the current state but was up in the previous state).
    pub fn pressed(self: *const Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (self.currKeys().downIdx(keyIdx) and !self.prevKeys().downIdx(keyIdx));
    }

    /// Returns true if the provided key was released in the current frame
    /// (i.e., it is up in the current state but was down in the previous state).
    pub fn released(self: *const Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (!self.currKeys().downIdx(keyIdx) and self.prevKeys().downIdx(keyIdx));
    }

    /// UTF-8 encodes the text typed during the current frame into `buf` and
    /// returns the number of bytes written. The codepoints come from GLFW's
    /// char callback, so they are already resolved through the active OS
    /// keyboard layout, dead keys and IME -- a QWERTZ, AZERTY or Dvorak
    /// layout produces the character on the keycap, not the US-QWERTY one.
    ///
    /// Non-destructive: repeated calls in the same frame return the same
    /// text. The buffer is refilled on the next `update`. A codepoint whose
    /// UTF-8 encoding would not fit in the remaining space is dropped along
    /// with everything after it.
    pub fn text(self: *Keyboard, buf: []u8) usize {
        var bufIdx: usize = 0;
        for (self.frameChars[0..self.frameCharCount]) |cp| {
            const cpLen = std.unicode.utf8CodepointSequenceLength(cp) catch continue;
            if (bufIdx + cpLen > buf.len) break;
            bufIdx += std.unicode.utf8Encode(cp, buf[bufIdx..]) catch break;
        }
        return bufIdx;
    }
};
