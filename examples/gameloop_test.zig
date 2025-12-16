const std = @import("std");
const builtin = @import("builtin");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Delay = pixzig.utils.Delay;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

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
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
        if (eng.keyboard.pressed(.left)) {
            std.debug.print("Left!\n", .{});
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
    var app = App.init(123);

    glfw.swapInterval(0);
    appRunner.run(&app);
}
