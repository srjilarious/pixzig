const std = @import("std");
const pixzig = @import("pixzig");

const FpsCounter = pixzig.utils.FpsCounter;

const imgui = pixzig.imgui;
const manifest_options = @import("manifest_options");
// Game controls go through the engine action map. While the console is
// open the engine suppresses it, so typing a space in the console doesn't
// flash the background.
const Action = enum { flash };

const AppRunner = pixzig.AppRunner(App, .{
    // The console reads typed characters through Keyboard.text(), which
    // needs the OS text-input machinery armed.
    .inputOpts = .{ .mouse = true, .textInput = true },
    .manifestOpts = manifest_options,
    // The engine owns the Lua state and the console bound to it
    // (`eng.scripts`, `eng.console`) and tears both down on shutdown.
    .scripting = true,
    .console = .{},
    .actionOpts = .{ .Action = Action },
});
const UiContext = imgui.UiContext(AppRunner.Engine);

pub const App = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    ui: UiContext,
    flashMs: f64,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        try eng.actions.bind(.flash, .{ .key = .space });

        const app: *App = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .ui = UiContext.init(eng),
            .fps = FpsCounter.init(),
            .flashMs = 0,
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

        // Quitting and the console toggle read the keyboard directly: the
        // action map is suppressed while the console is open, so an action
        // couldn't close it.
        if (eng.inputs.keyboard.pressed(.escape)) {
            return false;
        }
        if (eng.inputs.keyboard.pressed(.F1)) eng.console.toggle();

        if (eng.actions.pressed(.flash)) self.flashMs = 150;
        self.flashMs = @max(0, self.flashMs - delta);

        self.ui.update();
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        if (self.flashMs > 0) {
            eng.renderer.clear(230, 220, 255, 255);
        } else {
            eng.renderer.clear(128, 102, 204, 255);
        }

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
