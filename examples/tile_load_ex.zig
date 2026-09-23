const std = @import("std");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const Color = pixzig.common.Color;

const tile = pixzig.tile;
const FpsCounter = pixzig.utils.FpsCounter;
const AppRunner = pixzig.AppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    camera: pixzig.Camera2D,
    mapRenderer: tile.ChunkedTiledRenderer,
    guy: RectF,
    map: *pixzig.TileMapHandle,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        _ = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");

        std.log.info("Loading tile map", .{});
        _ = try eng.resources.loadTileMap("level1a", "assets/level1a.tmx");
        const map = try eng.resources.acquireTileMap("level1a");

        std.log.info("Initializing map renderer.", .{});
        const shader = try eng.resources.getShader(pixzig.shaders.TextureShader);
        const texture = try eng.resources.getTexture("tiles");
        const mapRender = try tile.ChunkedTiledRenderer.init(alloc, &map.val, shader, texture);

        std.log.info("Done initializing map renderer.", .{});

        const guy_rect = RectF.fromPosSize(33, 33, 32, 32);
        var cam = pixzig.Camera2D.init(eng.viewport.logicalSize);
        cam.pos = guy_rect.centerF();
        const main_layer = &map.val.layers.items[1];
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
            .map = map,
            .guy = guy_rect,
            .fps = FpsCounter.init(),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.mapRenderer.deinit();
        self.map.release();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.inputs.keyboard.pressed(.escape)) return false;

        if (self.map.dirty) {
            std.log.info("Tilemap handle dirty, re-acquiring and marking renderer dirty", .{});
            self.map = self.map.reacquire();

            const main_layer = &self.map.val.layers.items[1];
            self.camera.bounds = .{
                .l = 0,
                .t = 0,
                .r = @floatFromInt(main_layer.size.x * main_layer.tileSize.x),
                .b = @floatFromInt(main_layer.size.y * main_layer.tileSize.y),
            };

            self.mapRenderer.reload(&self.map.val) catch |err| {
                std.log.err("Failed to reload map renderer: {}", .{err});
                return true;
            };
            std.log.info("Tilemap renderer reloaded after hot reload", .{});
        }

        const MoveAmount = 3;
        if (eng.inputs.keyboard.down(.left)) {
            _ = pixzig.tile.Mover.moveLeft(
                &self.guy,
                MoveAmount,
                &self.map.val.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.right)) {
            _ = pixzig.tile.Mover.moveRight(
                &self.guy,
                MoveAmount,
                &self.map.val.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.up)) {
            _ = pixzig.tile.Mover.moveUp(
                &self.guy,
                MoveAmount,
                &self.map.val.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.down)) {
            _ = pixzig.tile.Mover.moveDown(
                &self.guy,
                MoveAmount,
                &self.map.val.layers.items[1],
                pixzig.tile.BlocksAll,
            );
        }

        self.camera.pos = self.guy.centerF();
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 51, 255);

        self.fps.renderTick();

        // Render tile layers below z=1 (background + main layer at z=0),
        // then game objects, then foreground layers at z>=1.
        // Set a `z` float property on a layer in Tiled to control ordering.
        self.mapRenderer.renderLayersBelow(1.0, &self.map.val, &self.camera, &eng.viewport);

        eng.renderer.begin(.{ .camera = &self.camera });
        eng.renderer.drawRect(self.guy, Color.from(255, 255, 0, 200), 2);
        eng.renderer.end();

        self.mapRenderer.renderLayersAbove(1.0, &self.map.val, &self.camera, &eng.viewport);
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig: Tilemap Example.", init.gpa, .{ .vsync = false });
    defer appRunner.deinit();

    const app: *App = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
