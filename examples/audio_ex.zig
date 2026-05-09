const std = @import("std");
const builtin = @import("builtin");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Delay = pixzig.utils.Delay;
const zaudio = pixzig.zaudio;

const math = pixzig.zmath;
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{ .audioOpts = .{ .enabled = true } });

pub const App = struct {
    alloc: std.mem.Allocator,
    testVal: i32,
    fps: FpsCounter,
    delay: Delay = .{ .max = 120 },

    pub fn init(allocator: std.mem.Allocator, engine: *AppRunner.Engine) !*App {
        engine.audio.loadSound("laserShoot", "assets/laserShoot.wav") catch |err| {
            std.log.err("Error loading sound: {}\n", .{err});
        };

        const app = try allocator.create(App);
        app.* = .{
            .alloc = allocator,
            .testVal = 123,
            // .audioEngine = engine, .sample = sample,
            .fps = FpsCounter.init(),
        };

        return app; //.{ .testVal = 123, .audioEngine = engine, .sample = sample, .fps = FpsCounter.init() };
    }

    pub fn deinit(self: *App) void {
        // self.sample.destroy();
        // self.audioEngine.destroy();
        // zaudio.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.info("FPS: {}", .{self.fps.fps()});
        }

        if (eng.keyboard.pressed(.one)) std.log.info("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.log.info("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.log.info("three!\n", .{});
        if (eng.keyboard.pressed(.left)) {
            std.log.info("Left!\n", .{});
            eng.audio.playSound("laserShoot") catch |err| {
                std.log.err("Error playing sound: {}\n", .{err});
            };

            // self.sample.start() catch |err| {
            //     std.log.info("Error playing sound: {}\n", .{err});
            // };
            self.testVal -= 1;
        }
        if (eng.keyboard.pressed(.right)) {
            std.log.info("Right!\n", .{});
            self.testVal += 1;
        }
        if (eng.keyboard.pressed(.space)) {
            std.log.info("Context: {}\n", .{self.testVal});
        }
        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 1, 1);
        self.fps.renderTick();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Game Loop Example", .{});

    const appRunner = try AppRunner.init("Pixzig Game Loop Example.", init.gpa, .{});
    const app = try App.init(init.gpa, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
