const std = @import("std");
const testz = @import("testz");
const input = @import("pixzig").input;
const KeyMap = input.KeyMap;
const KeyChordPiece = input.KeyChordPiece;

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
