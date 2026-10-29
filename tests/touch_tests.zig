const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const sdl = @import("sdl3");
const input = pixzig.input;
const Touch = input.Touch;
const InputManager = input.InputManager;
const ScriptEngine = pixzig.scripting.ScriptEngine;

const Actions = enum { fire, other };
const Axes = enum { move_x, move_y, look };

/// A 1000x500 screen at 2 pixels per dp, no insets.
fn testTouch() Touch {
    var touch = Touch.init();
    touch.layout(.{ .x = 1000, .y = 500 }, 2, .{ .l = 0, .t = 0, .r = 1000, .b = 500 });
    return touch;
}

pub fn touchLayoutPlacesControlsInDp(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var touch = testTouch();
    try touch.addButton(.{ .name = "a", .anchor = .bottom_right, .x = 80, .y = 50, .radius = 30 });
    try touch.addStick(.{ .name = "move", .anchor = .top_left, .x = 100, .y = 60, .radius = 40 });

    const b = touch.buttonSlice()[0];
    try testz.expectEqual(b.center.x, 1000 - 160);
    try testz.expectEqual(b.center.y, 500 - 100);
    try testz.expectEqual(b.radiusPx, 60);

    const s = touch.stickSlice()[0];
    try testz.expectEqual(s.center.x, 200);
    try testz.expectEqual(s.center.y, 120);
    try testz.expectEqual(s.radiusPx, 80);
}

pub fn touchLayoutKeepsInsideSafeArea(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var touch = Touch.init();
    try touch.addButton(.{ .name = "a", .anchor = .bottom_right, .x = 10, .y = 10 });
    // A notch on the right and a gesture bar at the bottom.
    touch.layout(.{ .x = 1000, .y = 500 }, 1, .{ .l = 0, .t = 0, .r = 900, .b = 460 });
    const b = touch.buttonSlice()[0];
    try testz.expectEqual(b.center.x, 890);
    try testz.expectEqual(b.center.y, 450);
}

pub fn touchFingerHoldsButtonUntilLifted(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var touch = testTouch();
    try touch.addButton(.{ .name = "a", .anchor = .center, .x = 0, .y = 0, .radius = 20 });
    try testz.expectFalse(touch.buttonDown("a"));
    try testz.expectFalse(touch.active);

    touch.fingerDown(7, .{ .x = 505, .y = 245 });
    try testz.expectTrue(touch.buttonDown("a"));
    try testz.expectTrue(touch.active);

    // Sliding off keeps it held; lifting releases it.
    touch.fingerMove(7, .{ .x = 900, .y = 400 });
    touch.finishTick();
    try testz.expectTrue(touch.buttonDown("a"));
    touch.fingerUp(7);
    try testz.expectFalse(touch.buttonDown("a"));

    // An unknown name is simply up.
    try testz.expectFalse(touch.buttonDown("nope"));
}

pub fn touchTapBetweenTicksStillCounts(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var touch = testTouch();
    try touch.addButton(.{ .name = "a", .anchor = .center, .x = 0, .y = 0, .radius = 20 });
    touch.fingerDown(1, .{ .x = 500, .y = 250 });
    touch.fingerUp(1);
    try testz.expectTrue(touch.buttonDown("a"));
    touch.finishTick();
    try testz.expectFalse(touch.buttonDown("a"));
}

pub fn touchStickDeflectionIsClamped(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var touch = testTouch();
    try touch.addStick(.{ .name = "move", .anchor = .center, .x = 0, .y = 0, .radius = 50 });

    touch.fingerDown(3, .{ .x = 500, .y = 250 });
    try testz.expectEqual(touch.stick("move").x, 0);
    touch.fingerMove(3, .{ .x = 550, .y = 250 });
    try testz.expectEqual(touch.stick("move").x, 0.5);
    // Twice the radius straight down: clamped to a full deflection.
    touch.fingerMove(3, .{ .x = 500, .y = 450 });
    try testz.expectEqual(touch.stick("move").x, 0);
    try testz.expectEqual(touch.stick("move").y, 1);
    touch.fingerUp(3);
    try testz.expectEqual(touch.stick("move").y, 0);
}

pub fn touchDragReadsFreeFingersInRegion(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var touch = testTouch();
    try touch.addButton(.{ .name = "a", .anchor = .top_right, .x = 50, .y = 50, .radius = 20 });

    // A free finger on the right half, one on the left, one on the button.
    touch.fingerDown(1, .{ .x = 700, .y = 300 });
    touch.fingerDown(2, .{ .x = 200, .y = 300 });
    touch.fingerDown(3, .{ .x = 900, .y = 100 });
    touch.fingerMove(1, .{ .x = 740, .y = 300 });
    touch.fingerMove(2, .{ .x = 220, .y = 310 });
    touch.fingerMove(3, .{ .x = 950, .y = 100 });

    // In dp: pixels over 2.
    try testz.expectEqual(touch.drag(.right_half).x, 20);
    try testz.expectEqual(touch.drag(.left_half).x, 10);
    try testz.expectEqual(touch.drag(.full).x, 30);
    try testz.expectEqual(touch.drag(.full).y, 5);

    touch.finishTick();
    try testz.expectEqual(touch.drag(.full).x, 0);
}

pub fn touchActionBindingsReadThePad(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var inputs = InputManager.init(.{});
    inputs.touch.layout(.{ .x = 1000, .y = 500 }, 1, .{ .l = 0, .t = 0, .r = 1000, .b = 500 });
    var actions = try input.ActionMap(Actions, Axes).init(alloc);
    defer actions.deinit();

    try actions.bind(.fire, try input.touchButton("a"));
    try actions.bindAxis(.move_x, .{ .touch_stick = .{ .stick = try input.touch.Name.init("move"), .component = .x } });
    try actions.bindAxis(.move_y, .{ .touch_stick = .{ .stick = try input.touch.Name.init("move"), .component = .y, .invert = true } });
    try actions.bindAxis(.look, .{ .touch_drag = .{ .region = .right_half, .component = .x, .sensitivity = 0.5, .clamp = 100 } });

    // No pad declared yet: the bindings read as up and 0.
    inputs.touch.fingerDown(1, .{ .x = 800, .y = 400 });
    actions.update(&inputs, 0);
    try testz.expectFalse(actions.down(.fire));
    try testz.expectEqual(actions.axis(.move_x), 0);
    inputs.touch.fingerUp(1);
    inputs.finishTick();

    try inputs.touch.addButton(.{ .name = "a", .anchor = .bottom_right, .x = 100, .y = 100, .radius = 40 });
    try inputs.touch.addStick(.{ .name = "move", .anchor = .bottom_left, .x = 100, .y = 100, .radius = 50 });

    inputs.touch.fingerDown(1, .{ .x = 900, .y = 400 });
    inputs.touch.fingerDown(2, .{ .x = 100, .y = 400 });
    inputs.touch.fingerMove(2, .{ .x = 125, .y = 375 });
    inputs.touch.fingerDown(3, .{ .x = 600, .y = 100 });
    inputs.touch.fingerMove(3, .{ .x = 640, .y = 100 });
    actions.update(&inputs, 0);
    try testz.expectTrue(actions.pressed(.fire));
    try testz.expectEqual(actions.axis(.move_x), 0.5);
    // Up on screen, inverted.
    try testz.expectEqual(actions.axis(.move_y), 0.5);
    try testz.expectEqual(actions.axis(.look), 20);
}

const touch_config =
    \\touch = {
    \\    sticks  = { { name = "move", anchor = "bottom_left", x = 100, y = 90, radius = 60 } },
    \\    buttons = {
    \\        { name = "a", label = "A", anchor = "bottom_right" },
    \\        { name = "pause", anchor = "top_right", x = 30, y = 30, radius = 20 },
    \\    },
    \\}
    \\bindings = {
    \\    { action = "fire", type = "touch_button", button = "a" },
    \\    { axis = "move_x", type = "touch_stick", stick = "move", component = "x", deadzone = 0.2 },
    \\    { axis = "look", type = "touch_drag", region = "right_half", component = "x", sensitivity = 0.35 },
    \\}
;

pub fn touchLayoutAndBindingsLoadFromLua(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var script = try ScriptEngine.init(alloc);
    defer script.deinit();
    try script.run(touch_config);

    var touch = testTouch();
    try touch.loadFromLua(&script, "touch");
    try testz.expectEqual(touch.stickSlice().len, 1);
    try testz.expectEqual(touch.buttonSlice().len, 2);
    try testz.expectEqualStr(touch.buttonSlice()[0].label.slice(), "A");
    try testz.expectEqual(touch.stickSlice()[0].radius, 60);
    // Unset fields keep their defaults.
    try testz.expectEqual(touch.buttonSlice()[0].radius, 36);
    try testz.expectEqual(touch.buttonSlice()[1].anchor, .top_right);

    var actions = try input.ActionMap(Actions, Axes).init(alloc);
    defer actions.deinit();
    try actions.loadFromLua(&script, "bindings");
    try testz.expectEqual(actions.axisBindings.items.len, 2);
    const stick = actions.axisBindings.items[0].source.touch_stick;
    try testz.expectEqualStr(stick.stick.slice(), "move");
    try testz.expectEqual(stick.deadzone, 0.2);
    try testz.expectEqual(actions.axisBindings.items[1].source.touch_drag.region, .right_half);

    // A config with no `touch` table loads nothing, without error.
    var empty = Touch.init();
    try empty.loadFromLua(&script, "no_such_global");
    try testz.expectFalse(empty.hasPad());
}

pub fn touchPadDisabledReleasesControlsAndClicks(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var inputs = InputManager.init(.{ .mouse = true });
    inputs.touch.layout(.{ .x = 1000, .y = 500 }, 2, .{ .l = 0, .t = 0, .r = 1000, .b = 500 });
    try inputs.touch.addButton(.{ .name = "a", .anchor = .center, .x = 0, .y = 0, .radius = 20 });

    inputs.touch.fingerDown(7, .{ .x = 505, .y = 245 });
    try testz.expectTrue(inputs.touch.buttonDown("a"));
    try testz.expectTrue(inputs.touch.visible());

    // Off: the held button lets go, the pad hides, and the finger drags.
    inputs.touch.setPadEnabled(false);
    try testz.expectFalse(inputs.touch.buttonDown("a"));
    try testz.expectFalse(inputs.touch.visible());
    inputs.touch.fingerMove(7, .{ .x = 525, .y = 245 });
    try testz.expectEqual(inputs.touch.drag(.full).x, 10);
    inputs.touch.fingerUp(7);

    // A new finger on the button doesn't press it, and SDL's touch-made
    // clicks reach the mouse again.
    inputs.touch.fingerDown(8, .{ .x = 505, .y = 245 });
    try testz.expectFalse(inputs.touch.buttonDown("a"));
    inputs.touch.fingerUp(8);
    var event: sdl.SDL_Event = std.mem.zeroes(sdl.SDL_Event);
    event.type = sdl.SDL_EVENT_MOUSE_BUTTON_DOWN;
    event.button.which = std.math.maxInt(sdl.SDL_MouseID);
    event.button.button = sdl.SDL_BUTTON_LEFT;
    event.button.down = true;
    inputs.handleEvent(event);
    try testz.expectTrue(inputs.mouse.down(.left));

    // Back on, that click's release still reaches the mouse, so it isn't
    // left held, and the button works again.
    inputs.finishTick();
    inputs.touch.setPadEnabled(true);
    event.type = sdl.SDL_EVENT_MOUSE_BUTTON_UP;
    event.button.down = false;
    inputs.handleEvent(event);
    try testz.expectFalse(inputs.mouse.down(.left));
    inputs.touch.fingerDown(9, .{ .x = 505, .y = 245 });
    try testz.expectTrue(inputs.touch.buttonDown("a"));
}

pub fn touchPadSwallowsEmulatedMouse(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    var inputs = InputManager.init(.{ .mouse = true });

    var event: sdl.SDL_Event = std.mem.zeroes(sdl.SDL_Event);
    event.type = sdl.SDL_EVENT_MOUSE_BUTTON_DOWN;
    event.button.which = std.math.maxInt(sdl.SDL_MouseID);
    event.button.button = sdl.SDL_BUTTON_LEFT;
    event.button.down = true;

    // Without a pad, SDL's touch-made clicks reach the mouse.
    inputs.handleEvent(event);
    try testz.expectTrue(inputs.mouse.down(.left));
    inputs.clear();

    // With one, the pad owns the touches.
    try inputs.touch.addButton(.{ .name = "a" });
    inputs.handleEvent(event);
    try testz.expectFalse(inputs.mouse.down(.left));

    // A real mouse still clicks, and hides the pad.
    inputs.touch.active = true;
    event.button.which = 1;
    inputs.handleEvent(event);
    try testz.expectTrue(inputs.mouse.down(.left));
    try testz.expectFalse(inputs.touch.active);
}
