const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const input = pixzig.input;
const keys = input.keys;
const Key = keys.Key;
const Keyboard = input.Keyboard;
const Mouse = input.Mouse;

/// The bitsets in Keyboard/Mouse index straight off `@intFromEnum`, which is
/// only sound while the enums stay dense and 0-based.
pub fn keyEnumIsDenseTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    inline for (@typeInfo(Key).@"enum".fields, 0..) |field, i| {
        try testz.expectEqual(field.value, i);
    }
    try testz.expectEqual(@intFromEnum(Key.unknown), 0);
    try testz.expectEqual(keys.NumKeys, @typeInfo(Key).@"enum".fields.len);

    inline for (@typeInfo(keys.MouseButton).@"enum".fields, 0..) |field, i| {
        try testz.expectEqual(field.value, i);
    }
    inline for (@typeInfo(keys.GamepadButton).@"enum".fields, 0..) |field, i| {
        try testz.expectEqual(field.value, i);
    }
    inline for (@typeInfo(keys.GamepadAxis).@"enum".fields, 0..) |field, i| {
        try testz.expectEqual(field.value, i);
    }
}

/// Scancodes and keycodes both land on the same `Key`, and anything SDL
/// reports that we don't model falls back to `.unknown` rather than
/// indexing off the end of the bitset.
pub fn keyCodeMappingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    const sdl = @import("sdl3");

    try testz.expectEqual(keys.fromScancode(sdl.SDL_SCANCODE_W), .w);
    try testz.expectEqual(keys.fromScancode(sdl.SDL_SCANCODE_ESCAPE), .escape);
    try testz.expectEqual(keys.fromScancode(sdl.SDL_SCANCODE_F12), .F12);
    try testz.expectEqual(keys.fromScancode(sdl.SDL_SCANCODE_KP_PLUS), .kp_add);
    try testz.expectEqual(keys.fromScancode(sdl.SDL_SCANCODE_UNKNOWN), .unknown);

    try testz.expectEqual(keys.fromKeycode(sdl.SDLK_W), .w);
    try testz.expectEqual(keys.fromKeycode(sdl.SDLK_RETURN), .enter);
    try testz.expectEqual(keys.fromKeycode(sdl.SDLK_GRAVE), .grave_accent);
    try testz.expectEqual(keys.fromKeycode(sdl.SDLK_UNKNOWN), .unknown);

    try testz.expectEqual(keys.fromSdlMouseButton(sdl.SDL_BUTTON_LEFT).?, .left);
    try testz.expectEqual(keys.fromSdlMouseButton(sdl.SDL_BUTTON_X2).?, .x2);
    try testz.expectTrue(keys.fromSdlMouseButton(99) == null);
}

/// Event-driven state: a key set by an event is down until the matching
/// up event, and `pressed`/`released` are one-tick edges measured against
/// whatever `finishTick` last rolled over.
pub fn keyboardEdgesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var kb = Keyboard.init();

    kb.setKey(.w, .w, true);
    _ = kb.update();
    try testz.expectTrue(kb.down(.w));
    try testz.expectTrue(kb.pressed(.w));
    try testz.expectFalse(kb.released(.w));

    // Second tick with no new events: still down, no longer a fresh press.
    kb.finishTick();
    _ = kb.update();
    try testz.expectTrue(kb.down(.w));
    try testz.expectFalse(kb.pressed(.w));

    kb.finishTick();
    kb.setKey(.w, .w, false);
    _ = kb.update();
    try testz.expectFalse(kb.down(.w));
    try testz.expectTrue(kb.released(.w));
}

/// The physical and layout identities are tracked separately, so a key
/// whose keycap disagrees with its position answers both questions.
pub fn keyboardLayoutIdentityTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var kb = Keyboard.init();

    // The physical QWERTY-Q position under an AZERTY layout: SDL reports
    // scancode Q, keycode A.
    kb.setKey(.q, .a, true);
    _ = kb.update();

    try testz.expectTrue(kb.down(.q));
    try testz.expectFalse(kb.down(.a));
    try testz.expectTrue(kb.layoutDown(.a));
    try testz.expectFalse(kb.layoutDown(.q));
    try testz.expectTrue(kb.layoutPressed(.a));
}

/// Focus loss clears everything, since the key-up events for anything held
/// while the window loses focus never arrive.
pub fn keyboardClearTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var kb = Keyboard.init();
    kb.setKey(.left_shift, .left_shift, true);
    _ = kb.update();
    try testz.expectTrue(kb.shift());

    kb.clear();
    _ = kb.update();
    try testz.expectFalse(kb.shift());
    try testz.expectFalse(kb.down(.left_shift));
}

/// Typed text survives repeated reads within a tick and is dropped by
/// `finishTick`.
pub fn keyboardTextTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var kb = Keyboard.init();
    kb.pushText("ab");
    kb.pushChar('c');
    _ = kb.update();

    var buf: [16]u8 = undefined;
    try testz.expectEqualStr(buf[0..kb.text(buf[0..])], "abc");
    // Non-destructive: reading again in the same tick gives the same text.
    try testz.expectEqualStr(buf[0..kb.text(buf[0..])], "abc");

    kb.finishTick();
    _ = kb.update();
    try testz.expectEqual(kb.text(buf[0..]), 0);
}

/// A caller's buffer that can't hold all the typed text is cut on a UTF-8
/// sequence boundary. Cutting on the raw byte count would hand back half an
/// encoded codepoint, which for 3-byte CJK input is not hypothetical.
pub fn keyboardTextUtf8BoundaryTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var kb = Keyboard.init();
    kb.pushText("\u{65e5}\u{672c}"); // two 3-byte codepoints
    _ = kb.update();

    var buf: [8]u8 = undefined;
    // Four bytes of room fits one full codepoint, not one and a third.
    try testz.expectEqual(kb.text(buf[0..4]), 3);
    try testz.expectEqualStr(buf[0..3], "\u{65e5}");
    try testz.expectEqual(kb.text(buf[0..]), 6);
}

/// SDL reports the IME composition caret in codepoints; callers slice the
/// composition in bytes.
pub fn keyboardPreeditTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var kb = Keyboard.init();
    try testz.expectEqualStr(kb.preedit(), "");
    try testz.expectTrue(kb.preeditCursorByte() == null);

    kb.setPreedit("\u{306b}\u{307b}\u{3093}", 2);
    try testz.expectEqualStr(kb.preedit(), "\u{306b}\u{307b}\u{3093}");
    try testz.expectEqual(kb.preeditCursorByte().?, 6);

    // A composition outlives the tick that saw it: it belongs to the IME,
    // not to one frame.
    kb.finishTick();
    try testz.expectEqualStr(kb.preedit(), "\u{306b}\u{307b}\u{3093}");

    kb.clearPreedit();
    try testz.expectEqualStr(kb.preedit(), "");
    try testz.expectTrue(kb.preeditCursorByte() == null);
}

pub fn mouseEdgesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var mouse = Mouse.init();
    mouse.curr_mut().set(.left, true);
    try testz.expectTrue(mouse.down(.left));
    try testz.expectTrue(mouse.pressed(.left));

    mouse.finishTick();
    try testz.expectTrue(mouse.down(.left));
    try testz.expectFalse(mouse.pressed(.left));

    mouse.curr_mut().set(.left, false);
    try testz.expectTrue(mouse.released(.left));
}

/// Scroll accumulates across the events in a tick and is consumed by
/// `finishTick`.
pub fn mouseScrollTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var mouse = Mouse.init();
    mouse.curr_mut().scroll_delta.y += 1.0;
    mouse.curr_mut().scroll_delta.y += 2.0;
    try testz.expectEqual(mouse.scroll().y, 3.0);

    mouse.finishTick();
    try testz.expectEqual(mouse.scroll().y, 0.0);
}

/// Motion accumulates across events in a tick and is consumed by
/// `finishTick`.
pub fn mouseDeltaTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var mouse = Mouse.init();
    mouse.curr_mut().addRawMotion(10.0, 11.0, 3.0, 4.0);
    mouse.curr_mut().addRawMotion(12.0, 10.0, 2.0, -1.0);

    try testz.expectEqual(mouse.delta().x, 5.0);
    try testz.expectEqual(mouse.delta().y, 3.0);
    try testz.expectEqual(mouse.rawPos().x, 12.0);
    try testz.expectEqual(mouse.rawPos().y, 10.0);

    mouse.finishTick();
    try testz.expectEqual(mouse.delta().x, 0.0);
    try testz.expectEqual(mouse.delta().y, 0.0);
}

/// Sticks pass through as -1..1; triggers, which SDL reports as 0..32767,
/// are rescaled onto the engine's -1..1 range.
pub fn gamepadAxisScalingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    try testz.expectEqual(keys.axisValue(.left_x, 0), 0.0);
    try testz.expectEqual(keys.axisValue(.left_x, 32767), 1.0);
    try testz.expectEqual(keys.axisValue(.left_x, -32767), -1.0);

    try testz.expectEqual(keys.axisValue(.left_trigger, 0), -1.0);
    try testz.expectEqual(keys.axisValue(.right_trigger, 32767), 1.0);
}

/// Key chord printing reads these names, and menus show them to players.
pub fn keyDisplayNameTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    try testz.expectEqualStr(keys.displayName(.a), "A");
    try testz.expectEqualStr(keys.displayName(.grave_accent), "`");
    try testz.expectEqualStr(keys.displayName(.F1), "F1");
    try testz.expectEqualStr(keys.displayName(.kp_add), "kp_add");
    try testz.expectEqualStr(keys.displayName(.left_control), "left_control");
}
