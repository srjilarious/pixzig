const std = @import("std");

const common = @import("../common.zig");
const resources = @import("../resources.zig");
const font_atlas = @import("./font_atlas.zig");
const sprite_batch = @import("./sprite_batch.zig");

const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Color = common.Color;
const SpriteBatch = sprite_batch.SpriteBatch;
const DrawMode = sprite_batch.DrawMode;

pub const FontAtlas = font_atlas.FontAtlas;
pub const FontFace = font_atlas.FontFace;
pub const Character = font_atlas.Character;
pub const stb_tt = font_atlas.stb_tt;
pub const FontMetrics = font_atlas.FontMetrics;
pub const measureFontFile = font_atlas.measureFontFile;
pub const measureFontFileIndexed = font_atlas.measureFontFileIndexed;
pub const findFaceIndexByName = font_atlas.findFaceIndexByName;

fn scaleInt(value: i32, scale: f32) i32 {
    return @as(i32, @intFromFloat(@as(f32, @floatFromInt(value)) * scale));
}

/// Iterates the UTF-8 codepoints of a byte slice, yielding U+FFFD for any
/// malformed sequence so a bad byte still advances the pen by one glyph
/// rather than derailing the whole string.
const CodepointIter = struct {
    text: []const u8,
    i: usize = 0,

    fn next(self: *CodepointIter) ?u21 {
        if (self.i >= self.text.len) return null;
        const seq_len = std.unicode.utf8ByteSequenceLength(self.text[self.i]) catch {
            self.i += 1;
            return 0xFFFD;
        };
        if (self.i + seq_len > self.text.len) {
            self.i = self.text.len;
            return 0xFFFD;
        }
        const cp = std.unicode.utf8Decode(self.text[self.i .. self.i + seq_len]) catch {
            self.i += seq_len;
            return 0xFFFD;
        };
        self.i += seq_len;
        return cp;
    }
};

const white: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 };

/// Lays out strings with the active font and queues one quad per glyph into
/// the renderer's `SpriteBatch`, so text keeps its place in draw order
/// among sprites and shapes. A TTF atlas draws in `.mask` mode (the glyph
/// coverage tints the color); a bitmap font's RGBA image in `.texture` mode.
pub const TextRenderer = struct {
    /// The batch glyphs are queued into. Owned by the renderer.
    batch: *SpriteBatch,
    /// Active font. A hot reload replaces the atlas inside the handle, so
    /// the next draw uses it.
    font: ?*resources.FontAtlasHandle = null,
    /// Set once the first draw call finds no font, so the "no font" warning
    /// is logged one time rather than on every string, every frame.
    warnedNoFont: bool = false,

    pub fn init(batch: *SpriteBatch) TextRenderer {
        return .{ .batch = batch };
    }

    /// Makes sure every glyph `text` needs is packed into the active font
    /// atlas and uploaded before quads are queued for it. If packing grew
    /// the atlas texture, every glyph's UVs changed, so any quads already
    /// queued this frame are flushed against the still-current texture
    /// before the grown one is uploaded.
    fn syncAtlasForText(self: *TextRenderer, fa: *FontAtlas, text: []const u8) void {
        fa.loadBlocksForText(text);
        if (fa.grewSinceUpload) self.batch.flush();
        fa.commitTexture();
    }

    /// Adopt a new font for rendering.
    pub fn setFont(self: *TextRenderer, font: *resources.FontAtlasHandle) void {
        self.font = font;
        self.warnedNoFont = false;
    }

    /// Logs the missing-font error once per renderer (reset by `setFont`),
    /// so a game that draws text before setting a font gets one clear line
    /// instead of one per string per frame.
    fn warnNoFont(self: *TextRenderer) void {
        if (self.warnedNoFont) return;
        self.warnedNoFont = true;
        std.log.err("TextRenderer: No Font set. Cannot draw text. " ++
            "Set one with Renderer.setDefaultFont, or EngineInitOptions.renderInitOpts.font.", .{});
    }

    pub fn drawString(self: *TextRenderer, text: []const u8, pos: Vec2I) Vec2I {
        return self.drawGlyphs(text, pos, 1.0, white, null);
    }

    /// Like `drawString`, but tints every glyph by `color` instead of
    /// rendering plain white.
    pub fn drawStringColored(self: *TextRenderer, text: []const u8, pos: Vec2I, color: Color) Vec2I {
        return self.drawGlyphs(text, pos, 1.0, color, null);
    }

    pub fn drawScaledString(self: *TextRenderer, text: []const u8, pos: Vec2I, scale: f32) Vec2I {
        return self.drawGlyphs(text, pos, scale, white, null);
    }

    /// Like drawString but clips character quads to `clip` in the active
    /// draw coordinate space. Partially-visible edge characters have their
    /// source UV rect trimmed to match so no bleed from adjacent font glyphs
    /// appears.
    pub fn drawClippedString(self: *TextRenderer, text: []const u8, pos: Vec2I, clip: RectF) Vec2I {
        return self.drawGlyphs(text, pos, 1.0, white, clip);
    }

    /// The one glyph loop behind every draw call. Returns the drawn size:
    /// the summed advances, and the tallest glyph.
    fn drawGlyphs(self: *TextRenderer, text: []const u8, pos: Vec2I, scale: f32, color: Color, clip: ?RectF) Vec2I {
        var drawSize: Vec2I = .{ .x = 0, .y = 0 };
        const handle = self.font orelse {
            self.warnNoFont();
            return drawSize;
        };
        const fa = &handle.val;
        self.syncAtlasForText(fa, text);

        const mode: DrawMode = if (fa.isAlpha) .mask else .texture;
        var currX: i32 = pos.x;
        const posY = pos.y + scaleInt(fa.ascent, scale);
        var it = CodepointIter{ .text = text };
        while (it.next()) |cp| {
            const ch = fa.getChar(cp) orelse continue;
            const advance = scaleInt(ch.advance, scale);

            // Only draw if the character has a visual representation.
            if (ch.size.x > 0 and ch.size.y > 0) {
                var dest = RectF.fromPosSize(
                    currX + scaleInt(ch.bearing.x, scale),
                    posY - scaleInt(ch.bearing.y, scale),
                    scaleInt(ch.size.x, scale),
                    scaleInt(ch.size.y, scale),
                );
                var src = ch.coords;

                if (clip) |c| {
                    // Entirely left of clip: advance the pen but don't draw.
                    if (dest.r <= c.l) {
                        currX += advance;
                        drawSize.x += advance;
                        continue;
                    }
                    // Entirely right of clip: nothing further will be visible.
                    if (dest.l >= c.r) break;

                    const uv_per_px = (src.r - src.l) / dest.width();
                    if (dest.l < c.l) {
                        src.l += (c.l - dest.l) * uv_per_px;
                        dest.l = c.l;
                    }
                    if (dest.r > c.r) {
                        src.r -= (dest.r - c.r) * uv_per_px;
                        dest.r = c.r;
                    }
                }

                self.batch.draw(&fa.texture, dest, src, .none, color, mode);
            }

            currX += advance;
            drawSize.x += advance;
            drawSize.y = @max(drawSize.y, scaleInt(ch.size.y, scale));
        }

        return drawSize;
    }

    /// Measures `text` without drawing it.
    pub fn measureString(self: *TextRenderer, text: []const u8) Vec2I {
        var width: i32 = 0;
        var height: i32 = 0;

        const handle = self.font orelse {
            self.warnNoFont();
            return .{ .x = 0, .y = 0 };
        };

        // Pack any not-yet-loaded blocks so their advances are known. No
        // quads are queued here, so a grow needs no batch flush.
        _ = handle.val.ensureBlocksForText(text);

        var it = CodepointIter{ .text = text };
        while (it.next()) |cp| {
            const ch = handle.val.getChar(cp) orelse continue;
            width += ch.advance;
            height = @max(height, ch.size.y);
        }

        return Vec2I{ .x = width, .y = height };
    }
};
