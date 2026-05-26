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

const TestAxes = enum {
    move_x,
    move_y,
};

pub fn basicKbActions(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const mouse = Mouse.init();
    var kb = Keyboard.init();

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
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

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
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

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
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

pub fn buttonsAxisNoInput(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kb = Keyboard.init();
    const mouse = Mouse.init();

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });
    _ = actions.update(&kb, &mouse);
    try testz.expectEqual(actions.axis(.move_x), 0.0);
}

pub fn buttonsAxisPositive(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kb = Keyboard.init();
    const mouse = Mouse.init();

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });
    kb.currKeys_mut().set(.right, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectEqual(actions.axis(.move_x), 1.0);
}

pub fn buttonsAxisNegative(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kb = Keyboard.init();
    const mouse = Mouse.init();

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });

    kb.currKeys_mut().set(.left, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectEqual(actions.axis(.move_x), -1.0);
}

pub fn buttonsAxisBothPressed(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kb = Keyboard.init();
    const mouse = Mouse.init();

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });
    kb.currKeys_mut().set(.left, true);
    kb.currKeys_mut().set(.right, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectEqual(actions.axis(.move_x), 0.0);
}

pub fn buttonsAxisIndependentAxes(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var kb = Keyboard.init();
    const mouse = Mouse.init();

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });
    try actions.bindAxis(.move_y, .{
        .buttons = .{
            .negative = .{ .key = .down },
            .positive = .{ .key = .up },
        },
    });
    kb.currKeys_mut().set(.right, true);
    kb.currKeys_mut().set(.up, true);
    _ = actions.update(&kb, &mouse);
    try testz.expectEqual(actions.axis(.move_x), 1.0);
    try testz.expectEqual(actions.axis(.move_y), 1.0);
}
