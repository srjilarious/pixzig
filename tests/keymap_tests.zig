const std = @import("std");
const testz = @import("testz");
const input = @import("pixzig").input;
const KeyMap = input.KeyMap;

pub fn simpleChordTest() !void {
    // TODO: change to anyerror in testz.
    var km = KeyMap.init(std.heap.page_allocator) catch unreachable;
    defer km.deinit();

    _ = km.addKeyChord(.ctrl, .a, "test", null) catch unreachable;
}

pub fn printKeyChordPieceTest() !void {
    const kp1 = input.KeyChordPiece.from(.ctrl_shift, .a);
    kp1.print();
}
