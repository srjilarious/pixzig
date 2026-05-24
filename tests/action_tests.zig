const std = @import("std");
const testz = @import("testz");
const input = @import("pixzig").input;
const Keyboard = input.Keyboard;
const Mouse = input.Mouse;

const TestActions = enum {
    run,
    jump,
    shoot,
};

pub fn basicKbActions(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const mouse = Mouse.init();
    var kb = Keyboard.init();

    var actions = try input.ActionMap(TestActions).init(alloc);
    defer actions.deinit();

    try actions.bind(.jump, .{ .key = .space });
    try actions.bind(.shoot, .{ .key = .a });
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    kb.currKeys_mut().set(.space, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    kb.currKeys_mut().clear();
    kb.currKeys_mut().set(.a, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));
}

pub fn multipleBindingKbActions(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kb = Keyboard.init();
    const mouse = Mouse.init();

    var actions = try input.ActionMap(TestActions).init(alloc);
    defer actions.deinit();

    try actions.bind(.jump, .{ .key = .space });
    try actions.bind(.shoot, .{ .key = .a });
    try actions.bind(.shoot, .{ .key = .z });
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    kb.currKeys_mut().set(.a, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    kb.currKeys_mut().set(.z, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    kb.currKeys_mut().set(.z, false);
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    kb.currKeys_mut().set(.a, false);
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));
}

pub fn basicMouseAction(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const kb = Keyboard.init();
    var mouse = Mouse.init();

    var actions = try input.ActionMap(TestActions).init(alloc);
    defer actions.deinit();

    try actions.bind(.jump, .{ .mouse_button = .left });
    try actions.bind(.shoot, .{ .mouse_button = .right });
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    mouse.curr_mut().set(.left, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    mouse.curr_mut().clear();
    mouse.curr_mut().set(.right, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));
}
