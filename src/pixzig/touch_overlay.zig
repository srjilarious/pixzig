//! Draws the virtual pad (`input/touch.zig`) over the game: a ring and a
//! knob for each stick, a disc for each button, brighter while held. The
//! engine draws it after `App.render` whenever `Touch.visible()` says so.
//!
//! The renderer has no circle primitive, so the shapes are two small
//! textures made on first use: a soft-edged disc and a ring, white, tinted
//! and faded as they're drawn.

const std = @import("std");
const gl = @import("zopengl").bindings;
const common = @import("./common.zig");
const Color = common.Color;
const RectF = common.RectF;
const Vec2F = common.Vec2F;
const resources = @import("./resources.zig");
const ResourceManager = resources.ResourceManager;
const TextureHandle = resources.TextureHandle;
const Touch = @import("./input/touch.zig").Touch;
const Viewport = @import("./window.zig").Viewport;

/// Side of the generated textures in pixels. Drawn scaled with linear
/// filtering, so this only has to be large enough to keep the edge smooth
/// at a thumb-sized radius.
const texture_size = 128;
/// The ring's thickness as a fraction of its radius.
const ring_thickness = 0.08;

const full_uv: RectF = .{ .l = 0, .t = 0, .r = 1, .b = 1 };

pub const TouchOverlay = struct {
    disc: ?*TextureHandle = null,
    ring: ?*TextureHandle = null,

    const Self = @This();

    /// Draws `touch`'s pad in framebuffer pixels. `renderer` is the engine's
    /// `Renderer`; labels are drawn only when it has text rendering.
    pub fn draw(self: *Self, renderer: anytype, res: *ResourceManager, viewport: *const Viewport, touch: *const Touch, comptime text: bool) void {
        const disc = self.disc orelse blk: {
            const t = makeTexture(res, "pixzig_touch_disc", .disc) catch |err| {
                std.log.warn("Could not make the touch pad textures: {}", .{err});
                return;
            };
            self.disc = t;
            break :blk t;
        };
        const ring = self.ring orelse blk: {
            const t = makeTexture(res, "pixzig_touch_ring", .ring) catch return;
            self.ring = t;
            break :blk t;
        };

        // The pad reaches into any letterbox bars, which nothing else
        // redraws each frame; clear them so its translucent shapes don't
        // pile up there frame after frame.
        clearBars(viewport);

        renderer.begin(.screen);
        defer renderer.end();

        for (touch.stickSlice()) |*s| {
            renderer.drawTextureColored(ring, square(s.center, s.radiusPx), full_uv, white(0.45));
            const held = s.value.x != 0 or s.value.y != 0;
            const knob: Vec2F = .{
                .x = s.center.x + s.value.x * s.radiusPx,
                .y = s.center.y + s.value.y * s.radiusPx,
            };
            renderer.drawTextureColored(disc, square(knob, s.radiusPx * 0.45), full_uv, white(if (held) 0.7 else 0.4));
        }

        for (touch.buttonSlice()) |*b| {
            renderer.drawTextureColored(disc, square(b.center, b.radiusPx), full_uv, white(if (b.down) 0.5 else 0.2));
            renderer.drawTextureColored(ring, square(b.center, b.radiusPx), full_uv, white(0.5));
            if (text and b.label.len > 0) {
                const label = b.label.slice();
                const size = renderer.measureString(label);
                // Scale the label to about half the button's height,
                // whatever size the default font was packed at.
                const scale = if (size.y > 0) b.radiusPx / size.y else 1;
                _ = renderer.drawScaledStringColored(label, .{
                    .x = b.center.x - size.x * scale / 2,
                    .y = b.center.y - size.y * scale / 2,
                }, scale, white(if (b.down) 0.95 else 0.7));
            }
        }
    }
};

/// Clears the parts of the framebuffer outside `viewport`'s game area to
/// black, leaving the game area and the GL clear colour as they were.
fn clearBars(viewport: *const Viewport) void {
    const fb = viewport.framebufferSize;
    const v = viewport.viewportPx;
    // l, t, r, b in raster pixels: left, right, top and bottom bars.
    const bars = [_][4]i32{
        .{ 0, 0, v.l, fb.y },
        .{ v.r, 0, fb.x, fb.y },
        .{ v.l, 0, v.r, v.t },
        .{ v.l, v.b, v.r, fb.y },
    };
    var clearColor: [4]f32 = undefined;
    gl.getFloatv(gl.COLOR_CLEAR_VALUE, &clearColor);
    gl.clearColor(0, 0, 0, 1);
    gl.enable(gl.SCISSOR_TEST);
    for (bars) |bar| {
        const w = bar[2] - bar[0];
        const h = bar[3] - bar[1];
        if (w <= 0 or h <= 0) continue;
        gl.scissor(bar[0], fb.y - bar[3], w, h);
        gl.clear(gl.COLOR_BUFFER_BIT);
    }
    gl.clearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
    viewport.apply();
}

fn white(alpha: f32) Color {
    return .{ .r = 1, .g = 1, .b = 1, .a = alpha };
}

fn square(center: Vec2F, radius: f32) RectF {
    return RectF.fromPosSize(center.x - radius, center.y - radius, radius * 2, radius * 2);
}

const Shape = enum { disc, ring };

/// A white `shape` with a one-pixel soft edge, in a square texture.
fn makeTexture(res: *ResourceManager, name: []const u8, shape: Shape) !*TextureHandle {
    var pixels: [texture_size * texture_size * 4]u8 = undefined;
    const half: f32 = texture_size / 2;
    const outer = half - 1;
    const inner = outer * (1 - ring_thickness);
    for (0..texture_size) |y| {
        for (0..texture_size) |x| {
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - half;
            const dy = @as(f32, @floatFromInt(y)) + 0.5 - half;
            const d = @sqrt(dx * dx + dy * dy);
            var a = std.math.clamp(outer - d, 0, 1);
            if (shape == .ring) a *= std.math.clamp(d - inner, 0, 1);
            const i = (y * texture_size + x) * 4;
            pixels[i] = 255;
            pixels[i + 1] = 255;
            pixels[i + 2] = 255;
            pixels[i + 3] = @intFromFloat(a * 255);
        }
    }
    const tex = try res.loadTextureFromBuffer(name, texture_size, texture_size, &pixels);
    // Drawn far larger than it is, so smooth rather than pixelated.
    gl.bindTexture(gl.TEXTURE_2D, tex.val.texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    return tex;
}
