const std = @import("std");
const builtin = @import("builtin");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;
const FontAtlas = pixzig.renderer.FontAtlas;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{ .gameScale = 3.0, .rendererOpts = .{ .textRenderering = true } });

pub const App = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    atlas: FontAtlas,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        app.* = .{
            .fps = FpsCounter.init(),
            .alloc = alloc,
            .atlas = FontAtlas.initFromBitmap("assets/font5r.png", 16, 19, 19, "abcdefghijklmnopqrstuvwxyz| 0123456789*#!`:.,\\?-+=$&%()'", alloc) catch {
                std.log.err("Failed to load font atlas.", .{});
                return error.FontLoadFailed;
            },
        };

        eng.renderer.impl.text.setAtlas(&app.atlas);

        return app;
    }

    pub fn deinit(self: *App) void {
        std.log.info("Deiniting application..", .{});
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.0, 0.0, 0.2, 1.0);
        self.fps.renderTick();

        eng.renderer.begin(eng.projMat);

        const size = eng.renderer.drawString("@!$ hello world!", .{ .x = 0, .y = 60 });

        eng.renderer.drawEnclosingRect(RectF.fromPosSize(20, 320, size.x, size.y), Color.from(100, 255, 100, 255), 2);

        eng.renderer.end();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Bitmap Font Text Rendering Example", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig Text Rendering Example.", alloc, .{ .renderInitOpts = .{} });
    const app = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
