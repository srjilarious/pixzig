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
    mapRenderer: tile.TileMapRenderer,
    guy: RectF,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        std.log.info("Loading tile map", .{});
        _ = try eng.resources.loadTileMap("level1a", "assets/level1a.tmx");

        // The renderer takes it from here: it holds the map, borrows the
        // texture shader, and loads the tileset image the .tmx names.
        std.log.info("Initializing map renderer.", .{});
        var mapRender = try tile.TileMapRenderer.init(alloc, &eng.resources, "level1a");
        errdefer mapRender.deinit();

        std.log.info("Done initializing map renderer.", .{});

        const guy_rect = RectF.fromPosSize(33, 33, 32, 32);
        var cam = pixzig.Camera2D.init();
        cam.pos = guy_rect.centerF();
        cam.bounds = layerBounds(mainLayer(&mapRender));

        const app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .camera = cam,
            .mapRenderer = mapRender,
            .guy = guy_rect,
            .fps = FpsCounter.init(),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.mapRenderer.deinit();
        self.alloc.destroy(self);
    }

    /// The layer the player walks on, looked up by the name it has in Tiled.
    fn mainLayer(mapRenderer: *tile.TileMapRenderer) *pixzig.TileLayer {
        return mapRenderer.tileMap().layerByName("main_layer").?;
    }

    fn layerBounds(layer: *const pixzig.TileLayer) RectF {
        return .{
            .l = 0,
            .t = 0,
            .r = @floatFromInt(layer.size.x * layer.tileSize.x),
            .b = @floatFromInt(layer.size.y * layer.tileSize.y),
        };
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.inputs.keyboard.pressed(.escape)) return false;

        // The renderer rebuilds itself on a hot-reload; all we have to do is
        // refresh what we derived from the map ourselves.
        if (self.mapRenderer.sync()) {
            std.log.info("Tilemap reloaded, refreshing camera bounds", .{});
            self.camera.bounds = layerBounds(mainLayer(&self.mapRenderer));
        }

        const MoveAmount = 3;
        if (eng.inputs.keyboard.down(.left)) {
            _ = pixzig.tile.Mover.moveLeft(
                &self.guy,
                MoveAmount,
                mainLayer(&self.mapRenderer),
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.right)) {
            _ = pixzig.tile.Mover.moveRight(
                &self.guy,
                MoveAmount,
                mainLayer(&self.mapRenderer),
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.up)) {
            _ = pixzig.tile.Mover.moveUp(
                &self.guy,
                MoveAmount,
                mainLayer(&self.mapRenderer),
                pixzig.tile.BlocksAll,
            );
        }
        if (eng.inputs.keyboard.down(.down)) {
            _ = pixzig.tile.Mover.moveDown(
                &self.guy,
                MoveAmount,
                mainLayer(&self.mapRenderer),
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
        self.mapRenderer.renderLayersBelow(1.0, &self.camera, &eng.viewport);

        eng.renderer.begin(.{ .camera = &self.camera });
        eng.renderer.drawRect(self.guy, Color.from(255, 255, 0, 200), 2);
        eng.renderer.end();

        self.mapRenderer.renderLayersAbove(1.0, &self.camera, &eng.viewport);
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig: Tilemap Example.", init.gpa, .{ .vsync = false });
    defer appRunner.deinit();

    const app: *App = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
