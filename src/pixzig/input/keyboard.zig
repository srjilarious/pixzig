const std = @import("std");
const keys = @import("./keys.zig");

pub const Key = keys.Key;
pub const NumKeys = keys.NumKeys;
pub const charFromKey = keys.charFromKey;

/// Represents the state of modifier keys (ctrl, alt, shift, super) at a
/// given time.
pub const KeyModifier = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    super: bool = false,
};

/// Represents the state of the keyboard at a given time, including which keys
/// are currently down and which modifier keys are active.
pub const KeyboardState = struct {
    /// Physical key positions that are down, indexed by `Key` (see
    /// `keys.Key`: these come from SDL scancodes).
    keys: std.StaticBitSet(NumKeys),
    /// The same keys resolved through the active OS layout, so on AZERTY
    /// the key that reports `.q` in `keys` reports `.a` here. Read through
    /// `Keyboard.layoutDown` / `layoutPressed` when the keycap matters.
    layout_keys: std.StaticBitSet(NumKeys),
    /// Modifier state as reported by SDL's key events, or null before any
    /// key event has been seen. SDL derives these bits from OS keymap
    /// state, so they reflect OS-level remaps (for example CapsLock
    /// remapped to Control) that the physical `keys` bitset can't: the
    /// remapped CapsLock key still reports as `.caps_lock`, never
    /// `.left_control`. When present, `modifiers()` ORs this with the
    /// physical-key reading so either source can satisfy a modifier query.
    mods_override: ?KeyModifier,

    /// Initializes a new KeyboardState with all keys up.
    pub fn init() KeyboardState {
        return .{
            .keys = std.StaticBitSet(NumKeys).initEmpty(),
            .layout_keys = std.StaticBitSet(NumKeys).initEmpty(),
            .mods_override = null,
        };
    }

    /// Returns true if the provided key is currently up in this state.
    pub fn up(self: *const KeyboardState, key: Key) bool {
        return !self.keys.isSet(keys.keyIndex(key));
    }

    /// Returns true if the provided key is currently down in this state.
    pub fn down(self: *const KeyboardState, key: Key) bool {
        return self.keys.isSet(keys.keyIndex(key));
    }

    /// Returns true if the provided key index is currently down in this state.
    pub fn downIdx(self: *const KeyboardState, keyIdx: usize) bool {
        return self.keys.isSet(keyIdx);
    }

    /// Returns true if the key carrying this identity on the active
    /// layout's keycaps is currently down.
    pub fn layoutDown(self: *const KeyboardState, key: Key) bool {
        return self.layout_keys.isSet(keys.keyIndex(key));
    }

    /// Returns true if the provided layout-key index is currently down.
    pub fn layoutDownIdx(self: *const KeyboardState, keyIdx: usize) bool {
        return self.layout_keys.isSet(keyIdx);
    }

    /// Sets the provided key to the given value (true for down, false for
    /// up) in this state.  This is used by the event pump and by tests.
    pub fn set(self: *KeyboardState, key: Key, val: bool) void {
        self.setIdx(keys.keyIndex(key), val);
    }

    /// Sets the provided key index to the given value (true for down, false
    /// for up) in this state.
    pub fn setIdx(self: *KeyboardState, keyIdx: usize, val: bool) void {
        if (val) {
            self.keys.set(keyIdx);
        } else {
            self.keys.unset(keyIdx);
        }
    }

    /// Sets the layout-resolved identity of a key that went down or up.
    pub fn setLayout(self: *KeyboardState, key: Key, val: bool) void {
        if (val) {
            self.layout_keys.set(keys.keyIndex(key));
        } else {
            self.layout_keys.unset(keys.keyIndex(key));
        }
    }

    /// Clears the keyboard state by setting all keys to up.
    pub fn clear(self: *KeyboardState) void {
        self.keys.setRangeValue(.{ .start = 0, .end = NumKeys }, false);
        self.layout_keys.setRangeValue(.{ .start = 0, .end = NumKeys }, false);
        self.mods_override = null;
    }

    /// Returns a KeyModifier struct representing the state of the modifier
    /// keys (ctrl, alt, shift, super) based on the current keyboard state.
    /// It checks if either the left or right version of each modifier key
    /// is down and sets the corresponding field in the KeyModifier struct
    /// accordingly.
    ///
    /// When `mods_override` is set (an SDL key event has been seen), its
    /// bits are OR-ed in so a modifier the OS produces from a remapped
    /// physical key (e.g. CapsLock acting as Control) is also reported,
    /// even though that physical key reports as something else.
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

/// Maximum number of UTF-8 *bytes* of typed text buffered between two
/// ticks. Anything typed past this in a single tick is dropped. SDL delivers
/// ready-made UTF-8, so bytes are the natural unit.
pub const TextBufLen = 128;

/// Maximum number of UTF-8 bytes of IME composition text retained.
pub const PreeditBufLen = 256;

/// Number of bytes of `bytes[0..n]` that end on a UTF-8 sequence boundary:
/// `n` itself unless it lands mid-sequence, in which case the partial
/// trailing sequence is dropped. Cutting typed text on a raw byte count
/// would hand callers half an encoded codepoint, which for CJK input
/// (3 bytes per character) is not hypothetical.
fn utf8Boundary(bytes: []const u8, n: usize) usize {
    var end = @min(n, bytes.len);
    if (end == bytes.len) return end; // nothing dropped, nothing to split
    // `bytes[end]` is the first byte that would be dropped. A continuation
    // byte there (0b10xxxxxx) means the cut landed inside a sequence: back
    // up over the continuations and off the lead byte that started it.
    while (end > 0 and bytes[end] & 0xC0 == 0x80) end -= 1;
    return end;
}

/// A small fixed-capacity byte buffer that only ever cuts on UTF-8
/// boundaries.
fn FixedBuffer(comptime capacity: usize) type {
    return struct {
        bytes: [capacity]u8 = undefined,
        len: usize = 0,

        const Self = @This();

        pub fn appendSlice(self: *Self, bytes: []const u8) void {
            const room = capacity - self.len;
            const n = if (bytes.len <= room) bytes.len else utf8Boundary(bytes, room);
            @memcpy(self.bytes[self.len..][0..n], bytes[0..n]);
            self.len += n;
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }
    };
}

/// Manages the state of the keyboard across ticks, allowing for querying of
/// key presses, releases, and holds. It maintains two buffers of
/// KeyboardState to track the current and previous state of the keyboard,
/// and provides methods to query key values and text input.
///
/// The state is driven by SDL events (`Engine.pollEvents` forwards them
/// through `InputManager.handleEvent`). Events latch: a key-up that never
/// arrives leaves a key stuck down, so the engine clears the whole state on
/// window focus loss.
pub const Keyboard = struct {
    currIdx: usize,
    prevIdx: usize,
    keyBuffers: [2]KeyboardState,
    /// Typed text accumulated since the last `update`.
    pendingText: FixedBuffer(TextBufLen),
    /// The current tick's typed text, latched from `pendingText` by
    /// `update` (or `latchText`). Read by `text()`.
    frameText: FixedBuffer(TextBufLen),
    /// Latest modifier bits seen from an SDL key event, or null before any
    /// key event. Copied into the current KeyboardState buffer each `update`.
    cbMods: ?KeyModifier,

    /// The IME's in-progress composition ("preedit"), from
    /// `SDL_EVENT_TEXT_EDITING`. Unlike `frameText` this is *not* per-tick
    /// state: it persists across ticks for as long as the user is
    /// composing, is replaced wholesale by each editing event, and is
    /// cleared when the IME commits (a `SDL_EVENT_TEXT_INPUT`, which
    /// carries the committed text through `pendingText`) or cancels. An
    /// app that wants to accept Japanese/Chinese/Korean input has to draw
    /// this at the caret; until it does, composing shows nothing at all
    /// until the commit lands.
    preeditText: FixedBuffer(PreeditBufLen),
    /// Caret position within the composition as a *codepoint* index, or -1
    /// when the IME didn't report one. `preeditCursorByte` converts.
    preeditCursor: i32,

    /// Initializes a new Keyboard instance with two empty KeyboardState buffers.
    pub fn init() Keyboard {
        return .{
            .currIdx = 0,
            .prevIdx = 1,
            .keyBuffers = .{
                KeyboardState.init(),
                KeyboardState.init(),
            },
            .pendingText = .{},
            .frameText = .{},
            .cbMods = null,
            .preeditText = .{},
            .preeditCursor = -1,
        };
    }

    /// Records a key going down or up. `physical` is the scancode-derived
    /// identity used by all the normal query methods; `layout` is the same
    /// key resolved through the OS layout.
    pub fn setKey(self: *Keyboard, physical: Key, layout: Key, isDown: bool) void {
        var curr = self.currKeys_mut();
        if (physical != .unknown) curr.set(physical, isDown);
        if (layout != .unknown) curr.setLayout(layout, isDown);
    }

    /// Appends typed UTF-8 text to the pending buffer. Called from the
    /// event pump on `SDL_EVENT_TEXT_INPUT`.
    pub fn pushText(self: *Keyboard, utf8: []const u8) void {
        self.pendingText.appendSlice(utf8);
    }

    /// Appends a single typed codepoint. A convenience over `pushText` for
    /// tests and for callers that already have a codepoint in hand.
    pub fn pushChar(self: *Keyboard, cp: u21) void {
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, buf[0..]) catch return;
        self.pushText(buf[0..n]);
    }

    /// Stores modifier state from an SDL key event's `mod` bitfield.
    pub fn setModsFromEvent(self: *Keyboard, mods: KeyModifier) void {
        self.cbMods = mods;
    }

    /// Replaces the IME composition text and caret.
    pub fn setPreedit(self: *Keyboard, composing: []const u8, cursor: i32) void {
        self.preeditText.clear();
        self.preeditText.appendSlice(composing);
        self.preeditCursor = cursor;
    }

    /// Ends any IME composition.
    pub fn clearPreedit(self: *Keyboard) void {
        self.preeditText.clear();
        self.preeditCursor = -1;
    }

    /// The IME's in-progress composition, or an empty slice when nothing is
    /// being composed. Valid until the next event is handled.
    pub fn preedit(self: *const Keyboard) []const u8 {
        return self.preeditText.slice();
    }

    /// Caret offset within `preedit()` in *bytes*, clamped into range. SDL
    /// reports it in codepoints; this walks the composition to convert so
    /// callers can slice the text directly. Null when the IME didn't
    /// report a position.
    pub fn preeditCursorByte(self: *const Keyboard) ?usize {
        if (self.preeditCursor < 0) return null;
        const composing = self.preeditText.slice();
        var remaining: usize = @intCast(self.preeditCursor);
        var i: usize = 0;
        while (remaining > 0 and i < composing.len) : (remaining -= 1) {
            i += std.unicode.utf8ByteSequenceLength(composing[i]) catch return i;
        }
        return @min(i, composing.len);
    }

    /// Moves text accumulated since the last call into the current tick's
    /// text buffer and clears the pending buffer. Called by `update`.
    pub fn latchText(self: *Keyboard) void {
        self.frameText.clear();
        self.frameText.appendSlice(self.pendingText.slice());
        self.pendingText.clear();
    }

    /// Returns a pointer to the current KeyboardState buffer, which
    /// represents the state of the keyboard in the current tick.
    pub fn currKeys(self: *const Keyboard) *const KeyboardState {
        return &self.keyBuffers[self.currIdx];
    }

    pub fn currKeys_mut(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.currIdx];
    }

    /// Returns a pointer to the previous KeyboardState buffer, which
    /// represents the state of the keyboard in the previous tick.
    pub fn prevKeys(self: *const Keyboard) *const KeyboardState {
        return &self.keyBuffers[self.prevIdx];
    }

    /// Begins a tick: latches typed text and the modifier bits collected
    /// from events since the last call. Returns whether any key is down.
    pub fn update(self: *Keyboard) bool {
        var curr = self.currKeys_mut();
        curr.mods_override = self.cbMods;
        self.latchText();
        return curr.keys.count() > 0;
    }

    /// Ends a tick: the current key state becomes the previous state so the
    /// next tick's `pressed`/`released` edges are measured against it, and
    /// this tick's typed text is dropped. The IME composition deliberately
    /// survives; it belongs to the composition, not to one tick.
    pub fn finishTick(self: *Keyboard) void {
        self.keyBuffers[self.prevIdx] = self.keyBuffers[self.currIdx];
        self.frameText.clear();
    }

    /// Drops all key state. Called when the window loses focus, where the
    /// key-up events for anything held would otherwise never arrive and
    /// leave keys stuck down.
    pub fn clear(self: *Keyboard) void {
        self.keyBuffers[0].clear();
        self.keyBuffers[1].clear();
        self.pendingText.clear();
        self.frameText.clear();
        self.cbMods = null;
        self.clearPreedit();
    }

    /// Returns true if the provided key is currently up in the current state.
    pub fn up(self: *const Keyboard, key: Key) bool {
        return !self.currKeys().down(key);
    }

    /// Returns true if the provided key is currently down in the current state.
    pub fn down(self: *const Keyboard, key: Key) bool {
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

    /// Returns true if the provided key was pressed in the current tick
    /// (i.e., it is down in the current state but was up in the previous state).
    pub fn pressed(self: *const Keyboard, key: Key) bool {
        const keyIdx = keys.keyIndex(key);
        return (self.currKeys().downIdx(keyIdx) and !self.prevKeys().downIdx(keyIdx));
    }

    /// Returns true if the provided key was released in the current tick
    /// (i.e., it is up in the current state but was down in the previous state).
    pub fn released(self: *const Keyboard, key: Key) bool {
        const keyIdx = keys.keyIndex(key);
        return (!self.currKeys().downIdx(keyIdx) and self.prevKeys().downIdx(keyIdx));
    }

    /// Like `down`, but matches the identity printed on the keycap under
    /// the active OS layout rather than the physical position. Use this for
    /// prompts and menus ("press Y to confirm"); use `down` for gameplay
    /// bindings, so WASD stays where the fingers are.
    pub fn layoutDown(self: *const Keyboard, key: Key) bool {
        return self.currKeys().layoutDown(key);
    }

    /// `pressed`, on the layout-resolved identity. See `layoutDown`.
    pub fn layoutPressed(self: *const Keyboard, key: Key) bool {
        const keyIdx = keys.keyIndex(key);
        return (self.currKeys().layoutDownIdx(keyIdx) and !self.prevKeys().layoutDownIdx(keyIdx));
    }

    /// `released`, on the layout-resolved identity. See `layoutDown`.
    pub fn layoutReleased(self: *const Keyboard, key: Key) bool {
        const keyIdx = keys.keyIndex(key);
        return (!self.currKeys().layoutDownIdx(keyIdx) and self.prevKeys().layoutDownIdx(keyIdx));
    }

    /// Copies the text typed during the current tick into `buf` as UTF-8
    /// and returns the number of bytes written. SDL resolves it through the
    /// active OS keyboard layout, dead keys and IME, so a QWERTZ, AZERTY or
    /// Dvorak layout produces the character on the keycap, not the
    /// US-QWERTY one.
    ///
    /// Non-destructive: repeated calls in the same tick return the same
    /// text. The buffer is refilled on the next `update`. If `buf` is too
    /// small the text is cut on a UTF-8 boundary, never mid-sequence.
    pub fn text(self: *Keyboard, buf: []u8) usize {
        const typed = self.frameText.slice();
        const n = if (typed.len <= buf.len) typed.len else utf8Boundary(typed, buf.len);
        @memcpy(buf[0..n], typed[0..n]);
        return n;
    }
};
