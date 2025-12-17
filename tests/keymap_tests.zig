const std = @import("std");
const testz = @import("testz");
const input = @import("pixzig").input;
const KeyMap = input.KeyMap;
const KeyChordPiece = input.KeyChordPiece;
const KeyboardState = input.KeyboardState;

pub fn keyboardStateTest() !void {
    var kbState = KeyboardState.init();
    kbState.set(.a, true);
    kbState.set(.left_alt, true);
    {
        const mods = kbState.modifiers();
        try testz.expectTrue(mods.alt and !mods.ctrl and !mods.shift and !mods.super);
    }

    kbState.set(.right_control, true);
    {
        const mods = kbState.modifiers();
        try testz.expectTrue(mods.alt and mods.ctrl and !mods.shift and !mods.super);
    }

    kbState.set(.right_shift, true);
    {
        const mods = kbState.modifiers();
        try testz.expectTrue(mods.alt and mods.ctrl and mods.shift and !mods.super);
    }

    kbState.set(.left_super, true);
    kbState.set(.right_super, true);
    kbState.set(.right_control, false);
    {
        const mods = kbState.modifiers();
        try testz.expectTrue(mods.alt and !mods.ctrl and mods.shift and mods.super);
    }
}

pub fn simpleChordTest() !void {
    var km = try KeyMap.init(std.heap.page_allocator);
    defer km.deinit();

    _ = try km.addKeyChord(.{ .ctrl = true }, .a, "test", null);
}

pub fn printKeyChordPieceTest() !void {
    const kp1 = input.KeyChordPiece.from(.{ .ctrl = true, .shift = true }, .a);

    var buff: [256]u8 = undefined;
    const len1 = try kp1.print(buff[0..]);
    try testz.expectEqualStr(buff[0..len1], "Ctrl+Shift+A");

    var kc = try input.KeyChord.init(std.heap.page_allocator, kp1, null);
    const kp2 = KeyChordPiece.from(.{ .alt = true }, .p);
    var kc2 = try input.KeyChord.init(std.heap.page_allocator, kp2, "another");
    try kc.children.put(kp2, &kc2);
    const len2 = try kc.print(buff[0..]);
    try testz.expectEqualStr(buff[0..len2], "Ctrl+Shift+A, Alt+P: another");
}

pub fn addSingleKeyChordTest() !void {
    var kmap = try KeyMap.init(std.heap.page_allocator);
    defer kmap.deinit();

    _ = try kmap.addKeyChord(.{ .ctrl = true }, .a, "test", null);
    const chord = kmap.chords.rootChord.children.get(KeyChordPiece.from(.{ .ctrl = true }, .a)).?;
    try testz.expectEqualStr(chord.func.?, "test");
}

pub fn simpleChordTreeUpdateTest() !void {
    var kmap = try KeyMap.init(std.heap.page_allocator);
    defer kmap.deinit();

    _ = try kmap.addKeyChord(.{ .ctrl = true }, .a, "testThing", null);
    var kbState = KeyboardState.init();
    kbState.set(.a, true);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.right_control, true);
    {
        const res = kmap.update(&kbState, 1000);
        const func = res.triggered.func;
        try testz.expectEqualStr(func.?, "testThing");
    }
}

pub fn twoKeyChordUpdateTest() !void {
    var kmap = try KeyMap.init(std.heap.page_allocator);
    defer kmap.deinit();

    _ = try kmap.addTwoKeyChord(.{ .ctrl = true }, .k, .l, "testThing", null);
    var kbState = KeyboardState.init();
    kbState.set(.k, true);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.right_control, true);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.k, false);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.l, true);
    {
        const res = kmap.update(&kbState, 1000);
        const func = res.triggered.func;
        try testz.expectEqualStr(func.?, "testThing");
    }
}

// Test that a complex chord with different modifiers triggers as expected.
pub fn twoKeyChordUpdateDifferentModsTest() !void {
    var kmap = try KeyMap.init(std.heap.page_allocator);
    defer kmap.deinit();

    try testz.expectTrue(try kmap.addComplexChord(
        .{ .mod = .{ .ctrl = true }, .key = .k },
        .{ .mod = .{ .super = true }, .key = .F1 },
        "testThing",
        null,
    ));

    var kbState = KeyboardState.init();
    kbState.set(.k, true);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.right_control, true);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.k, false);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.left_super, true);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.right_control, false);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.F1, true);
    {
        const res = kmap.update(&kbState, 1000);
        const func = res.triggered.func;
        try testz.expectEqualStr(func.?, "testThing");
    }
}

pub fn repeatKeyChordTrigger() !void {
    var kmap = try KeyMap.init(std.heap.page_allocator);
    defer kmap.deinit();

    _ = try kmap.addKeyChord(.{ .ctrl = true }, .a, "testThing", null);
    var kbState = KeyboardState.init();
    kbState.set(.a, true);
    {
        const res = kmap.update(&kbState, 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    kbState.set(.right_control, true);
    {
        const res = kmap.update(&kbState, 1000);
        const func = res.triggered.func;
        try testz.expectEqualStr(func.?, "testThing");
    }

    {
        const res = kmap.update(&kbState, input.InitialRepeatRate - 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    {
        const res = kmap.update(&kbState, 2000);
        const func = res.triggered.func;
        try testz.expectEqualStr(func.?, "testThing");
    }
}

pub fn charFromKeyTest() !void {
    try testz.expectEqual(input.charFromKey(.a, false), 'a');
    try testz.expectEqual(input.charFromKey(.a, true), 'A');
    try testz.expectEqual(input.charFromKey(.comma, true), '<');
    try testz.expectEqual(input.charFromKey(.grave_accent, false), '`');
    try testz.expectEqual(input.charFromKey(.grave_accent, true), '~');
    try testz.expectEqual(input.charFromKey(.F1, false), null);
    try testz.expectEqual(input.charFromKey(.F1, true), null);
}

pub fn textInputTest_1() !void {
    var kb = input.Keyboard.init();
    kb.currKeys().set(.a, true);
    kb.currKeys().set(.left_shift, true);
    var buff: [5]u8 = undefined;
    const len = kb.text(buff[0..]);
    try testz.expectEqual(len, 1);
    try testz.expectEqualStr(buff[0..len], "A");
}

pub fn textInputTest_2() !void {
    var kb = input.Keyboard.init();
    kb.currKeys().set(.t, true);
    kb.currKeys().set(.g, true);
    kb.currKeys().set(.right_shift, true);
    var buff: [5]u8 = undefined;
    const len = kb.text(buff[0..]);
    try testz.expectEqual(len, 2);
    try testz.expectEqualStr(buff[0..len], "GT");
}

pub fn textInputTest_3() !void {
    var kb = input.Keyboard.init();
    kb.currKeys().set(.t, true);
    kb.currKeys().set(.g, true);
    kb.currKeys().set(.right_shift, true);
    var buff: [1]u8 = undefined;
    const len = kb.text(buff[0..]);
    try testz.expectEqual(len, 1);
    try testz.expectEqualStr(buff[0..len], "G");
}
