const std = @import("std");
const pixzig = @import("pixzig");
const Delay = pixzig.utils.Delay;

const FpsCounter = pixzig.utils.FpsCounter;

const imgui = pixzig.imgui;
const scripting = pixzig.scripting;
const console = pixzig.console;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{
    .rendererOpts = .{
        .textRendering = true,
    },
    .inputOpts = .{ .mouse = true },
});

pub const App = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    script: *scripting.ScriptEngine,
    cons: *console.Console,
    ui: imgui.UiContext,
    delay: Delay = .{ .max = 120 },

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app: *App = try alloc.create(App);

        const script = try alloc.create(scripting.ScriptEngine);
        script.* = try scripting.ScriptEngine.init(alloc);
        const console_size = eng.viewport.logical_size.asVec2U();
        app.* = .{
            .alloc = alloc,
            .script = script,
            .cons = try console.Console.init(
                alloc,
                script,
                .{ .displaySize = console_size },
            ),
            .ui = imgui.UiContext.init(
                &eng.inputs.mouse,
                &eng.inputs.keyboard,
                &eng.viewport,
                &eng.renderer.impl.batches[0],
                &eng.renderer.impl.overlays,
                &eng.renderer.impl.shapes,
                &eng.renderer.impl.text,
            ),
            .fps = FpsCounter.init(),
        };
        app.ui.setClipboardWindow(eng.window);

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
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.inputs.keyboard.pressed(.escape)) {
            return false;
        }

        self.ui.update();
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.5, 0.4, 0.8, 1);

        eng.renderer.begin(eng.projMat);
        self.ui.begin();
        self.cons.draw(&self.ui);
        self.ui.end();
        eng.renderer.end();

        self.fps.renderTick();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Console Test Example", .{});

    const appRunner = try AppRunner.init("Pixzig: Console Test Example.", init.gpa, .{ .renderInitOpts = .{
        .fontFace = "assets/Roboto-Medium.ttf",
    } });

    std.log.info("Initializing app.\n", .{});
    const app: *App = try App.init(init.gpa, appRunner.engine);

    appRunner.run(app);
}
