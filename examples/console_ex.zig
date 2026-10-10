const std = @import("std");
const pixzig = @import("pixzig");

const FpsCounter = pixzig.utils.FpsCounter;

const imgui = pixzig.imgui;
const manifest_options = @import("manifest_options");
const AppRunner = pixzig.AppRunner(App, .{
    // The console reads typed characters through Keyboard.text(), which
    // needs the OS text-input machinery armed.
    .inputOpts = .{ .mouse = true, .textInput = true },
    .manifestOpts = manifest_options,
    // The engine owns the Lua state and the console bound to it
    // (`eng.scripts`, `eng.console`) and tears both down on shutdown.
    .scripting = true,
    .console = .{},
});
const UiContext = imgui.UiContext(AppRunner.Engine);

pub const App = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    ui: UiContext,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app: *App = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .ui = UiContext.init(eng),
            .fps = FpsCounter.init(),
        };
        app.ui.setClipboardWindow(eng.window);

        return app;
    }

    pub fn deinit(self: *App) void {
        std.log.info("Deiniting application.", .{});
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
        eng.renderer.clear(128, 102, 204, 255);

        eng.renderer.begin(.logical);
        self.ui.begin();
        eng.console.draw(&self.ui);
        self.ui.end();
        eng.renderer.end();

        self.fps.renderTick();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig: Console Test Example.", init.gpa, .{
        //.renderInitOpts = .{ .font = .{ .id = "Roboto-Medium" } },
    });
    defer appRunner.deinit();

    const app: *App = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
