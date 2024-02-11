const std = @import("std");
const testz = @import("testz");
const input = @import("pixzig").input;
const KeyMap = input.KeyMap;

pub fn simpleChordTest() !void {
    // TODO: change to anyerror in testz.
    var km = try KeyMap.init(std.heap.page_allocator);
    defer km.deinit();

    _ = try km.addKeyChord(.ctrl, .a, "test", null);
}

pub fn printKeyChordPieceTest() !void {
    const kp1 = input.KeyChordPiece.from(.ctrl_shift, .a);

    var buff: [256]u8 = undefined;
    _ = try kp1.print(buff[0..]);
    // std.debug.print("{s}\n", .{buff[0..len]});

    var kc = try input.KeyChord.init(std.heap.page_allocator, kp1, "test");
    const kp2 = input.KeyChordPiece.from(.alt, .p);
    const kc2 = try input.KeyChord.init(std.heap.page_allocator, kp2, "another");
    try kc.children.put(kp2, kc2);
    _ = try kc.print(buff[0..]);
    // std.debug.print("\n{s}\n", .{buff[0..len2]});
}
