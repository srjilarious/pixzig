//! Draws the virtual pad (`input/touch.zig`) over the game: a ring and a
//! knob for each stick, a disc for each button, brighter while held. The
//! engine draws it after `App.render` whenever `Touch.visible()` says so,
//! or earlier in the frame if the app calls `eng.drawTouchOverlay()`.
//!
//! The renderer has no circle primitive, so the default shapes are two
//! small textures made on first use: a soft-edged disc and a ring, white,
//! tinted and faded as they're drawn. Set `eng.touchOverlay.style` to
//! change the colours and fades or draw the game's own textures instead:
//!
//! ```zig
//! eng.touchOverlay.style = .{
//!     .color = .{ .r = 1, .g = 0.8, .b = 0.3, .a = 1 },
//!     .button = try eng.resources.loadTexture("pad_button", "assets/pad_button.png"),
//! };
//! ```

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

/// How the pad looks. Each texture is drawn stretched over the control's
/// square, tinted with `color` at the given alpha; null uses the generated
/// disc or ring.
pub const Style = struct {
    /// Tint for every part of the pad. Its alpha scales the alphas below.
    color: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 },

    /// A stick's ring, at its full radius.
    stickRing: ?*TextureHandle = null,
    stickRingAlpha: f32 = 0.45,
    /// A stick's knob, which follows the thumb.
    knob: ?*TextureHandle = null,
    /// The knob's radius as a fraction of the stick's.
    knobScale: f32 = 0.45,
    knobAlpha: f32 = 0.4,
    knobHeldAlpha: f32 = 0.7,

    /// A button's face.
    button: ?*TextureHandle = null,
    buttonAlpha: f32 = 0.2,
    buttonHeldAlpha: f32 = 0.5,
    /// The outline drawn over a button's face. Set `buttonRingAlpha` to 0
    /// for none, e.g. when `button` has its own border.
    buttonRing: ?*TextureHandle = null,
    buttonRingAlpha: f32 = 0.5,

    /// Button labels, drawn with the default font when the engine has text
    /// rendering.
    labels: bool = true,
    labelAlpha: f32 = 0.7,
    labelHeldAlpha: f32 = 0.95,

    fn tint(self: *const Style, alpha: f32) Color {
        return .{ .r = self.color.r, .g = self.color.g, .b = self.color.b, .a = self.color.a * alpha };
    }
};

pub const TouchOverlay = struct {
    /// How the pad is drawn. Change it at any time.
    style: Style = .{},
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

        const st = &self.style;
        for (touch.stickSlice()) |*s| {
            renderer.drawTextureColored(st.stickRing orelse ring, square(s.center, s.radiusPx), full_uv, st.tint(st.stickRingAlpha));
            const held = s.value.x != 0 or s.value.y != 0;
            const knob: Vec2F = .{
                .x = s.center.x + s.value.x * s.radiusPx,
                .y = s.center.y + s.value.y * s.radiusPx,
            };
            const knobAlpha = if (held) st.knobHeldAlpha else st.knobAlpha;
            renderer.drawTextureColored(st.knob orelse disc, square(knob, s.radiusPx * st.knobScale), full_uv, st.tint(knobAlpha));
        }

        for (touch.buttonSlice()) |*b| {
            const faceAlpha = if (b.down) st.buttonHeldAlpha else st.buttonAlpha;
            renderer.drawTextureColored(st.button orelse disc, square(b.center, b.radiusPx), full_uv, st.tint(faceAlpha));
            if (st.buttonRingAlpha > 0) {
                renderer.drawTextureColored(st.buttonRing orelse ring, square(b.center, b.radiusPx), full_uv, st.tint(st.buttonRingAlpha));
            }
            if (text and st.labels and b.label.len > 0) {
                const label = b.label.slice();
                // Scale the label to about half the button's height,
                // whatever size the default font was packed at.
                const height = renderer.measureText(label, .{}).y;
                const scale = if (height > 0) b.radiusPx / height else 1;
                const size = renderer.measureText(label, .{ .scale = scale });
                _ = renderer.drawText(label, .{ .x = b.center.x, .y = b.center.y - size.y / 2 }, .{
                    .scale = scale,
                    .color = st.tint(if (b.down) st.labelHeldAlpha else st.labelAlpha),
                    .@"align" = .center,
                });
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
