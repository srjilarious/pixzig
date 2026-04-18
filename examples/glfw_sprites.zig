//* -- collapsed: Imports --
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
//* ---

//* -- collapsed: Panic, logging and AppRunner definition--
//* Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});
//* ---

//* For this application, we load a texture and define some coordinates to
//* use for drawing sprites and shapes.
pub const App = struct {
    alloc: std.mem.Allocator,
    tex: *pixzig.Texture,
    fps: FpsCounter,

    dest: [3]RectF,
    srcCoords: [3]RectF,
    destRects: [3]RectF,
    colorRects: [3]Color,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        std.log.debug("Loading texture...\n", .{});

        //* We load a texture through the resource manager, which will cache
        //* it and return the same texture if we try to load it again.  The
        //* resource manager also handles deinitialization of the texture when
        //* the engine is deinitialized, so we don't have to worry about freeing it ourselves.

        const tex = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");

        app.* = .{
            .alloc = alloc,
            .tex = tex,
            .fps = FpsCounter.init(),
            .dest = [_]RectF{
                RectF.fromPosSize(10, 10, 32, 32),
                RectF.fromPosSize(200, 50, 32, 32),
                RectF.fromPosSize(566, 300, 32, 32),
            },

            .srcCoords = [_]RectF{
                RectF.fromCoords(32, 32, 32, 32, 512, 512),
                RectF.fromCoords(64, 64, 32, 32, 512, 512),
                RectF.fromCoords(128, 128, 32, 32, 512, 512),
            },

            .destRects = [_]RectF{
                RectF.fromPosSize(50, 40, 32, 64),
                RectF.fromPosSize(220, 80, 64, 32),
                RectF.fromPosSize(540, 316, 128, 128),
            },

            .colorRects = [_]Color{
                Color.from(255, 100, 100, 255),
                Color.from(100, 255, 200, 200),
                Color.from(25, 100, 255, 128),
            },
        };

        return app;
    }

    pub fn deinit(self: *App) void {
        std.log.info("Deiniting application..", .{});
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}\n", .{self.fps.fps()});
        }

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);
        self.fps.renderTick();

        //* We start a renderer batch, which will group together all of our draw calls and render them at once when we call end.
        eng.renderer.begin(eng.projMat);

        //* Here we're directly drawing a source rectangle from the texture to a destination rectangle on the screen.  The sprite batch will handle creating the vertices for this and batching it together with other draw calls.
        for (0..3) |idx| {
            eng.renderer.draw(self.tex, self.dest[idx], self.srcCoords[idx]);
        }

        //* Draw sprite outlines.
        for (0..3) |idx| {
            eng.renderer.drawRect(self.dest[idx], Color.from(255, 255, 0, 200), 2);
        }

        //* We can draw enclosing rects which will wrap the rectangle around the destination rectangle, which is useful for drawing outlines.
        for (0..3) |idx| {
            eng.renderer.drawEnclosingRect(self.dest[idx], Color.from(255, 0, 255, 200), 2);
        }

        //* We can also draw filled rectangles.
        for (0..3) |idx| {
            eng.renderer.drawFilledRect(self.destRects[idx], self.colorRects[idx]);
        }

        //* We finish by calling `end` which submits all of the draw calls at once.
        eng.renderer.end();
    }
};

//* -- collapsed: Main function --
pub fn main() !void {
    std.log.info("Pixzig Sprite and Shape test!", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig Sprites Example.", alloc, .{});
    const app = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
//* ---
