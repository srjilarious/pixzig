const std = @import("std");
const builtin = @import("builtin");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import("zstbi");
const zmath = @import("zmath");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    projMat: zmath.Mat,
    scrollOffset: Vec2F,
    tex: *pixzig.Texture,
    fps: FpsCounter,

    dest: [3]RectF,
    srcCoords: [3]RectF,
    destRects: [3]RectF,
    colorRects: [3]Color,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const tst = try alloc.alloc(u8, 100);
        @memset(tst, 123);

        std.log.debug("Loading texture...\n", .{});
        const tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");

        app.* = .{
            .alloc = alloc,
            .projMat = projMat,
            .scrollOffset = .{ .x = 0, .y = 0 },
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

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) std.log.info("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.log.info("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.log.info("three!\n", .{});
        const ScrollAmount = 3;
        if (eng.keyboard.down(.left)) {
            self.scrollOffset.x += ScrollAmount;
        }
        if (eng.keyboard.down(.right)) {
            self.scrollOffset.x -= ScrollAmount;
        }
        if (eng.keyboard.down(.up)) {
            self.scrollOffset.y += ScrollAmount;
        }
        if (eng.keyboard.down(.down)) {
            self.scrollOffset.y -= ScrollAmount;
        }
        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);
        self.fps.renderTick();

        eng.renderer.begin(self.projMat);

        for (0..3) |idx| {
            eng.renderer.draw(self.tex, self.dest[idx], self.srcCoords[idx]);
        }

        // Draw sprite outlines.
        for (0..3) |idx| {
            eng.renderer.drawRect(self.dest[idx], Color.from(255, 255, 0, 200), 2);
        }
        for (0..3) |idx| {
            eng.renderer.drawEnclosingRect(self.dest[idx], Color.from(255, 0, 255, 200), 2);
        }
        for (0..3) |idx| {
            eng.renderer.drawFilledRect(self.destRects[idx], self.colorRects[idx]);
        }

        eng.renderer.end();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Sprite and Shape test!", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig Sprites Example.", alloc, .{});
    const app = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
