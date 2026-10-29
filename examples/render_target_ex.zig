//* Draws a scene into a small `RenderTarget`, then draws that target
//* scaled up to fill the screen through a custom shader, the usual shape
//* of a low-resolution game with a post-processing pass.
//*
//* - The scene is three overlapping squares drawn with additive blending,
//*   so where they cross the colors add up to white.
//* - The target is a quarter of the logical size and uses nearest
//*   filtering, so scaling it up keeps hard pixel edges.
//* - The scaled-up frame goes through a wave shader whose `time` uniform
//*   is set every frame.
//* - Space flashes the screen white with `fade`.
//*
//* Keys: 1 toggles the shader, 2 toggles additive blending, Space flashes,
//* Escape quits.

//* -- collapsed: Imports --
const std = @import("std");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const Color = pixzig.common.Color;
//* ---

const AppRunner = pixzig.AppRunner(App, .{
    .screenshotHook = true,
});

//* The fragment shader gets the batch's usual inputs (see
//* `Renderer.createShader`) plus our own `time`. It shifts each row of the
//* image sideways by a sine wave.
const wave_shader: [*:0]const u8 =
    \\#version 300 es
    \\precision mediump float;
    \\in vec2 Texcoord;
    \\in vec4 Col;
    \\flat in float Mode;
    \\uniform sampler2D tex;
    \\uniform float time;
    \\out vec4 fragColor;
    \\void main() {
    \\    vec2 uv = Texcoord;
    \\    uv.x += sin(uv.y * 24.0 + time * 3.0) * 0.006;
    \\    fragColor = texture(tex, uv) * Col;
    \\}
;

const flash_ms: f64 = 400;

pub const App = struct {
    alloc: std.mem.Allocator,
    target: pixzig.RenderTarget,
    wave: *pixzig.resources.ShaderHandle,
    elapsedMs: f64 = 0,
    flashLeftMs: f64 = 0,
    useShader: bool = true,
    additive: bool = true,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);
        errdefer alloc.destroy(app);

        //* A quarter of the logical screen in each direction.
        const logical = eng.viewport.logicalSize;
        var target = try pixzig.RenderTarget.init(.{
            .x = @intCast(@divTrunc(logical.x, 4)),
            .y = @intCast(@divTrunc(logical.y, 4)),
        }, .{ .filter = .nearest });
        errdefer target.deinit();

        app.* = .{
            .alloc = alloc,
            .target = target,
            .wave = try eng.renderer.createShader(&eng.resources, "wave", wave_shader),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.target.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) void {
        self.elapsedMs += delta;
        self.flashLeftMs = @max(0, self.flashLeftMs - delta);

        const kb = &eng.inputs.keyboard;
        if (kb.pressed(.escape)) eng.quit();
        if (kb.pressed(.one)) self.useShader = !self.useShader;
        if (kb.pressed(.two)) self.additive = !self.additive;
        if (kb.pressed(.space)) self.flashLeftMs = flash_ms;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine, alpha: f32) void {
        _ = alpha;
        const r = &eng.renderer;
        const t: f32 = @floatCast(self.elapsedMs / 1000.0);

        //* Pass 1: the scene, into the target. A `.logical` pass inside a
        //* target stretches the logical screen over it, so the scene is
        //* drawn in the same coordinates as everything else.
        r.setTarget(&self.target);
        r.begin(.logical);
        r.clear(10, 10, 30, 255);
        if (self.additive) r.setBlend(.additive);
        const colors = [_]Color{ Color.red, Color.green, Color.blue };
        for (colors, 0..) |c, i| {
            const phase = t + @as(f32, @floatFromInt(i)) * 2.1;
            const x = 400 + @cos(phase) * 90 - 120;
            const y = 240 + @sin(phase) * 90 - 120;
            r.drawFilledRect(RectF.fromPosSize(x, y, 240, 240), c);
        }
        r.end();
        r.setTarget(null);

        //* Pass 2: the target, scaled up to the whole logical screen.
        //* `texture.val.src` is pre-flipped, so it draws upright.
        r.clear(0, 0, 0, 255);
        r.begin(.logical);
        if (self.useShader) {
            r.setShader(self.wave);
            r.setUniform("time", t);
        }
        const size = eng.viewport.logicalSize;
        const screen = RectF.fromPosSize(0, 0, @floatFromInt(size.x), @floatFromInt(size.y));
        r.drawTexture(&self.target.texture, screen, self.target.texture.val.src);
        r.end();

        //* Pass 3: the flash, fading out over `flash_ms`.
        r.fade(Color.white, @floatCast(self.flashLeftMs / flash_ms));
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig Render Target Example", init.gpa, .{});
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
