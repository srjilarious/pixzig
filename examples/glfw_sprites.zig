// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
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

const Renderer = pixzig.renderer.Renderer(.{});

// pub const panic = pixzig.web.panic;
// pub const std_options = std.Options{
//     .logFn = pixzig.web.log,
// };

pub const App = struct {
    allocator: std.mem.Allocator,
    projMat: zmath.Mat,
    scrollOffset: Vec2F,
    tex: *pixzig.Texture,
    renderer: Renderer,
    fps: FpsCounter,

    dest: [3]RectF,
    srcCoords: [3]RectF,
    destRects: [3]RectF,
    colorRects: [3]Color,

    pub fn init(eng: *pixzig.PixzigEngine, alloc: std.mem.Allocator) !App {
        std.log.info("GLFW Sprites init w/ vendored lua!!", .{});
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const tst = try alloc.alloc(u8, 100);
        @memset(tst, 123);
        std.log.info("filled buffer", .{});

        std.log.debug("Loading texture...\n", .{});
        const tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");

        std.log.debug("Creating renderer.\n", .{});
        const renderer = try Renderer.init(alloc, .{});

        return .{
            .allocator = alloc,
            .projMat = projMat,
            .scrollOffset = .{ .x = 0, .y = 0}, 
            .tex = tex,
            .renderer = renderer,
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
        self.renderer.deinit();
    }

    pub fn update(self: *App, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.log.debug("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) std.log.info("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.log.info("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.log.info("three!\n", .{});
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
        // gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        gl.clearColor(0, 0, 0.2, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);
        self.fps.renderTick();
       
        self.renderer.begin(self.projMat);
        
        for(0..3) |idx| {
            self.renderer.draw(self.tex, self.dest[idx], self.srcCoords[idx]);
        }
        
        
        // Draw sprite outlines.
        for(0..3) |idx| {
            self.renderer.drawRect(self.dest[idx], Color.from(255,255,0,200), 2);
        }
        for(0..3) |idx| {
            self.renderer.drawEnclosingRect(self.dest[idx], Color.from(255,0,255,200), 2);
        }
        for(0..3) |idx| {
            self.renderer.drawFilledRect(self.destRects[idx], self.colorRects[idx]);
        }

        self.renderer.end();
 
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

    std.log.info("Pixzig Sprite and Shape test!", .{});

    // var gpa_state = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
    // const gpa = gpa_state.allocator();

    g_Eng = try pixzig.PixzigEngine.init("Pixzig: Tile Render Test.", std.heap.c_allocator, EngOptions{});
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
        g_App.deinit();
        g_Eng.deinit();
        // _ = gpa_state.deinit();
    }
}

