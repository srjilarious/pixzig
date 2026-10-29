//* Draws a scene into a small `RenderTarget`, then draws that target
//* scaled up to fill the screen through a custom shader, the usual shape
//* of a low-resolution game with a post-processing pass.
//*
//* - The scene is three tinted sprites (red, green and blue) circling
//*   each other, drawn with additive blending, so where they cross the
//*   colors add up towards white.
//* - The target starts at a quarter of the logical size with nearest
//*   filtering, so scaling it up keeps hard pixel edges. Key 3 switches it
//*   to full size to compare.
//* - The scaled-up frame goes through a blur shader whose `texel` and
//*   `radius` uniforms are set every frame.
//* - Motion uses the render `alpha`, so it stays smooth between update
//*   ticks.
//* - Space flashes the screen white with `fade`.
//*
//* Keys: 1 toggles the blur, 2 toggles additive blending, 3 toggles the
//* target size, Up/Down change the blur radius, Space flashes, Escape quits.

//* -- collapsed: Imports --
const std = @import("std");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const Color = pixzig.common.Color;
const Vec2F = pixzig.common.Vec2F;
const Vec2U = pixzig.common.Vec2U;
const Sprite = pixzig.sprites.Sprite;
const TextureHandle = pixzig.resources.TextureHandle;
//* ---

const AppRunner = pixzig.AppRunner(App, .{
    .screenshotHook = true,
});

//* The fragment shader gets the batch's usual inputs (see
//* `Renderer.createShader`) plus our own `texel` (the size of one target
//* pixel in UVs) and `radius` (how many target pixels apart the samples
//* are). It averages a 5x5 neighbourhood with Gaussian weights
//* (1 4 6 4 1 in each direction, out of 256 in total).
const blur_shader: [*:0]const u8 =
    \\#version 300 es
    \\precision mediump float;
    \\in vec2 Texcoord;
    \\in vec4 Col;
    \\flat in float Mode;
    \\uniform sampler2D tex;
    \\uniform vec2 texel;
    \\uniform float radius;
    \\out vec4 fragColor;
    \\void main() {
    \\    float w[5] = float[5](1.0, 4.0, 6.0, 4.0, 1.0);
    \\    vec4 sum = vec4(0.0);
    \\    for (int y = 0; y < 5; y++) {
    \\        for (int x = 0; x < 5; x++) {
    \\            vec2 offset = vec2(float(x - 2), float(y - 2)) * texel * radius;
    \\            sum += texture(tex, Texcoord + offset) * w[x] * w[y];
    \\        }
    \\    }
    \\    fragColor = (sum / 256.0) * Col;
    \\}
;

const flash_ms: f64 = 400;
const sprite_size: f32 = 96;
const max_blur_radius: f32 = 4;

pub const App = struct {
    alloc: std.mem.Allocator,
    target: pixzig.RenderTarget,
    blur: *pixzig.resources.ShaderHandle,
    //* The three frames of the player's walk cycle, from the atlas.
    frames: [3]*TextureHandle,
    sprites: [3]Sprite,
    elapsedMs: f64 = 0,
    //* The length of one update tick, so `render` can place the scene
    //* `alpha` of the way into the next one.
    stepMs: f64 = 0,
    flashLeftMs: f64 = 0,
    useBlur: bool = true,
    blurRadius: f32 = 1,
    additive: bool = true,
    lowRes: bool = true,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);
        errdefer alloc.destroy(app);

        _ = try eng.resources.loadAtlas("assets/pac-tiles");
        const frames = [3]*TextureHandle{
            try eng.resources.getTexture("player_right_1"),
            try eng.resources.getTexture("player_right_2"),
            try eng.resources.getTexture("player_right_3"),
        };

        var target = try pixzig.RenderTarget.init(targetSize(eng, true), .{ .filter = .nearest });
        errdefer target.deinit();

        app.* = .{
            .alloc = alloc,
            .target = target,
            .blur = try eng.renderer.createShader(&eng.resources, "blur", blur_shader),
            .frames = frames,
            .sprites = undefined,
        };

        const tints = [_]Color{ Color.red, Color.green, Color.blue };
        for (&app.sprites, tints) |*spr, tint| {
            spr.* = Sprite.create(frames[0]);
            spr.setOriginCentered();
            spr.setSize(sprite_size, sprite_size);
            spr.tint = tint;
        }
        return app;
    }

    pub fn deinit(self: *App) void {
        self.target.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) void {
        self.elapsedMs += delta;
        self.stepMs = delta;
        self.flashLeftMs = @max(0, self.flashLeftMs - delta);

        const kb = &eng.inputs.keyboard;
        if (kb.pressed(.escape)) eng.quit();
        if (kb.pressed(.one)) self.useBlur = !self.useBlur;
        if (kb.pressed(.two)) self.additive = !self.additive;
        if (kb.pressed(.three)) {
            self.lowRes = !self.lowRes;
            self.target.resize(targetSize(eng, self.lowRes)) catch |err| {
                std.log.err("Couldn't resize the render target: {}", .{err});
            };
        }
        if (kb.pressed(.up)) self.blurRadius = @min(max_blur_radius, self.blurRadius + 0.5);
        if (kb.pressed(.down)) self.blurRadius = @max(0, self.blurRadius - 0.5);
        if (kb.pressed(.space)) self.flashLeftMs = flash_ms;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine, alpha: f32) void {
        const r = &eng.renderer;
        //* Time as of this frame: the last update plus `alpha` of a tick.
        //* Using `elapsedMs` alone would hold each position until the next
        //* update, which stutters on a display faster than the update rate.
        const nowMs = self.elapsedMs + @as(f64, alpha) * self.stepMs;
        const t: f32 = @floatCast(nowMs / 1000.0);
        const logical = logicalSizeF(eng);

        //* Pass 1: the scene, into the target. A `.logical` pass inside a
        //* target stretches the logical screen over it, so the scene is
        //* drawn in the same coordinates as everything else.
        r.setTarget(&self.target);
        r.begin(.logical);
        r.clear(10, 10, 30, 255);
        if (self.additive) r.setBlend(.additive);
        //* Ping-pong through the walk cycle: 1 2 3 2 1 2 3 ...
        const cycle = [_]usize{ 0, 1, 2, 1 };
        const frame = self.frames[cycle[@as(usize, @intFromFloat(nowMs / 90)) % cycle.len]];
        for (&self.sprites, 0..) |*spr, i| {
            const phase = t + @as(f32, @floatFromInt(i)) * 2.1;
            spr.setTexture(frame);
            spr.setPosF(logical.x / 2 + @cos(phase) * 70, logical.y / 2 + @sin(phase) * 70);
            r.drawSprite(spr);
        }
        r.end();
        r.setTarget(null);

        //* Pass 2: the target, scaled up to the whole logical screen.
        //* `texture.val.src` is pre-flipped, so it draws upright.
        r.clear(0, 0, 0, 255);
        r.begin(.logical);
        if (self.useBlur) {
            const size = self.target.size();
            r.setShader(self.blur);
            r.setUniform("texel", Vec2F{
                .x = 1 / @as(f32, @floatFromInt(size.x)),
                .y = 1 / @as(f32, @floatFromInt(size.y)),
            });
            r.setUniform("radius", self.blurRadius);
        }
        const screen = RectF.fromPosSize(0, 0, logical.x, logical.y);
        r.drawTexture(&self.target.texture, screen, self.target.texture.val.src);
        r.end();

        //* Pass 3: what's on, drawn straight to the screen. The shader and
        //* blend mode were reset by the last `end`, so the text is sharp.
        r.begin(.logical);
        var buf: [160]u8 = undefined;
        const status = std.fmt.bufPrint(&buf, "1 blur: {s} (radius {d:.1}, Up/Down)   2 additive: {s}   3 target: {d}x{d}", .{
            if (self.useBlur) "on" else "off",
            self.blurRadius,
            if (self.additive) "on" else "off",
            self.target.size().x,
            self.target.size().y,
        }) catch "";
        _ = r.drawText(status, .{ .x = 8, .y = 8 }, .{ .shadow = Color.black });
        r.end();

        //* Pass 4: the flash, fading out over `flash_ms`.
        r.fade(Color.white, @floatCast(self.flashLeftMs / flash_ms));
    }

    fn logicalSizeF(eng: *AppRunner.Engine) Vec2F {
        const size = eng.viewport.logicalSize;
        return .{ .x = @floatFromInt(size.x), .y = @floatFromInt(size.y) };
    }

    //* A quarter of the logical screen in each direction, or all of it.
    fn targetSize(eng: *AppRunner.Engine, lowRes: bool) Vec2U {
        const logical = eng.viewport.logicalSize;
        const div: i32 = if (lowRes) 4 else 1;
        return .{
            .x = @intCast(@divTrunc(logical.x, div)),
            .y = @intCast(@divTrunc(logical.y, div)),
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig Render Target Example", init.gpa, .{});
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
