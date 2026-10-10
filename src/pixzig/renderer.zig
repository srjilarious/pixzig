const std = @import("std");
const builtin = @import("builtin");

const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

pub const constants = @import("./renderer/constants.zig");
pub const quad_batch = @import("./renderer/quad_batch.zig");
pub const sprite_batch = @import("./renderer/sprite_batch.zig");
pub const stb_tt = @import("stb_truetype");

const textMod = @import("./renderer/text.zig");
const common = @import("./common.zig");
const resources = @import("./resources.zig");
const textures = @import("./renderer/textures.zig");
const shaders = @import("./renderer/shaders.zig");

const Sprite = @import("./renderer/sprites.zig").Sprite;
const Viewport = @import("./window.zig").Viewport;
const Camera2D = @import("./camera.zig").Camera2D;
const TextureHandle = resources.TextureHandle;
const Vec2I = common.Vec2I;
const white: common.Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Rotate = common.Rotate;
const Texture = textures.Texture;
const ResourceManager = resources.ResourceManager;
const Shader = shaders.Shader;
pub const FontAtlas = textMod.FontAtlas;
pub const FontFace = textMod.FontFace;
pub const Character = textMod.Character;
pub const FontMetrics = textMod.FontMetrics;
pub const measureFontFile = textMod.measureFontFile;
pub const measureFontFileIndexed = textMod.measureFontFileIndexed;
pub const findFaceIndexByName = textMod.findFaceIndexByName;

pub const QuadBatch = quad_batch.QuadBatch;
pub const StaticQuadBatch = quad_batch.StaticQuadBatch;
pub const BatchLayout = quad_batch.BatchLayout;
pub const SpriteBatch = sprite_batch.SpriteBatch;
pub const DrawMode = sprite_batch.DrawMode;
pub const TextRenderer = textMod.TextRenderer;

/// Comptime render options that allow us to compile out features we don't
/// need.  For example, if you don't need shape rendering, you can set
/// shapeRendering to false and the related code will not be included in the
///  final binary.
pub const RendererOptions = struct {
    shapeRendering: bool = true,
    /// Also gates the build-embedded default font: with this false its
    /// bytes are never referenced, so they stay out of the binary.
    textRendering: bool = true,

    /// Quad capacity of the renderer's batch. It auto-flushes once this many
    /// quads are queued, so a scene that draws more than this in one
    /// `begin`/`end` simply costs extra draw calls -- correctness is
    /// unaffected. Raise it for scenes that legitimately draw tens of
    /// thousands of quads per frame (e.g. a full character grid) to keep
    /// them in one draw call. The element indices are `u32`, so values well
    /// past 1M are safe.
    maxSprites: u32 = constants.MaxSprites,
};

/// Specifies the default font for the renderer.
pub const FontSource = union(enum) {
    /// The font `buildGame` embedded in the binary: Karla-Regular unless the
    /// build picked another `default_font`. With `default_font = .none`
    /// nothing is embedded and the renderer starts without a font.
    embedded: struct { size: f32 = 20.0 },
    /// `face` is the font file path; `faceIndex` selects a face inside a
    /// `.ttc` collection (0 for a plain font file).
    path: struct { face: [:0]const u8, size: f32 = 20.0, faceIndex: i32 = 0 },
    /// Raw TTF/OTF bytes, e.g. the game's own `@embedFile`. The atlas keeps
    /// its own copy, so `bytes` only has to live through init.
    data: struct { bytes: []const u8, size: f32 = 20.0, faceIndex: i32 = 0 },
    /// A font already loaded into the ResourceManager (e.g. a manifest boot group).
    id: []const u8,
    /// Start without a default font.
    none,
};

/// The bytes `buildGame` embedded as the default font, or null.
const embedded_default_font: ?[]const u8 = @import("pixzig_default_font").data;

/// The coordinate space a `Renderer.begin` pass draws in.
pub const Projection = union(enum) {
    /// The logical game resolution: (0,0)..(logicalW, logicalH), y down.
    /// The usual choice for game rendering.
    logical,
    /// Framebuffer pixels: (0,0)..(framebufferW, framebufferH), y down.
    /// For debug overlays that should be positioned in physical pixels.
    /// The pass covers the whole framebuffer, letterbox bars included;
    /// `end()` restores the letterboxed game viewport.
    screen,
    /// World space seen through a camera (see `Camera2D.matrix`).
    camera: *const Camera2D,
    /// A caller-built model-view-projection matrix.
    matrix: zmath.Mat,
};

/// Runtime initialization options for the renderer.
pub const RendererInitOpts = struct {
    font: FontSource = .{ .embedded = .{} },
};

/// A rendering interface that provides methods for drawing sprites, shapes
/// and writing text.
///
/// Every draw -- sprites (plain, tinted or filled), textures, shapes and
/// text -- queues into one `SpriteBatch`, so draws appear in the order they
/// are submitted. Consecutive draws from the same texture go out as one GL
/// call; switching texture flushes. Shapes all share a built-in white
/// texture, so a run of shapes is one call too.
pub fn Renderer(opts: RendererOptions) type {
    return struct {
        const Self = @This();

        /// Emits a compile error naming `flag` when a method needs a
        /// renderer feature that `opts` compiled out.
        inline fn requireFlag(comptime method: []const u8, comptime flag: []const u8) void {
            if (comptime !@field(opts, flag)) {
                @compileError("Renderer." ++ method ++ " requires RendererOptions." ++ flag ++
                    " = true (set EngineOptions.rendererOpts." ++ flag ++ ")");
            }
        }

        alloc: std.mem.Allocator,
        _impl: *align(@alignOf(Impl)) anyopaque,
        /// The engine's viewport, used to resolve `Projection` and clip
        /// rects. Owned by the engine, which outlives the renderer.
        viewport: *const Viewport,

        const Impl = struct {
            batch: SpriteBatch,
            /// Queues glyphs into `batch`. Only initialized with text
            /// rendering on.
            text: TextRenderer = undefined,

            /// True inside a `begin(.screen)` pass, which widens the GL
            /// viewport to the whole framebuffer until `end()`.
            screenPass: bool = false,
        };

        const DefaultFontName = "__pixzig_default_font";

        inline fn implMut(self: *Self) *Impl {
            return @ptrCast(self._impl);
        }

        inline fn implConst(self: *const Self) *const Impl {
            return @ptrCast(self._impl);
        }

        pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager, viewport: *const Viewport, initOpts: RendererInitOpts) !Self {
            var rend = try alloc.create(Impl);
            errdefer alloc.destroy(rend);
            rend.* = .{ .batch = undefined };

            std.log.info("Initializing shaders.", .{});
            const spriteShader = try resMgr.loadShader(shaders.SpriteShader, &shaders.SpriteVertexShader, &shaders.SpritePixelShader);
            // Not used by the renderer itself, but other engine renderers
            // (tile maps, grids) look these up by name.
            _ = try resMgr.loadShader(shaders.TextureShader, &shaders.TexVertexShader, &shaders.TexPixelShader);
            if (opts.shapeRendering) {
                _ = try resMgr.loadShader(shaders.ColorShader, &shaders.ColorVertexShader, &shaders.ColorPixelShader);
            }

            rend.batch = try SpriteBatch.initCapacity(alloc, spriteShader, opts.maxSprites);
            errdefer rend.batch.deinit();

            if (opts.textRendering) {
                std.log.info("Setting up text renderering.\n", .{});
                rend.text = TextRenderer.init(&rend.batch);

                switch (initOpts.font) {
                    .embedded => |e| {
                        if (embedded_default_font) |bytes| {
                            rend.text.setFont(try resMgr.loadFontFromTtfData(DefaultFontName, bytes, 0, e.size));
                        } else if (builtin.mode == .debug) {
                            std.log.warn("The build embedded no default font (default_font = .none). Text rendering will not work until a FontAtlas is set.", .{});
                        }
                    },
                    .path => |p| {
                        rend.text.setFont(try resMgr.loadFontFromTtfFileIndexed(DefaultFontName, p.face, p.faceIndex, p.size));
                    },
                    .data => |d| {
                        rend.text.setFont(try resMgr.loadFontFromTtfData(DefaultFontName, d.bytes, d.faceIndex, d.size));
                    },
                    .id => |id| {
                        rend.text.setFont(try resMgr.getFontAtlas(id));
                    },
                    .none => {},
                }
            }

            // set texture options
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
            gl.enable(gl.BLEND);
            gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

            return .{ .alloc = alloc, ._impl = rend, .viewport = viewport };
        }

        pub fn deinit(self: *Self) void {
            const impl = self.implMut();
            impl.batch.deinit();
            self.alloc.destroy(impl);
        }

        /// Set the renderer's default font to an already-loaded font in `resMgr`.
        /// Useful when the font is loaded post-init (e.g. via a manifest boot group).
        pub fn setDefaultFont(self: *Self, resMgr: *ResourceManager, id: []const u8) !void {
            requireFlag("setDefaultFont", "textRendering");
            self.implMut().text.setFont(try resMgr.getFontAtlas(id));
        }

        /// Appends a fallback face to the renderer's default font (the one
        /// loaded from `RendererInitOpts.font`). Codepoints the primary face
        /// lacks are then drawn from this face; anything no face provides
        /// falls back to the atlas's `.notdef` box. `faceIndex` selects a
        /// face inside a `.ttc`; use 0 for a plain font file.
        pub fn addDefaultFontFallback(self: *Self, resMgr: *ResourceManager, fontPath: []const u8, faceIndex: i32) !void {
            requireFlag("addDefaultFontFallback", "textRendering");
            _ = self;
            try resMgr.addFontFallback(DefaultFontName, fontPath, faceIndex);
        }

        /// The renderer's live default font atlas -- the one from
        /// `RendererInitOpts.font`, plus any faces added via
        /// `addDefaultFontFallback`. Null when text rendering is compiled
        /// out or no default font has been set.
        ///
        /// Returned by pointer so callers can drive the atlas directly, e.g.
        /// `atlas.setFontSize(pt)` to repack it at a new pixel size. Such a
        /// change is picked up by the next `drawString` with no re-`setFont`;
        /// make it outside a `begin`/`end` pair. Any size clamping/stepping
        /// is the caller's to apply.
        pub fn defaultFontAtlas(self: *Self) ?*FontAtlas {
            if (comptime !opts.textRendering) return null;
            const handle = self.implMut().text.font orelse return null;
            return &handle.val;
        }

        /// Testing hook for the renderer's one-shot "no default font" warning.
        /// This is intentionally narrow: tests can assert the public warning
        /// behavior without reaching into the renderer's private batching state.
        pub fn testingNoFontWarningIssued(self: *const Self) bool {
            requireFlag("testingNoFontWarningIssued", "textRendering");
            return self.implConst().text.warnedNoFont;
        }

        /// Starts a pass in the given coordinate space, e.g. `begin(.logical)`
        /// or `begin(.{ .camera = &cam })`. Pair with `end()`; draw calls
        /// between them are queued, and flushed when the texture changes,
        /// the batch fills, or at `end()`.
        pub fn begin(self: *Self, projection: Projection) void {
            const impl = self.implMut();
            const mvp = switch (projection) {
                .logical => self.viewport.projection(),
                .screen => self.viewport.applyFullscreen(),
                .camera => |cam| cam.matrix(self.viewport),
                .matrix => |m| m,
            };

            impl.screenPass = projection == .screen;
            impl.batch.begin(mvp);
        }

        /// Flushes whatever is still queued and closes the pass.
        pub fn end(self: *Self) void {
            const impl = self.implMut();
            impl.batch.end();

            if (impl.screenPass) {
                self.viewport.apply();
                impl.screenPass = false;
            }
        }

        /// Flushes queued draws, so draws made before a GL state change
        /// (scissor, blend mode, ...) render under the old state.
        pub fn flush(self: *Self) void {
            self.implMut().batch.flush();
        }

        /// Clips subsequent draws to `rect`, given in logical coordinates
        /// (clamped to the logical screen). `null` restores the pass's own
        /// clip: the letterboxed viewport, or the whole framebuffer inside a
        /// `.screen` pass. Queued draws are flushed first, so they keep the
        /// previous clip.
        pub fn setClip(self: *Self, rect: ?RectF) void {
            self.flush();
            const r = rect orelse {
                if (self.implMut().screenPass) {
                    _ = self.viewport.applyFullscreen();
                } else {
                    self.viewport.apply();
                }
                return;
            };

            const vp = self.viewport;
            const logical_w: f32 = @floatFromInt(vp.logicalSize.x);
            const logical_h: f32 = @floatFromInt(vp.logicalSize.y);
            const l = std.math.clamp(r.l, 0.0, logical_w);
            const t = std.math.clamp(r.t, 0.0, logical_h);
            const right = std.math.clamp(r.r, l, logical_w);
            const b = std.math.clamp(r.b, t, logical_h);
            const top_left = vp.logicalToFramebuffer(.{ .x = l, .y = t });
            const bottom_right = vp.logicalToFramebuffer(.{ .x = right, .y = b });
            const left_px: i32 = @intFromFloat(top_left.x);
            const top_px: i32 = @intFromFloat(top_left.y);
            const right_px: i32 = @intFromFloat(bottom_right.x);
            const bottom_px: i32 = @intFromFloat(bottom_right.y);
            gl.enable(gl.SCISSOR_TEST);
            gl.scissor(
                left_px,
                vp.framebufferSize.y - bottom_px,
                @max(0, right_px - left_px),
                @max(0, bottom_px - top_px),
            );
        }

        /// Clears the color buffer (inside the current scissor) to a 0-255
        /// color.
        pub fn clear(self: *const Self, r: u8, g: u8, b: u8, a: u8) void {
            _ = self;
            const c = Color.from(r, g, b, a);
            gl.clearColor(c.r, c.g, c.b, c.a);
            gl.clear(gl.COLOR_BUFFER_BIT);
        }

        /// Draws a `Sprite`: as a silhouette when `sprite.fill` is set (see
        /// `drawSpriteFilled`), otherwise multiplied by `sprite.tint` when set
        /// (see `drawSpriteColored`), otherwise plain.
        pub fn drawSprite(self: *Self, sprite: *const Sprite) void {
            self.implMut().batch.drawSprite(sprite);
        }

        /// Draws a `Sprite` multiplied by `color` (a straight per-channel
        /// multiply, so alpha < 1 fades it and rgb < 1 darkens/tints it).
        pub fn drawSpriteColored(self: *Self, sprite: *const Sprite, color: Color) void {
            self.implMut().batch.drawSpriteAs(sprite, color, .texture);
        }

        /// Draws a `Sprite` as a silhouette: every texel's rgb is replaced
        /// by `color.rgb` (blended by `color.a`, 1 = solid) while the
        /// texture's own alpha is kept, so the sprite's shape is filled with
        /// a flat colour. Handy for hit flashes.
        pub fn drawSpriteFilled(self: *Self, sprite: *const Sprite, color: Color) void {
            self.implMut().batch.drawSpriteAs(sprite, color, .fill);
        }

        /// Draws the `srcCoords` region (UVs of the underlying image) of
        /// `texture` into `dest`.
        pub fn drawTexture(self: *Self, texture: *TextureHandle, dest: RectF, srcCoords: RectF) void {
            self.implMut().batch.draw(&texture.val, dest, srcCoords, .none, white, .texture);
        }

        /// Draws the whole texture (frame) at `pos`, scaled uniformly by `scale`.
        pub fn drawFullTexture(self: *Self, texture: *TextureHandle, pos: Vec2I, scale: f32) void {
            const tex = &texture.val;
            const tsx = @as(f32, @floatFromInt(tex.size.x)) * scale;
            const tsy = @as(f32, @floatFromInt(tex.size.y)) * scale;
            const dest = RectF.fromPosSize(pos.x, pos.y, @intFromFloat(tsx), @intFromFloat(tsy));
            self.implMut().batch.draw(tex, dest, tex.src, .none, white, .texture);
        }

        /// Requires `RendererOptions.shapeRendering == true`; calling it with
        /// shape rendering compiled out is a compile error.
        pub fn drawFilledRect(self: *Self, dest: RectF, color: Color) void {
            requireFlag("drawFilledRect", "shapeRendering");
            self.implMut().batch.drawFilledRect(dest, color);
        }

        /// Draws the outline of `dest`, `lineWidth` pixels thick, inside it.
        /// Requires `RendererOptions.shapeRendering == true`; see `drawFilledRect()`.
        pub fn drawRect(self: *Self, dest: RectF, color: Color, lineWidth: u8) void {
            requireFlag("drawRect", "shapeRendering");
            self.implMut().batch.drawRect(dest, color, lineWidth);
        }

        /// Like `drawRect`, but the outline sits outside `dest`, enclosing it.
        /// Requires `RendererOptions.shapeRendering == true`; see `drawFilledRect()`.
        pub fn drawEnclosingRect(self: *Self, dest: RectF, color: Color, lineWidth: u8) void {
            requireFlag("drawEnclosingRect", "shapeRendering");
            self.implMut().batch.drawEnclosingRect(dest, color, lineWidth);
        }

        /// Requires `RendererOptions.textRendering == true`; calling it with
        /// text rendering compiled out is a compile error. Draws nothing (and
        /// logs an error) if no default font has been set (see `setDefaultFont`).
        pub fn drawString(self: *Self, text: []const u8, pos: Vec2I) Vec2I {
            requireFlag("drawString", "textRendering");
            return self.implMut().text.drawString(text, pos);
        }

        /// Requires `RendererOptions.textRendering == true`; see `drawString()`.
        pub fn drawScaledString(self: *Self, text: []const u8, pos: Vec2I, scale: f32) Vec2I {
            requireFlag("drawScaledString", "textRendering");
            return self.implMut().text.drawScaledString(text, pos, scale);
        }

        /// Like `drawString`, but tints every glyph by `color` instead of
        /// rendering plain white. Requires `RendererOptions.textRendering == true`.
        pub fn drawStringColored(self: *Self, text: []const u8, pos: Vec2I, color: Color) Vec2I {
            requireFlag("drawStringColored", "textRendering");
            return self.implMut().text.drawStringColored(text, pos, color);
        }

        /// Like `drawString`, but only the parts of glyphs inside `clip` are
        /// drawn (edge glyphs are trimmed, not dropped). Requires
        /// `RendererOptions.textRendering == true`.
        pub fn drawClippedString(self: *Self, text: []const u8, pos: Vec2I, clip: RectF) Vec2I {
            requireFlag("drawClippedString", "textRendering");
            return self.implMut().text.drawClippedString(text, pos, clip);
        }

        /// The default font's line height in pixels, or null when no font is
        /// set. Requires `RendererOptions.textRendering == true`.
        pub fn lineHeight(self: *const Self) ?i32 {
            requireFlag("lineHeight", "textRendering");
            const font = self.implConst().text.font orelse return null;
            return font.val.maxY;
        }

        /// Measures `text` without drawing it. Requires `RendererOptions.textRendering == true`.
        pub fn measureString(self: *Self, text: []const u8) Vec2I {
            requireFlag("measureString", "textRendering");
            return self.implMut().text.measureString(text);
        }
    };
}
