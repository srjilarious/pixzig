//* This is a basic example of an application using the Pixzig engine.
//*
//* It shows how to use an AppRunner to run the game loop.
//*
//* The App struct has an `update` and `render` function that will be called
//* by AppRunner, and in this example we just print out the FPS and some
//* keyboard input to demonstrate that the game loop is working while clearing
//* the screen. Its controls go through the engine-owned action map, so
//* `update` asks about named actions instead of physical keys. It also
//* hears about window, drag-and-drop and lifecycle events through the
//* optional `onEvent` hook, and uses it to confirm before closing.

//* -- collapsed: Imports --
const std = @import("std");
const pixzig = @import("pixzig");

const FpsCounter = pixzig.utils.FpsCounter;

//* ---
//* Defines the application runner that will run our App.  The AppRunner
//* provides the game loop and calls the `update` and `render` functions
//* on our App struct.  It also provides the Engine to those functions,
//* which has references to the renderer, input, and other systems that
//* we can use in our game logic and rendering.
//*
//* Setting `actionOpts` asks the engine for an action map over our `Action`
//* enum, reached as `eng.actions`. The runner updates it every tick before
//* calling `App.update`, so the app only binds it and queries it.
const Action = enum { one, two, three, left, right, show, quit };

const AppRunner = pixzig.AppRunner(App, .{
    .actionOpts = .{ .Action = Action },
});

//* This is the definition of the application that will be run by the `AppRunner`.
//* It has an `update` and `render` function that will be called by the `AppRunner`.
//* The `update` function is where you would put your game logic, and the `render`
//* function is where you would put your rendering code.
pub const App = struct {
    testVal: i32,
    fps: FpsCounter,
    closeAsked: bool = false,

    //* Binds each action to a key. An action can take several bindings,
    //* for example a key and a gamepad button.
    pub fn init(eng: *AppRunner.Engine, val: i32) !App {
        try eng.actions.bind(.one, .{ .key = .one });
        try eng.actions.bind(.two, .{ .key = .two });
        try eng.actions.bind(.three, .{ .key = .three });
        try eng.actions.bind(.left, .{ .key = .left });
        try eng.actions.bind(.right, .{ .key = .right });
        try eng.actions.bind(.show, .{ .key = .space });
        try eng.actions.bind(.quit, .{ .key = .escape });
        return .{ .testVal = val, .fps = FpsCounter.init() };
    }

    pub fn deinit(self: *App) void {
        _ = self;
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) void {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        const actions = eng.actions;
        if (actions.pressed(.one)) std.log.info("one!\n", .{});
        if (actions.pressed(.two)) std.log.info("two!\n", .{});
        if (actions.pressed(.three)) std.log.info("three!\n", .{});
        if (actions.pressed(.left)) {
            std.log.info("Left!\n", .{});
            self.testVal -= 1;
        }
        if (actions.pressed(.right)) {
            std.log.info("Right!\n", .{});
            self.testVal += 1;
        }
        if (actions.pressed(.show)) {
            std.log.info("Context: {}\n", .{self.testVal});
        }
        if (actions.pressed(.quit)) {
            eng.quit();
            return;
        }
    }

    //* `onEvent` is optional. The runner calls it for everything the OS
    //* reports that isn't keyboard, mouse or text input, during the event
    //* pump and before this frame's `update` calls. Here the first close
    //* request is cancelled and the second one goes through.
    pub fn onEvent(self: *App, eng: *AppRunner.Engine, event: pixzig.Event) void {
        switch (event) {
            .close_requested => {
                if (!self.closeAsked) {
                    std.log.info("Close again to quit.", .{});
                    self.closeAsked = true;
                    eng.cancelClose();
                }
            },
            .window_resized => |size| std.log.info("Resized to {}x{}", .{ size.x, size.y }),
            .drop_file => |drop| std.log.info("Dropped {s} at {d},{d}", .{ drop.path, drop.pos.x, drop.pos.y }),
            .drop_text => |drop| std.log.info("Dropped text: {s}", .{drop.text}),
            else => std.log.info("Event: {t}", .{event}),
        }
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 255, 255);
        self.fps.renderTick();
    }
};

//* This is the main function that will be called when the program is run.
//* It initializes your App structure, the AppRunner and runs the application.
//* It hands over control of the gameloop to AppRunner so that both desktop
//* and web builds can use the same main function.
pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig Game Loop Example.", init.gpa, .{});
    defer appRunner.deinit();

    var app = try App.init(appRunner.engine, 123);
    defer app.deinit();

    appRunner.run(&app);
}
