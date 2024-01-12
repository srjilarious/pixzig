// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
const zmath = @import("zmath"); 
const flecs = @import("zflecs"); 
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
    spriteBatch: pixzig.renderer.SpriteBatchQueue,
    shapeBatch: pixzig.renderer.ShapeBatchQueue,
    tex: *pixzig.Texture,
    texShader: pixzig.shaders.Shader,
    colorShader: pixzig.shaders.Shader,
    fps: FpsCounter,

    dest: [3]RectF,
    srcCoords: [3]RectF,
    destRects: [3]RectF,
    colorRects: [3]Color,

    pub fn init(eng: *pixzig.PixzigEngine, alloc: std.mem.Allocator) !App {
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        var texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader
        );

        const tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");
       
        const spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(alloc, &texShader);

        var colorShader = try pixzig.shaders.Shader.init(
                &pixzig.shaders.ColorVertexShader,
                &pixzig.shaders.ColorPixelShader
            );

        const shapeBatch = try pixzig.renderer.ShapeBatchQueue.init(alloc, &colorShader);
        std.debug.print("Done creating tile renderering data.\n", .{});

        return .{
            .allocator = alloc,
            .projMat = projMat,
            .scrollOffset = .{ .x = 0, .y = 0}, 
            .spriteBatch = spriteBatch,
            .shapeBatch = shapeBatch,
            .tex = tex,
            .texShader = texShader,
            .colorShader = colorShader,
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
    }

    pub fn deinit(self: *App) void {
        self.spriteBatch.deinit();
        self.shapeBatch.deinit();
        self.colorShader.deinit();
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
       
        self.spriteBatch.begin(self.projMat);
        
        for(0..3) |idx| {
            self.spriteBatch.drawSprite(self.tex, self.dest[idx], self.srcCoords[idx]);
        }
        self.spriteBatch.end();
        
        self.shapeBatch.begin(self.projMat);
        
        // Draw sprite outlines.
        for(0..3) |idx| {
            self.shapeBatch.drawRect(self.dest[idx], Color.from(255,255,0,200), 2);
        }
        for(0..3) |idx| {
            self.shapeBatch.drawEnclosingRect(self.dest[idx], Color.from(255,0,255,200), 2);
        }
        for(0..3) |idx| {
            self.shapeBatch.drawFilledRect(self.destRects[idx], self.colorRects[idx]);
        }
        self.shapeBatch.end();
 
    }
};

pub fn main() !void {

    std.log.info("Pixzig Flecs test!", .{});

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Pixzig: Flecs Test.", gpa, EngOptions{});
    defer eng.deinit();

    const AppRunner = pixzig.PixzigApp(App);
    var app = try App.init(&eng, gpa);

    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
    app.deinit();
}





    // gl.enable(gl.BLEND);
    // gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    // gl.enable(gl.TEXTURE_2D);


