const std = @import("std");
const builtin = @import("builtin");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Delay = pixzig.utils.Delay;

const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    pixBuff: pixzig.pixel_buffer.PixelBuffer,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !App {
        return .{ .pixBuff = try pixzig.pixel_buffer.PixelBuffer.init(
            alloc,
            &eng.resources,
            .{
                .x = 200,
                .y = 150,
            },
        ) };
    }

    pub fn deinit(self: *App) void {
        _ = self;
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        _ = delta;
        _ = self;

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.8, 0, 0.8, 1);
        self.pixBuff.clear(28, 28, 60);
        for (0..200) |i| {
            self.pixBuff.setPixel(i, 0, 0, 255, 255);
            self.pixBuff.setPixel(i, 149, 0, 255, 0);
        }

        for (0..150) |i| {
            self.pixBuff.setPixel(0, i, 255, 255, 0);
            self.pixBuff.setPixel(199, i, 255, 0, 0);
        }

        self.pixBuff.setPixel(100, 75, 255, 0, 255);
        self.pixBuff.render();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Pixel Buffer Example", .{});

    const alloc = std.heap.c_allocator;

    const appRunner = try AppRunner.init("Pixzig Pixel Buffer Example.", alloc, .{
        .windowSize = .{ .x = 800, .y = 600 },
    });
    var app = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(&app);
}
