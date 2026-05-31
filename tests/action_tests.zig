const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const input = pixzig.input;
const InputManager = input.InputManager;
const InputOptions = input.InputOptions;
const ScriptEngine = pixzig.scripting.ScriptEngine;

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
    try testz.expectTrue(actions.up(.jump));

    try testz.expectFalse(actions.down(.shoot));
    try testz.expectTrue(actions.up(.shoot));

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

// --- loadFromLua ---

const luaKeyBinding =
    \\bindings = {
    \\    { action="jump", type="key", key="space" },
    \\    { action="shoot", type="key", key="z" },
    \\}
;

pub fn loadFromLuaKeyBinding(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();
    try eng.run(luaKeyBinding);

    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.loadFromLua(&eng, "bindings");

    inputs.keyboard.currKeys_mut().set(.space, true);
    _ = actions.update(&inputs);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.keyboard.currKeys_mut().clear();
    inputs.keyboard.currKeys_mut().set(.z, true);
    _ = actions.update(&inputs);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));
}

const luaMouseBinding =
    \\bindings = {
    \\    { action="jump", type="mouse_button", button="left" },
    \\}
;

pub fn loadFromLuaMouseBinding(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();
    try eng.run(luaMouseBinding);

    var inputs = InputManager.init(.{ .mouse = true });
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.loadFromLua(&eng, "bindings");

    inputs.mouse.curr_mut().set(.left, true);
    _ = actions.update(&inputs);
    try testz.expectTrue(actions.down(.jump));
}

const luaButtonsAxis =
    \\bindings = {
    \\    { axis="move_x", type="buttons", neg="a", pos="d" },
    \\}
;

pub fn loadFromLuaButtonsAxis(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();
    try eng.run(luaButtonsAxis);

    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.loadFromLua(&eng, "bindings");

    inputs.keyboard.currKeys_mut().set(.d, true);
    _ = actions.update(&inputs);
    try testz.expectEqual(actions.axis(.move_x), 1.0);

    inputs.keyboard.currKeys_mut().clear();
    inputs.keyboard.currKeys_mut().set(.a, true);
    _ = actions.update(&inputs);
    try testz.expectEqual(actions.axis(.move_x), -1.0);
}

const luaUnknownAction =
    \\bindings = {
    \\    { action="fly", type="key", key="space" },
    \\}
;

pub fn loadFromLuaUnknownActionError(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();
    try eng.run(luaUnknownAction);

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    var got_error = false;
    actions.loadFromLua(&eng, "bindings") catch |err| {
        try testz.expectEqual(err, error.UnknownAction);
        got_error = true;
    };
    try testz.expectTrue(got_error);
}

const luaUnknownKey =
    \\bindings = {
    \\    { action="jump", type="key", key="turbo_boost" },
    \\}
;

pub fn loadFromLuaUnknownKeyError(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();
    try eng.run(luaUnknownKey);

    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    var got_error = false;
    actions.loadFromLua(&eng, "bindings") catch |err| {
        try testz.expectEqual(err, error.UnknownKey);
        got_error = true;
    };
    try testz.expectTrue(got_error);
}

const luaMixedBindings =
    \\bindings = {
    \\    { action="jump",  type="key",     key="space" },
    \\    { action="shoot", type="key",     key="z" },
    \\    { axis="move_x",  type="buttons", neg="left", pos="right" },
    \\    { axis="move_y",  type="buttons", neg="down", pos="up" },
    \\}
;

pub fn loadFromLuaMixedBindings(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();
    try eng.run(luaMixedBindings);

    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.loadFromLua(&eng, "bindings");

    inputs.keyboard.currKeys_mut().set(.space, true);
    inputs.keyboard.currKeys_mut().set(.right, true);
    inputs.keyboard.currKeys_mut().set(.up, true);
    _ = actions.update(&inputs);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));
    try testz.expectEqual(actions.axis(.move_x), 1.0);
    try testz.expectEqual(actions.axis(.move_y), 1.0);
}
