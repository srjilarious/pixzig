const std = @import("std");
const testz = @import("testz");
const input = @import("pixzig").input;
const InputManager = input.InputManager;
const InputOptions = input.InputOptions;

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
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bind(.jump, .{ .key = .space });
    try actions.bind(.shoot, .{ .key = .a });
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.keyboard.currKeys_mut().set(.space, true);
    _ = actions.update(&inputs);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.keyboard.currKeys_mut().clear();
    inputs.keyboard.currKeys_mut().set(.a, true);
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));
}

pub fn multipleBindingKbActions(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bind(.jump, .{ .key = .space });
    try actions.bind(.shoot, .{ .key = .a });
    try actions.bind(.shoot, .{ .key = .z });
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.keyboard.currKeys_mut().set(.a, true);
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    inputs.keyboard.currKeys_mut().set(.z, true);
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    inputs.keyboard.currKeys_mut().set(.z, false);
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    inputs.keyboard.currKeys_mut().set(.a, false);
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));
}

pub fn basicMouseAction(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{ .mouse = true });
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bind(.jump, .{ .mouse_button = .left });
    try actions.bind(.shoot, .{ .mouse_button = .right });
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.mouse.curr_mut().set(.left, true);
    _ = actions.update(&inputs);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.mouse.curr_mut().clear();
    inputs.mouse.curr_mut().set(.right, true);
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));
}

pub fn buttonsAxisNoInput(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });
    _ = actions.update(&inputs);
    try testz.expectEqual(actions.axis(.move_x), 0.0);
}

pub fn buttonsAxisPositive(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });
    inputs.keyboard.currKeys_mut().set(.right, true);
    _ = actions.update(&inputs);
    try testz.expectEqual(actions.axis(.move_x), 1.0);
}

pub fn buttonsAxisNegative(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });

    inputs.keyboard.currKeys_mut().set(.left, true);
    _ = actions.update(&inputs);
    try testz.expectEqual(actions.axis(.move_x), -1.0);
}

pub fn buttonsAxisBothPressed(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        },
    });
    inputs.keyboard.currKeys_mut().set(.left, true);
    inputs.keyboard.currKeys_mut().set(.right, true);
    _ = actions.update(&inputs);
    try testz.expectEqual(actions.axis(.move_x), 0.0);
}

pub fn buttonsAxisIndependentAxes(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
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
    inputs.keyboard.currKeys_mut().set(.right, true);
    inputs.keyboard.currKeys_mut().set(.up, true);
    _ = actions.update(&inputs);
    try testz.expectEqual(actions.axis(.move_x), 1.0);
    try testz.expectEqual(actions.axis(.move_y), 1.0);
}
