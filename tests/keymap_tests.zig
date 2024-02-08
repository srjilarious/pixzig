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

    var buff: [256]u8 = undefined;
    const len = kp1.print(buff[0..]) catch unreachable;
    std.debug.print("{s}\n", .{buff[0..len]});

    var kc = input.KeyChord.init(std.heap.page_allocator, kp1, "test") catch unreachable;
    const kp2 = input.KeyChordPiece.from(.alt, .p);
    const kc2 = input.KeyChord.init(std.heap.page_allocator, kp2, "another") catch unreachable;
    kc.children.put(kp2, kc2) catch unreachable;
    const len2 = kc.print(buff[0..]) catch unreachable;
    std.debug.print("\n{s}\n", .{buff[0..len2]});
}
