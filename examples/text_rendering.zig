// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const zmath = @import("zmath"); 
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import ("zstbi");
const pixzig = @import("pixzig");
const freetype = @import("freetype");

const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Vec2I = pixzig.common.Vec2I;

const GameStateMgr = pixzig.gamestate.GameStateMgr;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;
const PixzigEngine = pixzig.PixzigEngine;

const Renderer = pixzig.renderer.Renderer(.{.textRenderering =  true});

pub const MyApp = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    projMat: zmath.Mat,
    renderer: Renderer,
    // textRenderer: pixzig.renderer.TextRenderer,
    // colorShader: pixzig.shaders.Shader,
    // shapeBatch: pixzig.renderer.ShapeBatchQueue,
    //
    pub fn init(eng: *PixzigEngine, alloc: std.mem.Allocator) !MyApp {
        _ = eng;

        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        // const textRenderer = try pixzig.renderer.TextRenderer.init("assets/Roboto-Medium.ttf", alloc);
        
        const renderer = try Renderer.init(
                alloc, 
                .{ .fontFace = "assets/Roboto-Medium.ttf" }
            );
        // set texture options
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        // var colorShader = try pixzig.shaders.Shader.init(
        //         &pixzig.shaders.ColorVertexShader,
        //         &pixzig.shaders.ColorPixelShader
        //     );
        //
        // const shapeBatch = try pixzig.renderer.ShapeBatchQueue.init(alloc, &colorShader);
        
        return .{ 
            .fps = FpsCounter.init(),
            .alloc = alloc,
            .projMat = projMat,
            .renderer = renderer,
            // .textRenderer = textRenderer,
            // .colorShader = colorShader,
            // .shapeBatch = shapeBatch,
        };
    }

    pub fn deinit(self: *MyApp) void {
        self.renderer.deinit();
    }

    pub fn update(self: *MyApp, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();
        if(eng.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *MyApp, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        self.fps.renderTick();

        self.renderer.begin(self.projMat);
        // self.textRenderer.spriteBatch.drawSprite(&self.textRenderer.tex, 
            // RectF.fromPosSize(32, 32, 512, 512), .{ .l=0, .t=0, .r=1, .b=1});
        //
        const size = self.renderer.drawString("@!$() Hello World!", .{ .x = 20, .y = 320 });
        
        self.renderer.drawEnclosingRect(RectF.fromPosSize(20, 320, size.x, size.y), Color.from(100, 255, 100, 255), 2);
        
        // self.renderer.drawFilledRect(RectF.fromPosSize(20, 320, size.x, size.y), Color.from(255, 100, 100, 100));

        self.renderer.end();
    }
};



pub fn main() !void {

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Pixzig Text Rendering Test.", gpa, EngOptions{});
    defer eng.deinit();

    const AppRunner = pixzig.PixzigApp(MyApp);

    var app = try MyApp.init(&eng, gpa);

    eng.window.setInputMode(.cursor, .hidden);
    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
    app.deinit();
}


