// An example of generating a texture from a character buffer with a
// mapping from character to color.  Useful for simple game assets.
const std = @import("std");

const pixzig = @import("pixzig");
const RectF = pixzig.RectF;
const Color8 = pixzig.Color8;
const CharToColor = pixzig.textures.CharToColor;

pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.AppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    tex: *pixzig.TextureHandle,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const chars =
            \\=------=
            \\-..####-
            \\-.####=-
            \\-#####=-
            \\-#####=-
            \\-#####=-
            \\-##===@-
            \\=------=
        ;

        // Borrowed handle: the resource manager owns the texture.
        const tex = try eng.resources.createTextureImageFromChars("test", 8, 8, chars, &[_]CharToColor{
            .{ .char = '#', .color = Color8.from(40, 255, 40, 255) },
            .{ .char = '-', .color = Color8.from(100, 100, 200, 255) },
            .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
            .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
            .{ .char = '@', .color = Color8.from(30, 155, 30, 255) },
            .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
        });
        std.log.info("Created texture from characters.", .{});

        const app = try alloc.create(App);
        app.* = .{ .alloc = alloc, .tex = tex };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        _ = self;
        _ = delta;
        return !eng.inputs.keyboard.pressed(.escape);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 26, 255);
        eng.renderer.begin(.logical);
        const src = self.tex.val.src;
        eng.renderer.drawTexture(self.tex, RectF.fromPosSize(64, 64, 64, 64), src);
        eng.renderer.drawTexture(self.tex, RectF.fromPosSize(128, 64, 64, 64), src);
        eng.renderer.drawTexture(self.tex, RectF.fromPosSize(192, 64, 64, 64), src);
        eng.renderer.drawTexture(self.tex, RectF.fromPosSize(128, 128, 64, 64), src);
        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig: Create Texture Example.", init.gpa, .{});
    const app: *App = try App.init(init.gpa, appRunner.engine);
    appRunner.run(app);
}
