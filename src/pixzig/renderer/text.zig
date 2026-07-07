const std = @import("std");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

const common = @import("../common.zig");
const resources = @import("../resources.zig");
const shaders = @import("./shaders.zig");
const font_atlas = @import("./font_atlas.zig");

const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Shader = shaders.Shader;
const ResourceManager = resources.ResourceManager;
const SpriteBatchQueue = @import("./sprite_batch.zig").SpriteBatchQueue;

pub const FontAtlas = font_atlas.FontAtlas;
pub const Character = font_atlas.Character;
pub const stb_tt = font_atlas.stb_tt;

fn scaleInt(value: i32, scale: f32) i32 {
    return @as(i32, @intFromFloat(@as(f32, @floatFromInt(value)) * scale));
}

pub const TextRenderer = struct {
    spriteBatch: SpriteBatchQueue,
    /// Pool refs (not pre-acquired handles) so setFont can swap the active
    /// shader on the underlying batch via swapShader. The batch itself owns
    /// whichever handle is currently in use.
    alphaShader: *resources.ManagedShader,
    texShader: *resources.ManagedShader,
    alloc: std.mem.Allocator,
    /// Active font handle. Released in deinit. The parent back-pointer is
    /// used to reacquire after a hot-reload without re-doing the name lookup.
    font: ?*resources.FontAtlasHandle,

    pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager) !TextRenderer {
        const texShader = try resMgr.getShader(shaders.TextureShader);
        const alphaShader = try resMgr.getShader(shaders.FontShader);
        var spriteBatch = try SpriteBatchQueue.init(alloc, texShader);
        errdefer spriteBatch.deinit();

        return TextRenderer{
            .alloc = alloc,
            .spriteBatch = spriteBatch,
            .alphaShader = alphaShader,
            .texShader = texShader,
            .font = null,
        };
    }

    pub fn deinit(self: *TextRenderer) void {
        if (self.font) |h| h.release();
        self.spriteBatch.deinit();
    }

    fn refreshAtlas(self: *TextRenderer) void {
        const handle = self.font orelse return;
        if (!handle.dirty) return;
        self.font = handle.reacquire();
    }

    pub fn begin(self: *TextRenderer, mvp: zmath.Mat) void {
        self.spriteBatch.begin(mvp);
    }

    pub fn end(self: *TextRenderer) void {
        self.spriteBatch.end();
    }

    /// Flushes queued text while keeping the renderer open for further draws.
    pub fn flush(self: *TextRenderer) void {
        self.spriteBatch.flush();
    }

    /// Adopt a new font for rendering. Releases any previously held handle,
    /// acquires ownership of a new handle, and swaps the underlying batch's
    /// shader to the alpha-channel program when the atlas was packed as
    /// alpha, or the regular texture program otherwise.
    pub fn setFont(
        self: *TextRenderer,
        font: *resources.ManagedFont,
    ) !void {
        if (self.font) |h| h.release();
        self.font = font.acquire();

        const shader = if (self.font.?.val.isAlpha) self.alphaShader else self.texShader;
        try self.spriteBatch.swapShader(shader);
    }

    pub fn drawString(self: *TextRenderer, text: []const u8, pos: Vec2I) Vec2I {
        var currX: i32 = pos.x;

        var drawSize: Vec2I = .{ .x = 0, .y = 0 };

        if (self.font == null) {
            std.log.err("TextRenderer: No Font set. Cannot draw text.", .{});
            return drawSize;
        }

        const posY = pos.y + self.font.?.val.maxY;
        for (text) |c| {
            const charDataPtr = self.font.?.val.chars.get(@intCast(c));
            if (charDataPtr == null) continue;

            const charData = charDataPtr.?;

            // Only draw if character has visual representation
            if (charData.size.x > 0 and charData.size.y > 0) {
                self.spriteBatch.draw(&self.font.?.val.texture, RectF.fromPosSize(currX + charData.bearing.x, posY - charData.bearing.y, charData.size.x, charData.size.y), charData.coords, .none);
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

        if (self.font == null) {
            std.log.err("TextRenderer: No Font set. Cannot draw text.", .{});
            return drawSize;
        }

        const posY = pos.y + scaleInt(self.font.?.val.maxY, scale);
        for (text) |c| {
            const charDataPtr = self.font.?.val.chars.get(@intCast(c));
            if (charDataPtr == null) continue;

            const charData = charDataPtr.?;

            // Only draw if character has visual representation
            if (charData.size.x > 0 and charData.size.y > 0) {
                self.spriteBatch.draw(
                    &self.font.?.val.texture,
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

    // Like drawString but clips character quads to `clip` in screen space.
    // Partially-visible edge characters have their source UV rect trimmed to
    // match so no bleed from adjacent font glyphs appears.
    pub fn drawClippedString(self: *TextRenderer, text: []const u8, pos: Vec2I, clip: RectF) Vec2I {
        var currX: i32 = pos.x;
        var drawSize: Vec2I = .{ .x = 0, .y = 0 };

        if (self.font == null) {
            std.log.err("TextRenderer: No Font set. Cannot draw text.", .{});
            return drawSize;
        }

        const posY = pos.y + self.font.?.val.maxY;
        for (text) |c| {
            const charDataPtr = self.font.?.val.chars.get(@intCast(c));
            if (charDataPtr == null) continue;

            const charData = charDataPtr.?;

            if (charData.size.x > 0 and charData.size.y > 0) {
                var dest = RectF.fromPosSize(
                    currX + charData.bearing.x,
                    posY - charData.bearing.y,
                    charData.size.x,
                    charData.size.y,
                );
                var src = charData.coords;

                // Entirely left of clip — advance cursor but don't draw.
                if (dest.r <= clip.l) {
                    currX += @intCast(charData.advance);
                    drawSize.x += @intCast(charData.advance);
                    continue;
                }
                // Entirely right of clip — nothing further will be visible.
                if (dest.l >= clip.r) break;

                const uv_per_px = (src.r - src.l) / dest.width();

                if (dest.l < clip.l) {
                    src.l += (clip.l - dest.l) * uv_per_px;
                    dest.l = clip.l;
                }
                if (dest.r > clip.r) {
                    src.r -= (dest.r - clip.r) * uv_per_px;
                    dest.r = clip.r;
                }

                self.spriteBatch.draw(&self.font.?.val.texture, dest, src, .none);
            }

            currX += @intCast(charData.advance);
            drawSize.x += @intCast(charData.advance);
            drawSize.y = @max(drawSize.y, charData.size.y);
        }

        return drawSize;
    }

    // Helper function to measure text without drawing
    pub fn measureString(self: *TextRenderer, text: []const u8) Vec2I {
        var width: i32 = 0;
        var height: i32 = 0;

        for (text) |c| {
            const charDataPtr = self.font.?.val.chars.get(@intCast(c));
            if (charDataPtr == null) continue;

            const charData = charDataPtr.?;
            width += @intCast(charData.advance);
            height = @max(height, charData.size.y);
        }

        return Vec2I{ .x = width, .y = height };
    }
};
