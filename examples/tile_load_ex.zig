const std = @import("std");
const pixzig = @import("pixzig");
const zmath = pixzig.zmath;
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

const AppRunner = pixzig.PixzigAppRunner(App, .{ .vsyncEnabled = false });

pub const App = struct {
    alloc: std.mem.Allocator,
    camera: pixzig.Camera2D,
    mapRenderer: tile.TileMapRenderer,
    guy: RectF,
    tilemap_pool: *pixzig.ManagedTileMap,
    map_handle: *pixzig.TileMapHandle,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        _ = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");

        std.log.info("Loading tile map", .{});
        try eng.resources.loadTileMap("level1a", "assets/level1a.tmx");
        const tilemap_pool = eng.resources.tilemaps.get("level1a") orelse return error.NoTileMapWithThatName;
        const map_handle = tilemap_pool.acquire() orelse return error.NoTileMapWithThatName;

        const tData = map_handle.val.layers.items[1].tile(0, 0);
        std.log.info("Tile 0,0 data: {any}", .{tData});

        std.log.info("Initializing map renderer.", .{});
        const shader_pool = eng.resources.shaders.get(pixzig.shaders.TextureShader) orelse return error.NoShaderWithThatName;
        const texture_pool = eng.resources.atlas.get("tiles") orelse return error.NoTextureWithThatName;
        var mapRender = try tile.TileMapRenderer.init(alloc, shader_pool, texture_pool);

        std.log.info("Creating tile renderering data.", .{});
        try mapRender.recreateVertices(&map_handle.val.tilesets.items[0], &map_handle.val.layers.items[1]);

        std.log.info("Done creating tile renderering data.", .{});

        const guy_rect = RectF.fromPosSize(33, 33, 32, 32);
        var cam = pixzig.Camera2D.init(eng.viewport.logical_size);
        cam.pos = guy_rect.centerF();
        const layer = &map_handle.val.layers.items[1];
        cam.bounds = .{
            .l = 0,
            .t = 0,
            .r = @floatFromInt(layer.size.x * layer.tileSize.x),
            .b = @floatFromInt(layer.size.y * layer.tileSize.y),
        };

        const app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .camera = cam,
            .mapRenderer = mapRender,
            .tilemap_pool = tilemap_pool,
            .map_handle = map_handle,
            .guy = guy_rect,
            .fps = FpsCounter.init(),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.mapRenderer.deinit();
        self.tilemap_pool.release(self.map_handle);
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.inputs.keyboard.pressed(.escape)) return false;

        if (self.map_handle.dirty) {
            std.log.info("Tilemap handle dirty, re-acquiring and rebuilding renderer", .{});
            const new_handle = self.tilemap_pool.acquire() orelse {
                std.log.err("Failed to acquire reloaded tilemap handle", .{});
                return true;
            };
            self.tilemap_pool.release(self.map_handle);
            self.map_handle = new_handle;

            const layer = &self.map_handle.val.layers.items[1];
            self.camera.bounds = .{
                .l = 0,
                .t = 0,
                .r = @floatFromInt(layer.size.x * layer.tileSize.x),
                .b = @floatFromInt(layer.size.y * layer.tileSize.y),
            };

            self.mapRenderer.recreateVertices(
                &self.map_handle.val.tilesets.items[0],
                &self.map_handle.val.layers.items[1],
            ) catch |err| {
                std.log.err("Failed to rebuild tile renderer after hot reload: {}", .{err});
                return true;
            };
            std.log.info("Tilemap renderer rebuilt after hot reload", .{});
        }

        const MoveAmount = 3;
        if (eng.inputs.keyboard.down(.left)) {
            _ = pixzig.tile.Mover.moveLeft(
                &self.guy,
                MoveAmount,
                &self.map_handle.val.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.right)) {
            _ = pixzig.tile.Mover.moveRight(
                &self.guy,
                MoveAmount,
                &self.map_handle.val.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.up)) {
            _ = pixzig.tile.Mover.moveUp(
                &self.guy,
                MoveAmount,
                &self.map_handle.val.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.down)) {
            _ = pixzig.tile.Mover.moveDown(
                &self.guy,
                MoveAmount,
                &self.map_handle.val.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }

        self.camera.pos = self.guy.centerF();
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);

        self.fps.renderTick();
        const mvp = self.camera.matrix(&eng.viewport);
        try self.mapRenderer.draw(&self.map_handle.val.layers.items[1], mvp);

        // Draw outline.
        eng.renderer.begin(mvp);
        eng.renderer.drawRect(self.guy, Color.from(255, 255, 0, 200), 2);
        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Tilemap Example", .{});

    const appRunner = try AppRunner.init("Pixzig: Tilemap Example.", init.gpa, .{});

    std.log.info("Initializing app.", .{});
    const app: *App = try App.init(init.gpa, appRunner.engine);

    appRunner.run(app);
}
