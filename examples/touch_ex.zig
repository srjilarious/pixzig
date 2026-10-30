//* This example shows the virtual touch pad: an on-screen stick and two
//* buttons that feed the engine's action map like any other device.
//*
//* The controls and their bindings live in one Lua config, next to the
//* keyboard bindings for the same actions. On a phone the stick moves the
//* square and the buttons change its colour; on a desktop the arrow keys and
//* Z/X do the same, and the touch bindings simply read as up. Dragging a
//* finger on the right half of the screen (or the mouse, with no pad)
//* spins the square.

//* -- collapsed: Imports --
const std = @import("std");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const Color = pixzig.common.Color;
//* ---

const Action = enum { recolor, reset };
const Axes = enum { move_x, move_y, spin };

const AppRunner = pixzig.AppRunner(App, .{
    .scripting = true,
    .actionOpts = .{ .Action = Action, .Axes = Axes },
    .screenshotHook = true,
});

//* The whole config. A game would keep this in `assets/` and run it with
//* `eng.scripts.runScript`; it's inline here to keep the example to one file.
//*
//* `touch` lays out the pad in dp, measured inward from a screen corner.
//* The bindings name its controls by `name`.
const config =
    \\touch = {
    \\    sticks  = { { name = "move", anchor = "bottom_left", x = 120, y = 120, radius = 80 } },
    \\    buttons = {
    \\        { name = "a", label = "A", anchor = "bottom_right", x = 70,  y = 130, radius = 40 },
    \\        { name = "b", label = "B", anchor = "bottom_right", x = 160, y = 70,  radius = 40 },
    \\    },
    \\}
    \\bindings = {
    \\    { action = "recolor", type = "key", key = "z" },
    \\    { action = "recolor", type = "touch_button", button = "a" },
    \\    { action = "reset",   type = "key", key = "x" },
    \\    { action = "reset",   type = "touch_button", button = "b" },
    \\
    \\    { axis = "move_x", type = "buttons", neg = "left", pos = "right" },
    \\    { axis = "move_y", type = "buttons", neg = "up",   pos = "down" },
    \\    { axis = "move_x", type = "touch_stick", stick = "move", component = "x" },
    \\    { axis = "move_y", type = "touch_stick", stick = "move", component = "y" },
    \\
    \\    { axis = "spin", type = "touch_drag", region = "right_half", component = "x", sensitivity = 0.5, clamp = 10 },
    \\    { axis = "spin", type = "mouse_axis", component = "x", sensitivity = 0.5, clamp = 10 },
    \\}
;

const colors = [_]Color{
    Color.from(240, 80, 80, 255),
    Color.from(80, 220, 120, 255),
    Color.from(90, 140, 255, 255),
    Color.from(250, 210, 70, 255),
};

pub const App = struct {
    pos: pixzig.Vec2F = .{ .x = 400, .y = 240 },
    angle: f32 = 0,
    colorIdx: usize = 0,

    //* The pad is loaded before the bindings, though either order works:
    //* a binding finds its control by name each tick.
    pub fn init(eng: *AppRunner.Engine) !App {
        try eng.scripts.run(config);
        try eng.inputs.touch.loadFromLua(&eng.scripts, "touch");
        try eng.actions.loadFromLua(&eng.scripts, "bindings");
        return .{};
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) void {
        const actions = eng.actions;
        const speed: f32 = @floatCast(delta * 0.4);
        self.pos.x += actions.axis(.move_x) * speed;
        self.pos.y += actions.axis(.move_y) * speed;

        const size = eng.viewport.logicalSize;
        self.pos.x = std.math.clamp(self.pos.x, 0, @as(f32, @floatFromInt(size.x)));
        self.pos.y = std.math.clamp(self.pos.y, 0, @as(f32, @floatFromInt(size.y)));

        self.angle += actions.axis(.spin);

        if (actions.pressed(.recolor)) self.colorIdx = (self.colorIdx + 1) % colors.len;
        if (actions.pressed(.reset)) {
            self.pos = .{ .x = @floatFromInt(@divTrunc(size.x, 2)), .y = @floatFromInt(@divTrunc(size.y, 2)) };
            self.angle = 0;
        }
    }

    //* The square's size wobbles with its spin, since the renderer draws
    //* rectangles axis-aligned. The pad itself is drawn by the engine after
    //* `render`.
    pub fn render(self: *App, eng: *AppRunner.Engine, alpha: f32) void {
        _ = alpha;
        eng.renderer.clear(20, 24, 40, 255);
        eng.renderer.begin(.logical);
        const half = 40 + 20 * @sin(self.angle / 30);
        eng.renderer.drawFilledRect(
            RectF.fromPosSize(self.pos.x - half, self.pos.y - half, half * 2, half * 2),
            colors[self.colorIdx],
        );
        _ = eng.renderer.drawString("Stick or arrows: move.  A or Z: colour.  B or X: reset.  Drag right half: spin.", .{ .x = 10, .y = 10 });
        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig Touch Example", init.gpa, .{
        .logicalSize = .{ .x = 800, .y = 480 },
    });
    defer appRunner.deinit();

    var app = try App.init(appRunner.engine);
    appRunner.run(&app);
}
