// DigCraft - A 2d Minecraft-inspired game.

// TODO list:
// - world seeding
// - world simulation steps
// -

const std = @import("std");
const builtin = @import("builtin");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import("zstbi");
const zmath = @import("zmath");
const pixzig = @import("pixzig");
const flecs = @import("zflecs");

const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const shaders = pixzig.shaders;
const Shader = shaders.Shader;
const Sprite = pixzig.sprites.Sprite;
const ScriptEngine = pixzig.scripting.ScriptEngine;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const Vec2U = pixzig.common.Vec2U;
const FpsCounter = pixzig.utils.FpsCounter;

const Renderer = pixzig.renderer.Renderer(.{});
const GridRenderer = tile.GridRenderer;
const CharToColor = pixzig.textures.CharToColor;
const Color8 = pixzig.Color8;
const Texture = pixzig.textures.Texture;

const entities = @import("./entities.zig");
const Player = entities.Player;
const Mover = entities.Mover;

const C = @import("./constants.zig");

const Gravity = @import("systems/gravity.zig").Gravity;
const PlayerControl = @import("systems/player_control.zig").PlayerControl;
const CameraSystem = @import("systems/camera.zig").CameraSystem;
const Outlines = @import("systems/outlines.zig").Outlines;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

pub const DigcraftConfig = struct {
    fullscreen: bool = false,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    projMat: zmath.Mat,
    renderer: Renderer,
    fps: FpsCounter,
    mouse: *pixzig.input.Mouse,
    tex: *Texture,
    map: tile.TileMap,
    mapRenderer: tile.TileMapRenderer,
    texShader: pixzig.shaders.Shader,
    scripts: *ScriptEngine,
    world: *flecs.world_t,
    draw_query: *flecs.query_t,
    cursor_draw_query: *flecs.query_t,
    gravity: Gravity = undefined,
    playerControl: PlayerControl = undefined,
    cameras: CameraSystem = undefined,
    outlines: Outlines = undefined,

    pub fn init(eng: *pixzig.PixzigEngine, scripts: *ScriptEngine, alloc: std.mem.Allocator) !App {
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const renderer = try Renderer.init(alloc, .{});

        const atlasName = "assets/digcraft_sprites";
        const numSprites = try eng.textures.loadAtlas(atlasName);
        std.debug.print("Loaded {} sprites from '{s}' atlas", .{ numSprites, atlasName });
        const tex = eng.textures.getTexture("digcraft_sprites") catch unreachable;

        // Create base map and renderer
        const texShader = try pixzig.shaders.Shader.init(&pixzig.shaders.TexVertexShader, &pixzig.shaders.TexPixelShader);

        var map = try tile.TileMap.init(alloc);
        const tileset = try tile.TileSet.initEmpty(alloc, .{ .x = C.TileWidth, .y = C.TileHeight }, .{ .x = @intCast(tex.size.x), .y = @intCast(tex.size.y) }, C.NumTilesHorz * C.NumTilesVert);
        const layer = try tile.TileLayer.initEmpty(alloc, .{ .x = C.MapWidth, .y = C.MapHeight }, .{ .x = C.TileWidth, .y = C.TileHeight });
        try map.layers.append(layer);
        try map.tilesets.append(tileset);
        map.layers.items[0].tileset = &map.tilesets.items[0];

        var mapRender = try tile.TileMapRenderer.init(alloc, texShader);

        // Create some tiles for the tile set
        const DirtIdx = 0;
        const GrassIdx = 1;
        const StoneIdx = 2;
        map.tilesets.items[0].tile(DirtIdx).?.* = .{ .core = tile.BlocksAll, .properties = null, .alloc = alloc };
        map.tilesets.items[0].tile(GrassIdx).?.* = .{ .core = tile.BlocksAll, .properties = null, .alloc = alloc };
        map.tilesets.items[0].tile(StoneIdx).?.* = .{ .core = tile.BlocksAll, .properties = null, .alloc = alloc };

        // Generate a bunch of random blocks
        var prng = std.Random.DefaultPrng.init(0xdeadbeef);
        const rand = prng.random();
        for (0..200) |_| {
            const idx = rand.uintAtMost(usize, C.MapWidth * C.MapHeight);
            map.layers.items[0].tiles.items[idx] = rand.intRangeAtMost(i32, 0, 2);
        }

        // Draw a row on the entire bottom of the map.
        for (0..C.MapWidth) |idx| {
            map.layers.items[0].tiles.items[(C.MapHeight - 1) * C.MapWidth + idx] = GrassIdx;
        }

        try mapRender.recreateVertices(&map.tilesets.items[0], &map.layers.items[0]);

        // Setup world and entities
        const world = flecs.init();
        entities.setupEntities(world);

        const draw_query = try flecs.query_init(world, &.{
            .terms = [_]flecs.term_t{
                .{ .id = flecs.id(Sprite) },
            } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX - 1),
        });

        const cursor_draw_query = try flecs.query_init(world, &.{
            .terms = [_]flecs.term_t{
                .{ .id = flecs.id(entities.HumanController) },
            } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX - 1),
        });

        const playerTex = eng.textures.getTexture("remi") catch unreachable;
        const playerId = entities.spawn(world, .Player, playerTex, 8);

        map.layers.items[0].dumpLayer();

        const mouse = try alloc.create(pixzig.input.Mouse);
        mouse.* = pixzig.input.Mouse.init(eng.window, eng.allocator);
        // Create application.
        var app = App{
            .allocator = alloc,
            .projMat = projMat,
            // .scrollOffset = .{ .x = 0, .y = 0},
            .renderer = renderer,
            .fps = FpsCounter.init(),
            .mouse = mouse,
            .tex = tex,
            .texShader = texShader,
            .map = map,
            .mapRenderer = mapRender,
            .scripts = scripts,
            .world = world,
            .draw_query = draw_query,
            .cursor_draw_query = cursor_draw_query,
        };

        app.gravity = try Gravity.init(world);

        app.cameras = try CameraSystem.init(world, eng, projMat);
        var mainCamera = flecs.get_mut(world, app.cameras.currCamera.?, entities.Camera).?;
        mainCamera.tracked = playerId;

        app.playerControl = try PlayerControl.init(world, eng, app.mouse, app.cameras.currCamera.?);
        app.outlines = try Outlines.init(alloc, world, eng);
        return app;
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.map.deinit();
        self.mapRenderer.deinit();
        self.texShader.deinit();
        self.gravity.deinit();
        self.playerControl.deinit();
        self.outlines.deinit();
        self.allocator.destroy(self.mouse);
        flecs.query_fini(self.draw_query);
        flecs.query_fini(self.cursor_draw_query);
        _ = flecs.fini(self.world);
    }

    pub fn update(self: *App, eng: *pixzig.PixzigEngine, delta: f64) bool {
        //_ = delta;
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();
        self.mouse.update();

        const mapLayer = &self.map.layers.items[0];
        self.gravity.update(mapLayer);
        self.playerControl.update(mapLayer, &self.mapRenderer) catch unreachable;
        self.outlines.update();

        self.cameras.update();

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *App, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        self.fps.renderTick();

        const mvp = self.cameras.currCameraMat();
        try self.mapRenderer.draw(self.tex, &self.map.layers.items[0], mvp);

        try self.outlines.drawMapGrid(mvp);
        self.renderer.begin(mvp);

        var it = flecs.query_iter(self.world, self.draw_query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 0).?;
            for (0..it.count()) |idx| {
                self.renderer.drawSprite(&spr[idx]);
            }
        }

        var cit = flecs.query_iter(self.world, self.cursor_draw_query);
        while (flecs.query_next(&cit)) {
            const humCtrls = flecs.field(&cit, entities.HumanController, 0).?;
            for (0..it.count()) |idx| {
                const hum = &humCtrls[idx];
                self.renderer.drawEnclosingRect(hum.cursorLoc, hum.cursorColor, 1);
            }
        }

        try self.outlines.drawSpriteOutlines(&self.renderer);

        self.renderer.end();
    }
};

const AppRunner = pixzig.PixzigApp(App);
var g_AppRunner = AppRunner{};
var g_Eng: pixzig.PixzigEngine = undefined;
var g_App: App = undefined;
var g_ScriptEng: ScriptEngine = undefined;

export fn mainLoop() void {
    _ = g_AppRunner.gameLoopCore(&g_App, &g_Eng);
}

pub fn main() !void {
    std.log.info("Pixzig - DigCraft", .{});

    // var gpa_state = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
    // const gpa = gpa_state.allocator();

    const alloc = std.heap.c_allocator;

    // Load our config file.
    g_ScriptEng = try ScriptEngine.init(alloc);

    try g_ScriptEng.runScript("assets/digconf.lua");
    const conf = try g_ScriptEng.loadStruct(DigcraftConfig, "config");

    g_Eng = try pixzig.PixzigEngine.init(
        "Pixzig: DigCraft",
        alloc,
        EngOptions{ .fullscreen = conf.fullscreen },
    );
    std.log.info("Pixzig engine initialized..\n", .{});

    std.debug.print("Initializing app.\n", .{});
    g_App = try App.init(&g_Eng, &g_ScriptEng, alloc);

    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    if (builtin.target.os.tag == .emscripten) {
        pixzig.web.setMainLoop(mainLoop, null, false);
        std.log.debug("Set main loop.\n", .{});
    } else {
        g_AppRunner.gameLoop(&g_App, &g_Eng);
        std.log.info("Cleaning up...\n", .{});
        g_App.deinit();
        g_Eng.deinit();
        g_ScriptEng.deinit();
    }
}

// pub fn main() !void {

//     std.log.info("Pixzig - DigCraft", .{});

//     var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa_state.deinit();
//     const gpa = gpa_state.allocator();

//     var scripts = try ScriptEngine.init(gpa);
//     defer scripts.deinit();

//     try scripts.runScript("assets/digconf.lua");
//     const conf = try scripts.loadStruct(DigcraftConfig, "config");

//     var eng = try pixzig.PixzigEngine.init(
//         "Pixzig: DigCraft", gpa,
//         EngOptions{ .fullscreen = conf.fullscreen });
//     defer eng.deinit();

//     const AppRunner = pixzig.PixzigApp(App);
//     var app = try App.init(&eng, &scripts, gpa);

//     glfw.swapInterval(0);

//     std.debug.print("Starting main loop...\n", .{});
//     AppRunner.gameLoop(&app, &eng);

//     std.debug.print("Cleaning up...\n", .{});
//     app.deinit();
// }
