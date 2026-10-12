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
    actions.update(&inputs, 0);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.keyboard.currKeysPtr().set(.space, true);
    actions.update(&inputs, 0);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.keyboard.currKeysPtr().clear();
    inputs.keyboard.currKeysPtr().set(.a, true);
    actions.update(&inputs, 0);
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
    actions.update(&inputs, 0);

    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.up(.jump));

    try testz.expectFalse(actions.down(.shoot));
    try testz.expectTrue(actions.up(.shoot));

    inputs.keyboard.currKeysPtr().set(.a, true);
    actions.update(&inputs, 0);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    inputs.keyboard.currKeysPtr().set(.z, true);
    actions.update(&inputs, 0);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    inputs.keyboard.currKeysPtr().set(.z, false);
    actions.update(&inputs, 0);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));

    inputs.keyboard.currKeysPtr().set(.a, false);
    actions.update(&inputs, 0);
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
    actions.update(&inputs, 0);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.mouse.currPtr().set(.left, true);
    actions.update(&inputs, 0);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.mouse.currPtr().clear();
    inputs.mouse.currPtr().set(.right, true);
    actions.update(&inputs, 0);
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
    actions.update(&inputs, 0);
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
    inputs.keyboard.currKeysPtr().set(.right, true);
    actions.update(&inputs, 0);
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

    inputs.keyboard.currKeysPtr().set(.left, true);
    actions.update(&inputs, 0);
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
    inputs.keyboard.currKeysPtr().set(.left, true);
    inputs.keyboard.currKeysPtr().set(.right, true);
    actions.update(&inputs, 0);
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
    inputs.keyboard.currKeysPtr().set(.right, true);
    inputs.keyboard.currKeysPtr().set(.up, true);
    actions.update(&inputs, 0);
    try testz.expectEqual(actions.axis(.move_x), 1.0);
    try testz.expectEqual(actions.axis(.move_y), 1.0);
}

pub fn mouseAxisUsesMotionDelta(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{ .mouse = true });
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindAxis(.move_x, .{
        .mouse_axis = .{ .axis = .x, .sensitivity = 0.25, .clamp = 2.0 },
    });

    inputs.mouse.currPtr().addRawMotion(50.0, 20.0, 4.0, 0.0);
    actions.update(&inputs, 0);
    try testz.expectEqual(actions.axis(.move_x), 1.0);

    inputs.finishTick();
    inputs.mouse.currPtr().addRawMotion(52.0, 20.0, 20.0, 0.0);
    actions.update(&inputs, 0);
    try testz.expectEqual(actions.axis(.move_x), 2.0);
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

    inputs.keyboard.currKeysPtr().set(.space, true);
    actions.update(&inputs, 0);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.keyboard.currKeysPtr().clear();
    inputs.keyboard.currKeysPtr().set(.z, true);
    actions.update(&inputs, 0);
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

    inputs.mouse.currPtr().set(.left, true);
    actions.update(&inputs, 0);
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

    inputs.keyboard.currKeysPtr().set(.d, true);
    actions.update(&inputs, 0);
    try testz.expectEqual(actions.axis(.move_x), 1.0);

    inputs.keyboard.currKeysPtr().clear();
    inputs.keyboard.currKeysPtr().set(.a, true);
    actions.update(&inputs, 0);
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

    inputs.keyboard.currKeysPtr().set(.space, true);
    inputs.keyboard.currKeysPtr().set(.right, true);
    inputs.keyboard.currKeysPtr().set(.up, true);
    actions.update(&inputs, 0);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));
    try testz.expectEqual(actions.axis(.move_x), 1.0);
    try testz.expectEqual(actions.axis(.move_y), 1.0);
}

// --- chord bindings ---

pub fn singleKeyChordAction(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindChord(.{ .mod = .{ .ctrl = true }, .key = .a }, .jump);

    // No keys down -- action should be up.
    actions.update(&inputs, 1);
    try testz.expectFalse(actions.down(.jump));

    // Ctrl+A down -- should trigger jump.
    inputs.keyboard.currKeysPtr().set(.a, true);
    inputs.keyboard.currKeysPtr().set(.right_control, true);
    actions.update(&inputs, 1);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectTrue(actions.pressed(.jump));

    // Key still held -- down stays true, pressed becomes false.
    actions.update(&inputs, 1);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.pressed(.jump));

    // Release key -- action goes up.
    inputs.keyboard.currKeysPtr().set(.a, false);
    actions.update(&inputs, 1);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.released(.jump));
}

pub fn twoKeyChordAction(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bindChord2(
        .{ .mod = .{ .ctrl = true }, .key = .k },
        .{ .mod = .{ .ctrl = true }, .key = .l },
        .shoot,
    );

    // First key of chord -- no trigger yet.
    inputs.keyboard.currKeysPtr().set(.k, true);
    inputs.keyboard.currKeysPtr().set(.right_control, true);
    actions.update(&inputs, 1);
    try testz.expectFalse(actions.down(.shoot));

    // Release first key, press second key -- chord fires.
    inputs.keyboard.currKeysPtr().set(.k, false);
    actions.update(&inputs, 1);
    inputs.keyboard.currKeysPtr().set(.l, true);
    actions.update(&inputs, 1);
    try testz.expectTrue(actions.down(.shoot));

    // Release second key -- action goes up.
    inputs.keyboard.currKeysPtr().set(.l, false);
    actions.update(&inputs, 1);
    try testz.expectFalse(actions.down(.shoot));
}

pub fn chordAndKeyIndependent(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    // Regular key for jump, chord for shoot.
    try actions.bind(.jump, .{ .key = .space });
    try actions.bindChord(.{ .mod = .{ .ctrl = true }, .key = .s }, .shoot);

    inputs.keyboard.currKeysPtr().set(.space, true);
    actions.update(&inputs, 1);
    try testz.expectTrue(actions.down(.jump));
    try testz.expectFalse(actions.down(.shoot));

    inputs.keyboard.currKeysPtr().set(.space, false);
    inputs.keyboard.currKeysPtr().set(.s, true);
    inputs.keyboard.currKeysPtr().set(.right_control, true);
    actions.update(&inputs, 1);
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.down(.shoot));
}

// --- loadFromLua chord bindings ---

const luaSingleKeyChord =
    \\bindings = {
    \\    { action="jump", type="chord", key="ctrl+a" },
    \\}
;

pub fn loadFromLuaSingleKeyChord(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();
    try eng.run(luaSingleKeyChord);

    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.loadFromLua(&eng, "bindings");

    inputs.keyboard.currKeysPtr().set(.a, true);
    inputs.keyboard.currKeysPtr().set(.right_control, true);
    actions.update(&inputs, 1);
    try testz.expectTrue(actions.down(.jump));

    inputs.keyboard.currKeysPtr().set(.a, false);
    actions.update(&inputs, 1);
    try testz.expectFalse(actions.down(.jump));
}

const luaTwoKeyChord =
    \\bindings = {
    \\    { action="shoot", type="chord", key="ctrl+k ctrl+l" },
    \\}
;

pub fn loadFromLuaTwoKeyChord(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var eng = try ScriptEngine.init(alloc);
    defer eng.deinit();
    try eng.run(luaTwoKeyChord);

    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.loadFromLua(&eng, "bindings");

    // First piece -- no trigger yet.
    inputs.keyboard.currKeysPtr().set(.k, true);
    inputs.keyboard.currKeysPtr().set(.right_control, true);
    actions.update(&inputs, 1);
    try testz.expectFalse(actions.down(.shoot));

    // Release first, press second -- chord fires.
    inputs.keyboard.currKeysPtr().set(.k, false);
    actions.update(&inputs, 1);
    inputs.keyboard.currKeysPtr().set(.l, true);
    actions.update(&inputs, 1);
    try testz.expectTrue(actions.down(.shoot));

    inputs.keyboard.currKeysPtr().set(.l, false);
    actions.update(&inputs, 1);
    try testz.expectFalse(actions.down(.shoot));
}

// A suppressed tick reads as nothing held: the held action reports a
// release edge, axes drop to 0, and the next real update presses again.
pub fn updateSuppressedClearsState(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(TestActions, TestAxes).init(alloc);
    defer actions.deinit();

    try actions.bind(.jump, .{ .key = .space });
    try actions.bindAxis(.move_x, .{ .buttons = .{
        .negative = .{ .key = .left },
        .positive = .{ .key = .right },
    } });

    inputs.keyboard.currKeysPtr().set(.space, true);
    inputs.keyboard.currKeysPtr().set(.right, true);
    actions.update(&inputs, 1);
    try testz.expectTrue(actions.pressed(.jump));
    try testz.expectEqual(actions.axis(.move_x), 1.0);

    actions.updateSuppressed();
    try testz.expectFalse(actions.down(.jump));
    try testz.expectTrue(actions.released(.jump));
    try testz.expectEqual(actions.axis(.move_x), 0.0);

    actions.update(&inputs, 1);
    try testz.expectTrue(actions.pressed(.jump));
    try testz.expectEqual(actions.axis(.move_x), 1.0);
}

// `ActionOptions.Axes` defaults to `NoAxes`, so a map with no axes must
// still build and run.
pub fn defaultAxesIsEmpty(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const Opts: input.ActionOptions = .{ .Action = TestActions };
    var inputs = InputManager.init(.{});
    var actions = try input.ActionMap(Opts.Action, Opts.Axes).init(alloc);
    defer actions.deinit();

    try actions.bind(.shoot, .{ .key = .a });
    inputs.keyboard.currKeysPtr().set(.a, true);
    actions.update(&inputs, 1);
    try testz.expectTrue(actions.pressed(.shoot));
    try testz.expectEqual(actions.axis(.none), 0.0);
    actions.updateSuppressed();
    try testz.expectTrue(actions.released(.shoot));
}
