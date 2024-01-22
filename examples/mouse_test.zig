// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const zmath = @import("zmath"); 
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const GameStateMgr = pixzig.gamestate.GameStateMgr;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;
const PixzigEngine = pixzig.PixzigEngine;

pub const MyApp = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    projMat: zmath.Mat,
    mouse: pixzig.input.Mouse,
    spriteBatch: pixzig.renderer.SpriteBatchQueue,
    tex: *pixzig.Texture,
    pointer: pixzig.sprites.Sprite,
    texShader: pixzig.shaders.Shader,

    pub fn init(eng: *PixzigEngine, alloc: std.mem.Allocator) !MyApp {

        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        var texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader
        );

        const tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");
       
        const spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(alloc, &texShader);
        
        return .{ 
            .fps = FpsCounter.init(),
            .alloc = alloc,
            .projMat = projMat,
            .mouse = pixzig.input.Mouse.init(eng.window, eng.allocator),
            .spriteBatch = spriteBatch,
            .tex = tex,
            .pointer = pixzig.sprites.Sprite.create(tex, .{ .x = 32, .y = 32}, 
                RectF.fromCoords(32, 32, 32, 32, 512, 512)),
            .texShader = texShader,
        };
    }

    pub fn update(self: *MyApp, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();
        self.mouse.update();

        const mousePos = self.mouse.pos().asVec2I();
        self.pointer.setPos(mousePos.x, mousePos.y);

        if (self.mouse.pressed(.left)) {
            std.debug.print("left mouse!\n", .{});
        } 
        if (self.mouse.pressed(.right)) {
            std.debug.print("right mouse!\n", .{});
        }

        if(eng.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *MyApp, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        self.fps.renderTick();

        self.spriteBatch.begin(self.projMat);
        try self.pointer.draw(&self.spriteBatch);
        self.spriteBatch.end();
    }
};



pub fn main() !void {

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Glfw Eng Mouse Test.", gpa, EngOptions{});
    defer eng.deinit();

    const AppRunner = pixzig.PixzigApp(MyApp);

    var app = try MyApp.init(&eng, gpa);

    eng.window.setInputMode(.cursor, .hidden);
    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
}

