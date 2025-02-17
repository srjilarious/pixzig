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
    mapRenderer: tile.TileMapRenderer,
    shapeBatch: pixzig.renderer.ShapeBatchQueue,
    colorShader: pixzig.shaders.Shader,
    guy: RectF,
    map: tile.TileMap,
    tex: *pixzig.Texture,
    texShader: pixzig.shaders.Shader,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader,
        );

        const tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");

        std.log.info("Loading tile map", .{});
        const map = try tile.TileMap.initFromFile("assets/level1a.tmx", alloc);

        const tData = map.layers.items[1].tile(0, 0);
        std.log.info("Tile 0,0 data: {any}", .{tData});

        std.log.info("Initializing map renderer.", .{});
        var mapRender = try tile.TileMapRenderer.init(alloc, texShader);

        std.log.info("Creating tile renderering data.", .{});
        try mapRender.recreateVertices(&map.tilesets.items[0], &map.layers.items[1]);

        std.log.info("Done creating tile renderering data.", .{});

        var colorShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.ColorVertexShader,
            &pixzig.shaders.ColorPixelShader,
        );

        const shapeBatch = try pixzig.renderer.ShapeBatchQueue.init(alloc, &colorShader);

        const app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .projMat = projMat,
            .scrollOffset = .{ .x = 0, .y = 0 },
            .mapRenderer = mapRender,
            .map = map,
            .tex = tex,
            .texShader = texShader,
            .colorShader = colorShader,
            .shapeBatch = shapeBatch,
            .guy = RectF.fromPosSize(33, 33, 32, 32),
            .fps = FpsCounter.init(),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.mapRenderer.deinit();
        self.map.deinit();
        self.texShader.deinit();
        self.shapeBatch.deinit();
        self.colorShader.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) std.log.info("one!", .{});
        if (eng.keyboard.pressed(.two)) std.log.info("two!", .{});
        if (eng.keyboard.pressed(.three)) std.log.info("three!", .{});
        const ScrollAmount = 3;
        if (eng.keyboard.down(.a)) {
            self.scrollOffset.x += ScrollAmount;
        }
        if (eng.keyboard.down(.d)) {
            self.scrollOffset.x -= ScrollAmount;
        }
        if (eng.keyboard.down(.w)) {
            self.scrollOffset.y += ScrollAmount;
        }
        if (eng.keyboard.down(.s)) {
            self.scrollOffset.y -= ScrollAmount;
        }
        if (eng.keyboard.pressed(.escape)) {
            return false;
        }

        // Handle guy movement.
        if (eng.keyboard.down(.left)) {
            _ = pixzig.tile.Mover.moveLeft(
                &self.guy,
                ScrollAmount,
                &self.map.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.keyboard.down(.right)) {
            _ = pixzig.tile.Mover.moveRight(
                &self.guy,
                ScrollAmount,
                &self.map.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.keyboard.down(.up)) {
            _ = pixzig.tile.Mover.moveUp(
                &self.guy,
                ScrollAmount,
                &self.map.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.keyboard.down(.down)) {
            _ = pixzig.tile.Mover.moveDown(
                &self.guy,
                ScrollAmount,
                &self.map.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);

        self.fps.renderTick();
        const mvp = zmath.mul(zmath.translation(self.scrollOffset.x, self.scrollOffset.y, 0.0), self.projMat);
        try self.mapRenderer.draw(self.tex, &self.map.layers.items[1], mvp);

        // Draw outline.
        self.shapeBatch.begin(mvp);
        self.shapeBatch.drawRect(self.guy, Color.from(255, 255, 0, 200), 2);
        self.shapeBatch.end();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Tilemap Example", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig: Tilemap Example.", alloc, .{});

    std.log.info("Initializing app.\n", .{});
    const app: *App = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
