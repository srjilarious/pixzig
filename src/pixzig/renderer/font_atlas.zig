const std = @import("std");
const builtin = @import("builtin");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
pub const stb_tt = @import("stb_truetype");

const common = @import("../common.zig");
const textures = @import("./textures.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Texture = textures.Texture;

pub const Character = struct { coords: RectF, size: Vec2I, bearing: Vec2I, advance: i32 };

/// Font metrics scaled to a target pixel size, without packing any glyphs
/// into a texture -- unlike `initFromTtf*`, this needs no GL context, so it
/// can run before a window/renderer exists (e.g. to size a window from the
/// font it's about to load).
pub const FontMetrics = struct {
    /// Horizontal advance of a representative glyph ('M'). For a monospace
    /// font this is every glyph's advance, i.e. the terminal cell width.
    advance: i32,
    /// ascent - descent + line_gap: the font's recommended line-to-line
    /// spacing, i.e. the terminal cell height.
    line_height: i32,
    /// Ascent alone, for baseline placement.
    ascent: i32,
};

fn measureFontData(fontData: []const u8, fontSize: f32) !FontMetrics {
    var font_info: stb_tt.c.stbtt_fontinfo = undefined;
    if (stb_tt.c.stbtt_InitFont(&font_info, fontData.ptr, 0) == 0) return error.InvalidFont;

    var ascent: i32 = undefined;
    var descent: i32 = undefined;
    var line_gap: i32 = undefined;
    stb_tt.c.stbtt_GetFontVMetrics(&font_info, &ascent, &descent, &line_gap);

    var advance: i32 = undefined;
    var lsb: i32 = undefined;
    stb_tt.c.stbtt_GetCodepointHMetrics(&font_info, 'M', &advance, &lsb);

    const scale = stb_tt.c.stbtt_ScaleForPixelHeight(&font_info, fontSize);
    const scaled = struct {
        fn of(value: i32, s: f32) i32 {
            return @intFromFloat(@round(s * @as(f32, @floatFromInt(value))));
        }
    }.of;

    return .{
        .advance = scaled(advance, scale),
        .line_height = scaled(ascent - descent + line_gap, scale),
        .ascent = scaled(ascent, scale),
    };
}

/// Reads `fontPath` and returns its `FontMetrics` at `fontSize`. No GL
/// context required -- safe to call before window/renderer creation.
pub fn measureFontFile(fontPath: []const u8, fontSize: f32, alloc: std.mem.Allocator) !FontMetrics {
    const io = std.Io.Threaded.global_single_threaded.io();
    const fontData = try std.Io.Dir.cwd().readFileAlloc(io, fontPath, alloc, .unlimited);
    defer alloc.free(fontData);

    return measureFontData(fontData, fontSize);
}

pub const FontAtlas = struct {
    chars: std.AutoHashMap(u32, Character),
    texture: Texture,
    maxY: i32,
    isAlpha: bool,

    pub fn getChar(self: *FontAtlas, char: u32) ?Character {
        return self.chars.get(char);
    }

    fn initFromTtf(fontData: []const u8, fontSize: f32, alloc: std.mem.Allocator) !FontAtlas {
        var chars = std.AutoHashMap(u32, Character).init(alloc);
        errdefer chars.deinit();
        // Pack font using STB_TrueType
        var pack_context = stb_tt.c.stbtt_pack_context{};
        const GlyphBufferWidth = 2048;
        const GlyphBufferHeight = 1024;
        const glyphBuffer = try alloc.alloc(u8, GlyphBufferWidth * GlyphBufferHeight);
        defer alloc.free(glyphBuffer);
        @memset(glyphBuffer, 0); // Initialize to black

        // Pack ASCII printable characters (32-126 inclusive, space through
        // tilde) -- stbtt_PackFontRange packs `num_chars` codepoints
        // starting at 32, so this needs +1 or codepoint 126 ('~') is
        // silently left out of the atlas.
        const num_chars = 126 - 32 + 1;
        const packed_chars = try alloc.alloc(stb_tt.c.stbtt_packedchar, num_chars);
        defer alloc.free(packed_chars);

        _ = stb_tt.c.stbtt_PackBegin(&pack_context, glyphBuffer.ptr, GlyphBufferWidth, GlyphBufferHeight, 0, 1, null);
        _ = stb_tt.c.stbtt_PackFontRange(&pack_context, fontData.ptr, 0, fontSize, 32, num_chars, packed_chars.ptr);
        stb_tt.c.stbtt_PackEnd(&pack_context);

        // Get font metrics for baseline calculation
        var font_info: stb_tt.c.stbtt_fontinfo = undefined;
        _ = stb_tt.c.stbtt_InitFont(&font_info, fontData.ptr, 0);

        var ascent: i32 = undefined;
        var descent: i32 = undefined;
        var line_gap: i32 = undefined;
        stb_tt.c.stbtt_GetFontVMetrics(&font_info, &ascent, &descent, &line_gap);

        const scale = stb_tt.c.stbtt_ScaleForPixelHeight(&font_info, fontSize);
        const scaled_ascent = @as(i32, @intFromFloat(scale * @as(f32, @floatFromInt(ascent))));

        var maxY: i32 = 0;

        // Convert packed characters to our Character format
        for (packed_chars, 0..) |packed_char, i| {
            const char_code: u32 = 32 + @as(u32, @intCast(i));

            // Skip characters with no bitmap (like space)
            if (packed_char.x0 == packed_char.x1 or packed_char.y0 == packed_char.y1) {
                // Still add space character with advance but no visual
                if (char_code == 32) { // Space character
                    try chars.put(char_code, Character{
                        .coords = RectF.fromCoords(0, 0, 0, 0, GlyphBufferWidth, GlyphBufferHeight),
                        .size = .{ .x = 0, .y = 0 },
                        .bearing = .{ .x = 0, .y = 0 },
                        .advance = @as(i32, @intFromFloat(packed_char.xadvance)),
                    });
                }
                continue;
            }

            const char_width = packed_char.x1 - packed_char.x0;
            const char_height = packed_char.y1 - packed_char.y0;

            // Generate teh texture coordinates
            const coords = RectF.fromCoords(
                @intCast(packed_char.x0),
                @intCast(packed_char.y0),
                @intCast(char_width),
                @intCast(char_height),
                GlyphBufferWidth,
                GlyphBufferHeight,
            );

            // STB gives us offset from baseline, convert to your bearing format
            // Note: STB's yoff is negative for characters that extend above baseline
            const bearing_x = @as(i32, @intFromFloat(packed_char.xoff));
            const bearing_y = @as(i32, @intFromFloat(-packed_char.yoff)); // Flip Y coordinate

            try chars.put(char_code, Character{
                .coords = coords,
                .size = .{ .x = char_width, .y = char_height },
                .bearing = .{ .x = bearing_x, .y = bearing_y },
                .advance = @as(i32, @intFromFloat(packed_char.xadvance)),
            });

            // Track max Y for baseline calculations
            maxY = @max(maxY, bearing_y);
        }

        // If maxY is 0, use the font's ascent
        if (maxY == 0) {
            maxY = scaled_ascent;
        }

        // Generate OpenGL texture
        var charTex: c_uint = undefined;
        gl.genTextures(1, &charTex);
        errdefer gl.deleteTextures(1, &charTex);
        gl.bindTexture(gl.TEXTURE_2D, charTex);

        const format = if (builtin.os.tag == .emscripten) gl.ALPHA else gl.RED;

        gl.texImage2D(gl.TEXTURE_2D, 0, format, @intCast(GlyphBufferWidth), @intCast(GlyphBufferHeight), 0, format, gl.UNSIGNED_BYTE, @ptrCast(glyphBuffer));

        // Set texture parameters for crisp text rendering
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

        return .{
            .chars = chars,
            .texture = Texture{
                .texture = charTex,
                .size = Vec2U{ .x = @intCast(GlyphBufferWidth), .y = @intCast(GlyphBufferHeight) },
                .src = RectF{ .l = 0, .t = 0, .r = 1, .b = 1 },
            },
            .maxY = maxY,
            .isAlpha = true,
        };
    }

    /// Alternative init function that loads from file path (for non-WASM)
    pub fn initFromTtfFile(fontPath: []const u8, fontSize: f32, alloc: std.mem.Allocator) !FontAtlas {
        const io = std.Io.Threaded.global_single_threaded.io();
        const fontData = try std.Io.Dir.cwd().readFileAlloc(io, fontPath, alloc, .unlimited);
        defer alloc.free(fontData);

        return initFromTtf(fontData, fontSize, alloc);
    }

    /// Alternative init function for embedded fonts (WASM-friendly)
    pub fn initFromTtfEmbedded(comptime fontPath: []const u8, fontSize: f32, alloc: std.mem.Allocator) !FontAtlas {
        const fontData = @embedFile(fontPath);
        return initFromTtf(fontData, fontSize, alloc);
    }

    pub fn initFromBitmap(
        fontImagePath: []const u8,
        charWidth: i32,
        charHeight: i32,
        charsPerRow: i32,
        chars: []const u8,
        alloc: std.mem.Allocator,
    ) !FontAtlas {
        const fipz = try alloc.dupeZ(u8, fontImagePath);
        defer alloc.free(fipz);

        var image = try stbi.Image.loadFromFile(fipz, 0);
        defer image.deinit();
        if (image.width == 0 or image.height == 0) {
            return error.ImageLoadFailed;
        }

        // Generate OpenGL texture
        var charTex: c_uint = undefined;
        gl.genTextures(1, &charTex);
        errdefer gl.deleteTextures(1, &charTex);

        gl.bindTexture(gl.TEXTURE_2D, charTex);

        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @intCast(image.width), @intCast(image.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, image.data.ptr);

        // Set texture parameters for crisp text rendering
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

        var charsMap = std.AutoHashMap(u32, Character).init(alloc);
        errdefer charsMap.deinit();
        var maxY: i32 = 0;

        for (0..chars.len) |i| {
            const char_code = chars[i];
            const chW = @as(u32, @intCast(charWidth));
            const chH = @as(u32, @intCast(charHeight));

            const col = i % @as(u32, @intCast(charsPerRow));
            const row = i / @as(u32, @intCast(charsPerRow));

            const x0 = col * chW;
            const y0 = row * chH;

            // Skip characters that would be out of bounds
            if (x0 + chW > image.width or y0 + chH > image.height) {
                continue;
            }

            const coords = RectF.fromCoords(
                @intCast(x0),
                @intCast(y0),
                @intCast(charWidth),
                @intCast(charHeight),
                @intCast(image.width),
                @intCast(image.height),
            );

            try charsMap.put(char_code, Character{
                .coords = coords,
                .size = .{ .x = @intCast(charWidth), .y = @intCast(charHeight) },
                .bearing = .{ .x = 0, .y = @intCast(charHeight) }, // Assume top-left origin
                .advance = charWidth, // Fixed width
            });
            maxY = @max(maxY, @as(i32, @intCast(charHeight)));
        }

        return .{
            .chars = charsMap,
            .texture = Texture{
                .texture = charTex,
                .size = Vec2U{ .x = @as(u32, image.width), .y = @as(u32, image.height) },
                .src = RectF{ .l = 0, .t = 0, .r = 1, .b = 1 },
            },
            .maxY = maxY,
            .isAlpha = false,
        };
    }

    pub fn deinit(self: *FontAtlas) void {
        gl.deleteTextures(1, &self.texture.texture);
        self.chars.deinit();
    }
};
