const std = @import("std");
const builtin = @import("builtin");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");
pub const stb_tt = @import("stb_truetype");

const common = @import("../common.zig");
const resources = @import("../resources.zig");
const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Texture = textures.Texture;
const Shader = shaders.Shader;
const ResourceManager = resources.ResourceManager;
const SpriteBatchQueue = @import("./sprite_batch.zig").SpriteBatchQueue;

pub const Character = struct { coords: RectF, size: Vec2I, bearing: Vec2I, advance: i32 };

fn scaleInt(value: i32, scale: f32) i32 {
    return @as(i32, @intFromFloat(@as(f32, @floatFromInt(value)) * scale));
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
        // Pack font using STB_TrueType
        var pack_context = stb_tt.c.stbtt_pack_context{};
        const GlyphBufferWidth = 2048;
        const GlyphBufferHeight = 1024;
        const glyphBuffer = try alloc.alloc(u8, GlyphBufferWidth * GlyphBufferHeight);
        defer alloc.free(glyphBuffer);
        @memset(glyphBuffer, 0); // Initialize to black

        // Pack ASCII printable characters (32-126)
        const num_chars = 126 - 32;
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

    // Alternative init function that loads from file path (for non-WASM)
    pub fn initFromTtfFile(fontPath: []const u8, fontSize: f32, alloc: std.mem.Allocator) !FontAtlas {
        const fontData = try std.fs.cwd().readFileAlloc(alloc, fontPath, std.math.maxInt(usize));
        defer alloc.free(fontData);

        return initFromTtf(fontData, fontSize, alloc);
    }

    // Alternative init function for embedded fonts (WASM-friendly)
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
        gl.bindTexture(gl.TEXTURE_2D, charTex);

        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @intCast(image.width), @intCast(image.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, image.data.ptr);

        // Set texture parameters for crisp text rendering
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

        var charsMap = std.AutoHashMap(u32, Character).init(alloc);
        var maxY: i32 = 0;

        for (0..chars.len) |i| {
            const char_code = chars[i];
            const col = i % charsPerRow;
            const row = i / charsPerRow;

            const x0 = col * charWidth;
            const y0 = row * charHeight;

            // Skip characters that would be out of bounds
            if (x0 + charWidth > @as(u32, image.width) or y0 + charHeight > @as(u32, image.height)) {
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
        gl.deleteTextures(1, &self.tex.texture);
        self.characters.deinit();
    }
};

pub const TextRenderer = struct {
    spriteBatch: SpriteBatchQueue,
    alphaTexShader: *const Shader,
    texShader: *const Shader,
    alloc: std.mem.Allocator,
    atlas: ?*FontAtlas,

    pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager) !TextRenderer {
        const texShader = try resMgr.getShaderByName(shaders.TextureShader);
        const spriteBatch = try SpriteBatchQueue.init(alloc, texShader);

        return TextRenderer{
            .alloc = alloc,
            .spriteBatch = spriteBatch,
            .alphaTexShader = try resMgr.getShaderByName(shaders.FontShader),
            .texShader = texShader,
            .atlas = null,
        };
    }

    pub fn deinit(self: *TextRenderer) void {
        self.spriteBatch.deinit();
    }

    pub fn begin(self: *TextRenderer, mvp: zmath.Mat, atlas: ?*FontAtlas) void {
        if (atlas != null) {
            self.atlas = atlas;
        }

        //self.tex = atlas.tex;
        self.spriteBatch.begin(mvp);
    }

    pub fn end(self: *TextRenderer) void {
        self.spriteBatch.end();
    }

    pub fn setAtlas(self: *TextRenderer, atlas: *FontAtlas) void {
        self.atlas = atlas;
        if (atlas.isAlpha) {
            self.spriteBatch.shader = self.alphaTexShader;
        } else {
            self.spriteBatch.shader = self.texShader;
        }
    }

    pub fn drawString(self: *TextRenderer, text: []const u8, pos: Vec2I) Vec2I {
        var currX: i32 = pos.x;

        var drawSize: Vec2I = .{ .x = 0, .y = 0 };

        if (self.atlas == null) {
            std.log.err("TextRenderer: No FontAtlas set. Cannot draw text.", .{});
            return drawSize;
        }

        const posY = pos.y + self.atlas.?.maxY;
        for (text) |c| {
            const charDataPtr = self.atlas.?.chars.get(@intCast(c));
            if (charDataPtr == null) continue;

            const charData = charDataPtr.?;

            // Only draw if character has visual representation
            if (charData.size.x > 0 and charData.size.y > 0) {
                self.spriteBatch.draw(&self.atlas.?.texture, RectF.fromPosSize(currX + charData.bearing.x, posY - charData.bearing.y, charData.size.x, charData.size.y), charData.coords, .none);
            }

            currX += @intCast(charData.advance);
            drawSize.x += @intCast(charData.advance);
            drawSize.y = @max(drawSize.y, charData.size.y);
        }

        return drawSize;
    }

    pub fn drawScaledString(self: *TextRenderer, text: []const u8, pos: Vec2I, scale: f32) Vec2I {
        var currX: i32 = pos.x;

        var drawSize: Vec2I = .{ .x = 0, .y = 0 };

        if (self.atlas == null) {
            std.log.err("TextRenderer: No FontAtlas set. Cannot draw text.", .{});
            return drawSize;
        }

        const posY = pos.y + scaleInt(self.atlas.?.maxY, scale);
        for (text) |c| {
            const charDataPtr = self.atlas.?.chars.get(@intCast(c));
            if (charDataPtr == null) continue;

            const charData = charDataPtr.?;

            // Only draw if character has visual representation
            if (charData.size.x > 0 and charData.size.y > 0) {
                self.spriteBatch.draw(
                    &self.atlas.?.texture,
                    RectF.fromPosSize(
                        currX + scaleInt(charData.bearing.x, scale),
                        posY - scaleInt(charData.bearing.y, scale),
                        scaleInt(charData.size.x, scale),
                        scaleInt(charData.size.y, scale),
                    ),
                    charData.coords,
                    .none,
                );
            }

            const advanceScale = scaleInt(charData.advance, scale);
            currX += advanceScale;
            drawSize.x += advanceScale;
            drawSize.y = @max(drawSize.y, scaleInt(charData.size.y, scale));
        }

        return drawSize;
    }

    // Helper function to measure text without drawing
    pub fn measureString(self: *TextRenderer, text: []const u8) Vec2I {
        var width: i32 = 0;
        var height: i32 = 0;

        for (text) |c| {
            const charDataPtr = self.atlas.chars.get(@intCast(c));
            if (charDataPtr == null) continue;

            const charData = charDataPtr.?;
            width += @intCast(charData.advance);
            height = @max(height, charData.size.y);
        }

        return Vec2I{ .x = width, .y = height };
    }
};
