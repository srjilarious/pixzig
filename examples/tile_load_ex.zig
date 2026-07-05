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
    mapRenderer: tile.ChunkedTiledRenderer,
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

        std.log.info("Initializing map renderer.", .{});
        const shader_pool = eng.resources.shaders.get(pixzig.shaders.TextureShader) orelse return error.NoShaderWithThatName;
        const texture_pool = eng.resources.atlas.get("tiles") orelse return error.NoTextureWithThatName;
        const mapRender = try tile.ChunkedTiledRenderer.init(alloc, &map_handle.val, shader_pool, texture_pool);

        std.log.info("Done initializing map renderer.", .{});

        const guy_rect = RectF.fromPosSize(33, 33, 32, 32);
        var cam = pixzig.Camera2D.init(eng.viewport.logical_size);
        cam.pos = guy_rect.centerF();
        const main_layer = &map_handle.val.layers.items[1];
        cam.bounds = .{
            .l = 0,
            .t = 0,
            .r = @floatFromInt(main_layer.size.x * main_layer.tileSize.x),
            .b = @floatFromInt(main_layer.size.y * main_layer.tileSize.y),
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
            std.log.info("Tilemap handle dirty, re-acquiring and marking renderer dirty", .{});
            const new_handle = self.tilemap_pool.acquire() orelse {
                std.log.err("Failed to acquire reloaded tilemap handle", .{});
                return true;
            };
            self.tilemap_pool.release(self.map_handle);
            self.map_handle = new_handle;

            const main_layer = &self.map_handle.val.layers.items[1];
            self.camera.bounds = .{
                .l = 0,
                .t = 0,
                .r = @floatFromInt(main_layer.size.x * main_layer.tileSize.x),
                .b = @floatFromInt(main_layer.size.y * main_layer.tileSize.y),
            };

            self.mapRenderer.rebuildAll(&self.map_handle.val);
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

        // Render tile layers below z=1 (background + main layer at z=0),
        // then game objects, then foreground layers at z>=1.
        // Set a `z` float property on a layer in Tiled to control ordering.
        self.mapRenderer.renderLayersBelow(1.0, &self.map_handle.val, &self.camera, &eng.viewport);

        const mvp = self.camera.matrix(&eng.viewport);
        eng.renderer.begin(mvp);
        eng.renderer.drawRect(self.guy, Color.from(255, 255, 0, 200), 2);
        eng.renderer.end();

        self.mapRenderer.renderLayersAbove(1.0, &self.map_handle.val, &self.camera, &eng.viewport);
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Tilemap Example", .{});

    const appRunner = try AppRunner.init("Pixzig: Tilemap Example.", init.gpa, .{});

    std.log.info("Initializing app.", .{});
    const app: *App = try App.init(init.gpa, appRunner.engine);

    appRunner.run(app);
}
