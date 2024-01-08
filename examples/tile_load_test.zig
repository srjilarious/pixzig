// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
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

pub const App = struct {
    allocator: std.mem.Allocator,
    projMat: zmath.Mat,
    scrollOffset: Vec2F,
    mapRenderer: tile.TileMapRenderer,
    map: tile.TileMap,
    tex: *pixzig.Texture,
    texShader: pixzig.shaders.Shader,
    fps: FpsCounter,

    pub fn init(eng: *pixzig.PixzigEngine, alloc: std.mem.Allocator) !App {
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader
        );

        const tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");
        const map = try tile.TileMap.initFromFile("assets/level1a.tmx", alloc);

        const tData = map.layers.items[1].tile(0, 0);
        std.debug.print("Tile 0,0 data: {any}\n", .{tData});

        var mapRender = try tile.TileMapRenderer.init(std.heap.page_allocator, texShader);
    
        std.debug.print("Creating tile renderering data.\n", .{});
        try mapRender.recreateVertices(&map.tilesets.items[0], &map.layers.items[1]);

        std.debug.print("Done creating tile renderering data.\n", .{});

        return .{
            .allocator = alloc,
            .projMat = projMat,
            .scrollOffset = .{ .x = 0, .y = 0}, 
            .mapRenderer = mapRender,
            .map = map,
            .tex = tex,
            .texShader = texShader,
            .fps = FpsCounter.init() 
        };
    }

    pub fn deinit(self: *App) void {
        self.mapRenderer.deinit();
        self.map.deinit();
        self.texShader.deinit();
    }

    pub fn update(self: *App, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
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
        if(eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        self.fps.renderTick();
        const mvp = zmath.mul(zmath.translation(self.scrollOffset.x, self.scrollOffset.y, 0.0), self.projMat);
        try self.mapRenderer.draw(self.tex, &self.map.layers.items[0], mvp);
    }
};

pub fn main() !void {

    std.log.info("Pixzig Tilemap test!", .{});

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Pixzig: Tile Render Test.", gpa, EngOptions{});
    defer eng.deinit();

    const AppRunner = pixzig.PixzigApp(App);
    var app = try App.init(&eng, gpa);

    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
    app.deinit();
}

