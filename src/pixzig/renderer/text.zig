const std = @import("std");

const common = @import("../common.zig");
const resources = @import("../resources.zig");
const font_atlas = @import("./font_atlas.zig");
const sprite_batch = @import("./sprite_batch.zig");

const Vec2F = common.Vec2F;
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

/// Scales an integer glyph metric, truncated to whole pixels so glyphs
/// stay on the pixel grid when the pen starts on it.
fn scaleInt(value: i32, scale: f32) f32 {
    return @trunc(@as(f32, @floatFromInt(value)) * scale);
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

/// Where `drawText` puts the text relative to `pos.x`.
pub const TextAlign = enum {
    /// `pos.x` is the left edge.
    left,
    /// `pos.x` is the middle.
    center,
    /// `pos.x` is the right edge.
    right,
};

/// How `drawText` draws and `measureText` measures a string. Every field
/// has a default, so `.{}` is the default font in white at its own size.
pub const TextStyle = struct {
    /// The font to draw with; null uses the renderer's default font.
    font: ?*resources.FontAtlasHandle = null,
    color: Color = .white,
    /// Multiplies the font's pixel size. Glyph metrics are truncated to
    /// whole pixels after scaling, so text started on the pixel grid stays
    /// on it.
    scale: f32 = 1.0,
    /// Only the parts of glyphs inside this rect are drawn, in the pass's
    /// coordinate space. Edge glyphs are trimmed, not dropped.
    clip: ?RectF = null,
    @"align": TextAlign = .left,
    /// When set, the text is drawn a second time underneath in this color,
    /// moved by `shadowOffset`.
    shadow: ?Color = null,
    /// How far the shadow sits from the text, in pixels (not scaled).
    shadowOffset: Vec2F = .{ .x = 1, .y = 1 },
};

/// Lays out strings and queues one quad per glyph into the renderer's
/// `SpriteBatch`, so text keeps its place in draw order among sprites and
/// shapes. A TTF atlas draws in `.mask` mode (the glyph coverage tints the
/// color); a bitmap font's RGBA image in `.texture` mode.
///
/// A line drawn at `pos` occupies a box from `pos.y` down to
/// `pos.y + (ascent + descent) * scale`, with the baseline `ascent` below
/// the top. `measureText` returns that box, so centering on it centers the
/// text as drawn.
pub const TextRenderer = struct {
    /// The batch glyphs are queued into. Owned by the renderer.
    batch: *SpriteBatch,
    /// The default font, used when a style names none. A hot reload
    /// replaces the atlas inside the handle, so the next draw uses it.
    font: ?*resources.FontAtlasHandle = null,
    /// Set once the first draw call finds no font, so the "no font" warning
    /// is logged one time rather than on every string, every frame.
    warnedNoFont: bool = false,

    pub fn init(batch: *SpriteBatch) TextRenderer {
        return .{ .batch = batch };
    }

    /// Makes sure every glyph `text` needs is packed into the font atlas
    /// and uploaded before quads are queued for it. If packing grew the
    /// atlas texture, every glyph's UVs changed, so any quads already
    /// queued this frame are flushed against the still-current texture
    /// before the grown one is uploaded.
    fn syncAtlasForText(self: *TextRenderer, fa: *FontAtlas, text: []const u8) void {
        fa.loadBlocksForText(text);
        if (fa.grewSinceUpload) self.batch.flush();
        fa.commitTexture();
    }

    /// Adopt a new default font.
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

    /// The atlas `style` draws with, or null (after warning once) when it
    /// names no font and there is no default.
    fn atlasFor(self: *TextRenderer, style: TextStyle) ?*FontAtlas {
        const handle = style.font orelse self.font orelse {
            self.warnNoFont();
            return null;
        };
        return &handle.val;
    }

    /// Draws `text` with its line box's top at `pos.y` and its left edge,
    /// middle or right edge at `pos.x` (see `TextStyle.align`). Returns the
    /// same size `measureText` would.
    pub fn drawText(self: *TextRenderer, text: []const u8, pos: Vec2F, style: TextStyle) Vec2F {
        const fa = self.atlasFor(style) orelse return Vec2F.zero;
        self.syncAtlasForText(fa, text);

        const size = measureWith(fa, text, style.scale);
        const left: f32 = switch (style.@"align") {
            .left => pos.x,
            .center => pos.x - @trunc(size.x / 2),
            .right => pos.x - size.x,
        };
        const origin: Vec2F = .{ .x = left, .y = pos.y };

        if (style.shadow) |shadowColor| {
            self.queueGlyphs(fa, text, origin.add(style.shadowOffset), style.scale, shadowColor, style.clip);
        }
        self.queueGlyphs(fa, text, origin, style.scale, style.color, style.clip);
        return size;
    }

    /// The size `drawText` gives `text` in `style`: the summed glyph
    /// advances wide, and the font's ascent plus descent tall (the line box
    /// the glyphs are drawn in), both scaled. Alignment, clip and shadow
    /// don't change it.
    pub fn measureText(self: *TextRenderer, text: []const u8, style: TextStyle) Vec2F {
        const fa = self.atlasFor(style) orelse return Vec2F.zero;
        // Pack any not-yet-loaded blocks so their advances are known. No
        // quads are queued here, so a grow needs no batch flush.
        _ = fa.ensureBlocksForText(text);
        return measureWith(fa, text, style.scale);
    }

    /// The default font's line spacing at scale 1: ascent, descent and the
    /// font's line gap, i.e. how far apart to put the tops of consecutive
    /// lines. Null when there is no default font.
    pub fn lineHeight(self: *const TextRenderer) ?f32 {
        const handle = self.font orelse return null;
        const fa = &handle.val;
        return @floatFromInt(fa.ascent + fa.descent + fa.lineGap);
    }

    fn measureWith(fa: *FontAtlas, text: []const u8, scale: f32) Vec2F {
        var width: f32 = 0;
        var it = CodepointIter{ .text = text };
        while (it.next()) |cp| {
            const ch = fa.getChar(cp) orelse continue;
            width += scaleInt(ch.advance, scale);
        }
        return .{ .x = width, .y = scaleInt(fa.ascent + fa.descent, scale) };
    }

    /// Queues one quad per visible glyph, with the line box's top-left at
    /// `pos`, trimming quads (and their UVs) to `clip` when one is given.
    fn queueGlyphs(self: *TextRenderer, fa: *FontAtlas, text: []const u8, pos: Vec2F, scale: f32, color: Color, clip: ?RectF) void {
        const mode: DrawMode = if (fa.isAlpha) .mask else .texture;
        var currX: f32 = pos.x;
        const baseline = pos.y + scaleInt(fa.ascent, scale);
        var it = CodepointIter{ .text = text };
        while (it.next()) |cp| {
            const ch = fa.getChar(cp) orelse continue;
            const advance = scaleInt(ch.advance, scale);
            defer currX += advance;

            // Only draw if the character has a visual representation.
            if (ch.size.x <= 0 or ch.size.y <= 0) continue;

            var dest = RectF.fromPosSize(
                currX + scaleInt(ch.bearing.x, scale),
                baseline - scaleInt(ch.bearing.y, scale),
                scaleInt(ch.size.x, scale),
                scaleInt(ch.size.y, scale),
            );
            var src = ch.coords;

            if (clip) |c| {
                // Wholly right of the clip: nothing further will show.
                if (dest.l >= c.r) break;
                if (!clipQuad(&dest, &src, c)) continue;
            }

            self.batch.draw(&fa.texture, dest, src, .none, color, mode);
        }
    }
};

/// Trims `dest` to `clip`, moving `src`'s UV edges by the same fraction so
/// no neighbouring glyph bleeds in. False when nothing is left to draw.
fn clipQuad(dest: *RectF, src: *RectF, clip: RectF) bool {
    if (dest.r <= clip.l or dest.l >= clip.r or dest.b <= clip.t or dest.t >= clip.b) return false;

    const uPerPx = (src.r - src.l) / dest.width();
    const vPerPx = (src.b - src.t) / dest.height();
    if (dest.l < clip.l) {
        src.l += (clip.l - dest.l) * uPerPx;
        dest.l = clip.l;
    }
    if (dest.r > clip.r) {
        src.r -= (dest.r - clip.r) * uPerPx;
        dest.r = clip.r;
    }
    if (dest.t < clip.t) {
        src.t += (clip.t - dest.t) * vPerPx;
        dest.t = clip.t;
    }
    if (dest.b > clip.b) {
        src.b -= (dest.b - clip.b) * vPerPx;
        dest.b = clip.b;
    }
    return true;
}
