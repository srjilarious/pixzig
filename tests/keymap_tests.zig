const std = @import("std");
const testz = @import("testz");
const input = @import("pixzig").input;
const KeyMap = input.KeyMap;
const KeyChordPiece = input.KeyChordPiece;
const KeyboardState = input.KeyboardState;
const ChordTree = input.ChordTree;

const keychord = input.keychord;

pub fn keyboardStateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
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

pub fn simpleChordTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var km = try KeyMap.init(alloc);
    defer km.deinit();

    _ = try km.addKeyChord(.{ .ctrl = true }, .a, "test", null);
}

pub fn printKeyChordPieceTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const kp1 = input.KeyChordPiece.from(.{ .ctrl = true, .shift = true }, .a);

    var buff: [256]u8 = undefined;
    const len1 = try kp1.print(buff[0..]);
    try testz.expectEqualStr(buff[0..len1], "Ctrl+Shift+A");

    var kc = try input.KeyChord.init(alloc, kp1, null);

    // Only need to deinit the top key chord as it will free its children.
    defer kc.deinit();

    const kp2 = KeyChordPiece.from(.{ .alt = true }, .p);
    const kc2 = try alloc.create(input.KeyChord);
    kc2.* = try input.KeyChord.init(alloc, kp2, "another");

    try kc.children.put(kp2, kc2);
    const len2 = try kc.print(buff[0..]);
    try testz.expectEqualStr(buff[0..len2], "Ctrl+Shift+A, Alt+P: another");
}

pub fn addSingleKeyChordTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
    defer kmap.deinit();

    _ = try kmap.addKeyChord(.{ .ctrl = true }, .a, "test", null);
    const chord = kmap.chords.rootChord.children.get(KeyChordPiece.from(.{ .ctrl = true }, .a)).?;
    try testz.expectEqualStr(chord.func.?, "test");
}

pub fn simpleChordTreeUpdateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
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

pub fn twoKeyChordUpdateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
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
pub fn twoKeyChordUpdateDifferentModsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
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

pub fn repeatKeyChordTrigger(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
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
        const res = kmap.update(&kbState, keychord.InitialRepeatRate - 1000);
        try testz.expectEqual(res, input.ChordUpdateResult.none);
    }

    {
        const res = kmap.update(&kbState, 2000);
        const func = res.triggered.func;
        try testz.expectEqualStr(func.?, "testThing");
    }
}

pub fn charFromKeyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    try testz.expectEqual(input.charFromKey(.a, false), 'a');
    try testz.expectEqual(input.charFromKey(.a, true), 'A');
    try testz.expectEqual(input.charFromKey(.comma, true), '<');
    try testz.expectEqual(input.charFromKey(.grave_accent, false), '`');
    try testz.expectEqual(input.charFromKey(.grave_accent, true), '~');
    try testz.expectEqual(input.charFromKey(.F1, false), null);
    try testz.expectEqual(input.charFromKey(.F1, true), null);
}

// ----------------------------------------------------------------------------
// Text input tests.
// ----------------------------------------------------------------------------

pub fn textInputTest_1(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var kb = input.Keyboard.init();
    kb.currKeys().set(.a, true);
    kb.currKeys().set(.left_shift, true);
    var buff: [5]u8 = undefined;
    const len = kb.text(buff[0..]);
    try testz.expectEqual(len, 1);
    try testz.expectEqualStr(buff[0..len], "A");
}

pub fn textInputTest_2(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var kb = input.Keyboard.init();
    kb.currKeys().set(.t, true);
    kb.currKeys().set(.g, true);
    kb.currKeys().set(.right_shift, true);
    var buff: [5]u8 = undefined;
    const len = kb.text(buff[0..]);
    try testz.expectEqual(len, 2);
    try testz.expectEqualStr(buff[0..len], "GT");
}

pub fn textInputTest_3(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var kb = input.Keyboard.init();
    kb.currKeys().set(.t, true);
    kb.currKeys().set(.g, true);
    kb.currKeys().set(.right_shift, true);
    var buff: [1]u8 = undefined;
    const len = kb.text(buff[0..]);
    try testz.expectEqual(len, 1);
    try testz.expectEqualStr(buff[0..len], "G");
}

pub fn textInputTest_4(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var kb = input.Keyboard.init();
    kb.currKeys().set(.space, true);
    var buff: [1]u8 = undefined;
    const len = kb.text(buff[0..]);
    try testz.expectEqual(len, 1);
    try testz.expectEqualStr(buff[0..len], " ");
}

// ----------------------------------------------------------------------------
// Reset tests
// ----------------------------------------------------------------------------

// After triggering a chord and releasing the key, an explicit reset() should
// leave the keymap in a clean state so the next update returns .none.
pub fn resetStopsRepeatTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
    defer kmap.deinit();

    _ = try kmap.addKeyChord(.{ .ctrl = true }, .a, "testThing", null);
    var kbState = KeyboardState.init();
    kbState.set(.a, true);
    kbState.set(.right_control, true);

    const res = kmap.update(&kbState, 1000);
    try testz.expectEqualStr(res.triggered.func.?, "testThing");

    // Release key, then explicitly reset.
    kbState.set(.a, false);
    kmap.reset();

    // Should be .none — not a spurious repeat or re-trigger.
    const res2 = kmap.update(&kbState, 1000);
    try testz.expectEqual(res2, input.ChordUpdateResult.none);
}

// After advancing mid-way through a two-key sequence, reset() should bring
// the state back to root so the second key alone no longer triggers.
pub fn resetMidSequenceTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
    defer kmap.deinit();

    _ = try kmap.addTwoKeyChord(.{ .ctrl = true }, .k, .l, "testThing", null);
    var kbState = KeyboardState.init();

    // Advance to intermediate node with Ctrl+K.
    kbState.set(.k, true);
    kbState.set(.right_control, true);
    const res1 = kmap.update(&kbState, 1000);
    try testz.expectEqual(res1, input.ChordUpdateResult.none);

    // Reset mid-sequence.
    kbState.set(.k, false);
    kmap.reset();

    // Ctrl+L alone should not trigger — back at root, not the intermediate node.
    kbState.set(.l, true);
    const res2 = kmap.update(&kbState, 1000);
    try testz.expectEqual(res2, input.ChordUpdateResult.none);
}

// After triggering and calling reset() while the key is still held, the next
// update should trigger immediately without waiting for InitialRepeatRate.
// This distinguishes reset from the normal hold-to-repeat path.
pub fn resetAllowsImmediateRetriggerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
    defer kmap.deinit();

    _ = try kmap.addKeyChord(.{ .ctrl = true }, .a, "testThing", null);
    var kbState = KeyboardState.init();
    kbState.set(.a, true);
    kbState.set(.right_control, true);

    // Initial trigger.
    const res1 = kmap.update(&kbState, 1000);
    try testz.expectEqualStr(res1.triggered.func.?, "testThing");

    // Reset while key still held.
    kmap.reset();

    // Should trigger immediately on the next update — no InitialRepeatRate wait.
    const res2 = kmap.update(&kbState, 1000);
    try testz.expectEqualStr(res2.triggered.func.?, "testThing");
}

// After the timeout elapses mid-sequence, update() should return .reset and
// the keymap should be back at root (second key alone no longer triggers).
pub fn timeoutReturnsResetResultTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kmap = try KeyMap.init(alloc);
    defer kmap.deinit();

    _ = try kmap.addTwoKeyChord(.{ .ctrl = true }, .k, .l, "testThing", null);
    var kbState = KeyboardState.init();

    // Advance to intermediate node.
    kbState.set(.k, true);
    kbState.set(.right_control, true);
    _ = kmap.update(&kbState, 1000);
    kbState.set(.k, false);

    // Burn past the timeout with a single large elapsed value.
    const res = kmap.update(&kbState, keychord.DefaultChordTimeoutUs + 1);
    try testz.expectEqual(res, input.ChordUpdateResult.reset);

    // After timeout, the second key alone should not trigger (back at root).
    kbState.set(.l, true);
    const res2 = kmap.update(&kbState, 1000);
    try testz.expectEqual(res2, input.ChordUpdateResult.none);
}

// ----------------------------------------------------------------------------
// context storage tests
// ----------------------------------------------------------------------------

// A non-null context string passed to ChordTree.init should be stored and
// independently allocated (pointer differs from the original).
pub fn chordTreeContextStoredTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const name: []const u8 = "my_context";
    var tree = try ChordTree.init(alloc, name);
    defer tree.deinit();

    try testz.expectTrue(tree.context != null);
    try testz.expectEqualStr(tree.context.?, "my_context");
    // Verify the string was duped, not just the original pointer stored.
    try testz.expectTrue(tree.context.?.ptr != name.ptr);
}

// A null context passed to ChordTree.init should result in a null stored context.
pub fn chordTreeNullContextTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tree = try ChordTree.init(alloc, null);
    defer tree.deinit();

    try testz.expectEqual(tree.context, null);
}
