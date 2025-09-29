const std = @import("std");
const builtin = @import("builtin");

const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const shaders = pixzig.shaders;
const Shader = shaders.Shader;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;

const GridRenderer = tile.GridRenderer;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    projMat: zmath.Mat,
    fps: FpsCounter,
    grid: GridRenderer,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        // Orthographic projection matrix
        const projMat = zmath.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const grid = try GridRenderer.init(
            alloc,
            try eng.textures.getShaderByName(shaders.ColorShader),
            .{ .x = 20, .y = 12 },
            .{ .x = 32, .y = 32 },
            1,
            Color{ .r = 1, .g = 0, .b = 1, .a = 1 },
        );

        const app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .projMat = projMat,
            .fps = FpsCounter.init(),
            .grid = grid,
        };

        return app;
    }

    pub fn deinit(self: *App) void {
        self.grid.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) std.log.debug("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.log.debug("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.log.debug("three!\n", .{});

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);
        self.fps.renderTick();
        try self.grid.draw(self.projMat);
    }
};

pub fn main() !void {
    std.log.info("Pixzig Grid Render Example", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig: Grid Render Example.", alloc, .{});

    std.log.info("Initializing app.\n", .{});
    const app: *App = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
