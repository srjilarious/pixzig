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

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    testVal: i32,
    audioEngine: *zaudio.Engine,
    sample: *zaudio.Sound,
    fps: FpsCounter,
    delay: Delay = .{ .max = 120 },

    pub fn init(allocator: std.mem.Allocator) !App {
        zaudio.init(allocator);

        const engine = try zaudio.Engine.create(null);

        const sample = try engine.createSoundFromFile(
            "assets/laserShoot.wav",
            .{},
        );

        return .{ .testVal = 123, .audioEngine = engine, .sample = sample, .fps = FpsCounter.init() };
    }

    pub fn deinit(self: *App) void {
        self.sample.destroy();
        self.audioEngine.destroy();
        zaudio.deinit();
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
        if (eng.keyboard.pressed(.left)) {
            std.debug.print("Left!\n", .{});
            self.sample.start() catch |err| {
                std.debug.print("Error playing sound: {}\n", .{err});
            };
            self.testVal -= 1;
        }
        if (eng.keyboard.pressed(.right)) {
            std.debug.print("Right!\n", .{});
            self.testVal += 1;
        }
        if (eng.keyboard.pressed(.space)) {
            std.debug.print("Context: {}\n", .{self.testVal});
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

pub fn main() !void {
    std.log.info("Pixzig Game Loop Example", .{});

    const alloc = std.heap.c_allocator;

    const appRunner = try AppRunner.init("Pixzig Game Loop Example.", alloc, .{});
    var app = try App.init(alloc);

    glfw.swapInterval(0);
    appRunner.run(&app);
}
