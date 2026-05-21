const std = @import("std");
const testz = @import("testz");
const input = @import("pixzig").input;
const Keyboard = input.Keyboard;

const TestActions = enum {
    run,
    jump,
    shoot,
};

pub fn basicKbActions(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kb = Keyboard.init();

    var actions = try input.ActionMap(TestActions).init(alloc);
    defer actions.deinit();

    try actions.bind(.jump, .{ .key = .space });
    try actions.bind(.shoot, .{ .key = .a });
    _ = actions.update(&kb);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    kb.currKeys_mut().set(.space, true);
    _ = actions.update(&kb);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    kb.currKeys_mut().clear();
    kb.currKeys_mut().set(.a, true);
    _ = actions.update(&kb);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));
}
