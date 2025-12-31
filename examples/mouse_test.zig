// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
// const zgui = @import("zgui");
const zmath = @import("zmath"); 
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
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

pub const App = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    mouse: pixzig.input.Mouse,
    spriteBatch: pixzig.renderer.SpriteBatchQueue,
    tex: *pixzig.Texture,
    pointer: pixzig.sprites.Sprite,
    texShader: pixzig.shaders.Shader,

    pub fn init(eng: *PixzigEngine, alloc: std.mem.Allocator) !App {
        var texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader
        );

        const bigtex = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
       
        const tex = try eng.resources.addSubTexture(bigtex, "guy", RectF.fromCoords(32, 32, 32, 32, 512, 512));

        const spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(alloc, &texShader);
        
        return .{ 
            .fps = FpsCounter.init(),
            .alloc = alloc,
            .mouse = pixzig.input.Mouse.init(eng.window, eng.allocator),
            .spriteBatch = spriteBatch,
            .tex = tex,
            .pointer = pixzig.sprites.Sprite.create(tex, .{ .x = 32, .y = 32}),
            .texShader = texShader,
        };
    }

    pub fn update(self: *App, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

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

    pub fn render(self: *App, eng: *pixzig.PixzigEngine) void {
        eng.clear(.{ 0, 0, 0.2, 1 });
        self.fps.renderTick();

        self.spriteBatch.begin(eng.projMat);
        self.spriteBatch.drawSprite(&self.pointer);
        self.spriteBatch.end();
    }
};


const AppRunner =  pixzig.PixzigApp(App);
var g_AppRunner = AppRunner{};
var g_Eng: pixzig.PixzigEngine = undefined;
var g_App: App = undefined;

export fn mainLoop() void {
    _ = g_AppRunner.gameLoopCore(&g_App, &g_Eng);
}

pub fn main() !void {

    std.log.info("Pixzig Mouse test!", .{});

    // var gpa_state = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
    // const gpa = gpa_state.allocator();

    g_Eng = try pixzig.PixzigEngine.init("Pixzig: Mouse Test.", std.heap.c_allocator, EngOptions{});
    std.log.info("Pixzig engine initialized..\n", .{});

    std.debug.print("Initializing app.\n", .{});
    g_App = try App.init(&g_Eng, std.heap.c_allocator);

    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    if(builtin.target.os.tag == .emscripten) {
        pixzig.web.setMainLoop(mainLoop, null, false);
        std.log.debug("Set main loop.\n", .{});
    }
    else {
        g_AppRunner.gameLoop(&g_App, &g_Eng);
        std.log.info("Cleaning up...\n", .{});
        // g_App.deinit();
        g_Eng.deinit();
        // _ = gpa_state.deinit();
    }
}


