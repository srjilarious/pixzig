const std = @import("std");
const builtin = @import("builtin");

const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import("zstbi");
const zmath = @import("zmath");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const shaders = pixzig.shaders;
const Shader = shaders.Shader;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;

const Renderer = pixzig.renderer.Renderer(.{});
const GridRenderer = tile.GridRenderer;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

pub const App = struct {
    allocator: std.mem.Allocator,
    projMat: zmath.Mat,
    renderer: Renderer,
    fps: FpsCounter,
    grid: GridRenderer,

    pub fn init(eng: *pixzig.PixzigEngine, alloc: std.mem.Allocator) !App {
        _ = eng;
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const renderer = try Renderer.init(alloc, .{});

        const shader = try Shader.init(&shaders.ColorVertexShader, &shaders.ColorPixelShader);
        const grid = try GridRenderer.init(
            alloc,
            shader,
            .{ .x = 20, .y = 12 },
            .{ .x = 32, .y = 32 },
            1,
            Color{ .r = 1, .g = 0, .b = 1, .a = 1 },
        );
        return .{
            .allocator = alloc,
            .projMat = projMat,
            .renderer = renderer,
            .fps = FpsCounter.init(),
            .grid = grid,
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.grid.deinit();
    }

    pub fn update(self: *App, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) std.log.debug("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.log.debug("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.log.debug("three!\n", .{});

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *pixzig.PixzigEngine) void {
        _ = eng;

        gl.clearColor(0, 0, 0.2, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);

        self.fps.renderTick();

        try self.grid.draw(self.projMat);
    }
};

const AppRunner = pixzig.PixzigApp(App);
var g_AppRunner = AppRunner{};
var g_Eng: pixzig.PixzigEngine = undefined;
var g_App: App = undefined;

export fn mainLoop() void {
    _ = g_AppRunner.gameLoopCore(&g_App, &g_Eng);
}

pub fn main() !void {
    std.log.info("Pixzig Grid Render Example", .{});

    // var gpa_state = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
    // const gpa = gpa_state.allocator();

    const alloc = std.heap.c_allocator;
    g_Eng = try pixzig.PixzigEngine.init("Pixzig: Grid Render Example.", alloc, EngOptions{});
    std.log.info("Pixzig engine initialized..\n", .{});

    std.log.info("Initializing app.\n", .{});
    g_App = try App.init(&g_Eng, alloc);

    glfw.swapInterval(0);

    std.log.info("Starting main loop...\n", .{});
    if (builtin.target.os.tag == .emscripten) {
        pixzig.web.setMainLoop(mainLoop, null, false);
        std.log.debug("Set main loop.\n", .{});
    } else {
        g_AppRunner.gameLoop(&g_App, &g_Eng);
        std.log.info("Cleaning up...\n", .{});
        g_App.deinit();
        g_Eng.deinit();
    }
}
