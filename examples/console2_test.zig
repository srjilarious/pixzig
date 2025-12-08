const std = @import("std");
const builtin = @import("builtin");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
const zgui = pixzig.zgui;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Delay = pixzig.utils.Delay;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;

const scripting = pixzig.scripting;
const console = pixzig.console2;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{ .withGui = true });

pub const App = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    script: *scripting.ScriptEngine,
    cons: *console.Console,
    delay: Delay = .{ .max = 120 },

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app: *App = try alloc.create(App);

        // _ = eng;
        // _ = zgui.io.addFontFromFile(
        //     "assets/Roboto-Medium.ttf",
        //     std.math.floor(16.0 * eng.scaleFactor),
        // );

        const script = try alloc.create(scripting.ScriptEngine);
        script.* = try scripting.ScriptEngine.init(alloc);
        app.* = .{
            .alloc = alloc,
            .script = script,
            .cons = try console.Console.init(
                alloc,
                script,
                &eng.renderer.impl.text,
                &eng.renderer.impl.shapes,
                .{},
            ),
            .fps = FpsCounter.init(),
        };

        return app;
    }

    pub fn deinit(self: *App) void {
        std.log.info("Deiniting application.", .{});
        self.cons.deinit();

        self.script.deinit();
        self.alloc.destroy(self.script);

        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}\n", .{self.fps.fps()});
        }

        // std.log.debug("update: b\n",.{});
        eng.keyboard.update();

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.5, 0.4, 0.8, 1);

        // const fb_size = eng.window.getFramebufferSize();
        eng.renderer.begin(eng.projMat);
        self.cons.draw();
        eng.renderer.end();

        self.fps.renderTick();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Console Test Example", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig: Console Test Example.", alloc, .{});

    std.log.info("Initializing app.\n", .{});
    const app: *App = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
