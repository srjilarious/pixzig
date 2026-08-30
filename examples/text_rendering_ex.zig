const std = @import("std");
const pixzig = @import("pixzig");
const zmath = pixzig.zmath;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const manifest_options = @import("manifest_options");
const AppRunner = pixzig.PixzigAppRunner(App, .{
    .rendererOpts = .{ .textRendering = true },
    .manifestOpts = manifest_options,
});

const default_font_size: f32 = 20.0;

pub const App = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        _ = eng;
        const app = try alloc.create(App);

        app.* = .{
            .fps = FpsCounter.init(),
            .alloc = alloc,
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        std.log.info("Deiniting application..", .{});
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.inputs.keyboard.pressed(.escape)) {
            return false;
        }

        // Ctrl+- / Ctrl++ repack the default font atlas at a new pixel size;
        // Ctrl+0 restores the startup size. `+` is Shift+`=` on most
        // layouts, so `.equal` is accepted directly, plus the numpad keys.
        // The engine takes an absolute size and applies it as-is -- the
        // min/max range and the 2px step are this app's policy.
        const kb = &eng.inputs.keyboard;
        if (kb.ctrl()) {
            if (eng.defaultFontAtlas()) |fa| {
                const min_pt: f32 = 8;
                const max_pt: f32 = 72;
                const target: ?f32 = if (kb.pressed(.minus) or kb.pressed(.kp_subtract))
                    std.math.clamp(fa.font_size - 2, min_pt, max_pt)
                else if (kb.pressed(.equal) or kb.pressed(.kp_add))
                    std.math.clamp(fa.font_size + 2, min_pt, max_pt)
                else if (kb.pressed(.zero) or kb.pressed(.kp_0))
                    default_font_size
                else
                    null;
                if (target) |pt| fa.setFontSize(pt) catch |err| {
                    std.log.warn("font resize failed: {}", .{err});
                };
            }
        }

        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.0, 0.0, 0.2, 1.0);
        self.fps.renderTick();

        eng.renderer.begin(eng.projMat);

        var buf: [80]u8 = undefined;
        const pt = if (eng.defaultFontAtlas()) |fa| fa.font_size else 0;
        const hud = std.fmt.bufPrint(&buf, "Ctrl+- / Ctrl++ : font size {d:.0}px  (Ctrl+0 resets)", .{pt}) catch "";
        _ = eng.renderer.drawString(hud, .{ .x = 20, .y = 360 });

        const size = eng.renderer.drawString("@!$() Hello World!", .{ .x = 20, .y = 320 });

        eng.renderer.drawEnclosingRect(RectF.fromPosSize(20, 320, size.x, size.y), Color.from(100, 255, 100, 255), 2);

        _ = eng.renderer.drawScaledString("Scaled 2x!", .{ .x = 20, .y = 280 }, 2.0);
        _ = eng.renderer.drawScaledString("Scaled 0.5x!", .{ .x = 20, .y = 50 }, 0.5);

        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Test Rendering Example", .{});
    // A path-based default font (rather than a manifest `id`) so this demo
    // owns the file the atlas is repacked from at runtime.
    const appRunner = try AppRunner.init("Pixzig Text Rendering Example.", init.gpa, .{
        .renderInitOpts = .{ .font = .{ .path = .{
            .face = "assets/Roboto-Medium.ttf",
            .size = default_font_size,
        } } },
    });
    const app = try App.init(init.gpa, appRunner.engine);

    appRunner.run(app);
}
