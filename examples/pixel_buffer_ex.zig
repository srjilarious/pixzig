const std = @import("std");
const pixzig = @import("pixzig");

const AppRunner = pixzig.AppRunner(App, .{});

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
        self.pixBuff.deinit();
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        _ = delta;
        _ = self;

        if (eng.inputs.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(204, 0, 204, 255);
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

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig Pixel Buffer Example.", init.gpa, .{
        .windowSize = .{ .x = 800, .y = 600 },
    });
    defer appRunner.deinit();

    var app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(&app);
}
