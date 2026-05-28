//* This is a basic example of an application using the Pixzig engine.
//*
//* It shows how to set things up so that the panic handler and logging work
//* correctly on both desktop and web targets, and how to use an AppRunner to
//* run the game loop.
//*
//* The App struct has an `update` and `render` function that will be called
//* by AppRunner, and in this example we just print out the FPS and some
//* keyboard input to demonstrate that the game loop is working while clearing
//* the screen.

//* -- collapsed: Imports --
const std = @import("std");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Delay = pixzig.utils.Delay;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;

//* ---

//* Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

//* Defines the application runner that will run our App.  The AppRunner
//* provides the game loop and calls the `update` and `render` functions
//* on our App struct.  It also provides the Engine to those functions,
//* which has references to the renderer, input, and other systems that
//* we can use in our game logic and rendering.
const AppRunner = pixzig.PixzigAppRunner(App, .{});

//* This is the definition of the application that will be run by the `AppRunner`.
//* It has an `update` and `render` function that will be called by the `AppRunner`.
//* The `update` function is where you would put your game logic, and the `render`
//* function is where you would put your rendering code.
pub const App = struct {
    testVal: i32,
    fps: FpsCounter,
    delay: Delay = .{ .max = 120 },

    pub fn init(val: i32) App {
        return .{ .testVal = val, .fps = FpsCounter.init() };
    }

    pub fn deinit(self: *App) void {
        _ = self;
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.inputs.keyboard.pressed(.one)) std.log.info("one!\n", .{});
        if (eng.inputs.keyboard.pressed(.two)) std.log.info("two!\n", .{});
        if (eng.inputs.keyboard.pressed(.three)) std.log.info("three!\n", .{});
        if (eng.inputs.keyboard.pressed(.left)) {
            std.log.info("Left!\n", .{});
            self.testVal -= 1;
        }
        if (eng.inputs.keyboard.pressed(.right)) {
            std.log.info("Right!\n", .{});
            self.testVal += 1;
        }
        if (eng.inputs.keyboard.pressed(.space)) {
            std.log.info("Context: {}\n", .{self.testVal});
        }
        if (eng.inputs.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 1, 1);
        self.fps.renderTick();
    }
};

//* This is the main function that will be called when the program is run.
//* It initializes your App structure, the AppRunner and runs the application.
//* It hands over control of the gameloop to AppRunner so that both desktop
//* and web builds can use the same main function.
pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Game Loop Example", .{});

    const appRunner = try AppRunner.init("Pixzig Game Loop Example.", init.gpa, .{});
    var app = App.init(123);

    appRunner.run(&app);
}
