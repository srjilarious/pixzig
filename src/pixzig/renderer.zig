const std = @import("std");
const builtin = @import("builtin");

const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

pub const constants = @import("./renderer/constants.zig");
pub const quad_batch = @import("./renderer/quad_batch.zig");
pub const sprite_batch = @import("./renderer/sprite_batch.zig");
pub const shape = @import("./renderer/shape.zig");
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
pub const SpriteBatchQueue = sprite_batch.SpriteBatchQueue;
pub const ShapeBatchQueue = shape.ShapeBatchQueue;
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

    /// Quad capacity of every batch queue (sprite, overlay, shape, and the
    /// two text batches). A batch auto-flushes once this many quads are
    /// queued, so a scene that draws more than this in one `begin`/`end`
    /// simply costs extra draw calls -- correctness is unaffected. Raise it
    /// for scenes that legitimately draw tens of thousands of quads per
    /// frame (e.g. a full character grid) to keep them in one draw call.
    /// The element indices are `u32`, so values well past 1M are safe.
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
/// Draws appear in the order they are submitted. Each kind of draw (plain
/// sprites, tinted sprites, shapes, text, colored text) queues into its own
/// batch, and switching to a different kind flushes the previous batch
/// first. Runs of the same kind (and texture) still coalesce into one GL
/// call, so group similar draws together when order doesn't matter.
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
        impl: *Impl,
        /// The engine's viewport, used to resolve `Projection` and clip
        /// rects. Owned by the engine, which outlives the renderer.
        viewport: *const Viewport,

        /// Which batch holds the queued-but-unflushed draws.
        const BatchKind = enum { none, sprites, tinted, shapes, text, text_colored };

        const Impl = struct {
            sprites: SpriteBatchQueue,
            /// Dedicated sprite batch bound to `TintTextureShader`, used by
            /// `drawSpriteColored` so the plain sprite path stays on the
            /// untinted `TextureShader` program.
            tinted: SpriteBatchQueue,

            shapes: ShapeBatchQueue = undefined,
            text: TextRenderer = undefined,

            /// The batch the last draw went to. A draw to any other batch
            /// flushes this one first, which keeps submission order.
            active: BatchKind = .none,
        };

        const DefaultFontName = "__pixzig_default_font";

        pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager, viewport: *const Viewport, initOpts: RendererInitOpts) !Self {
            var rend = try alloc.create(Impl);
            errdefer alloc.destroy(rend);

            // Tracks exactly which fields of `rend` are live so a later
            // failure unwinds only what actually got initialized, in
            // reverse construction order.
            var spritesInit = false;
            var tintedInit = false;
            var shapesInit = false;
            var textInit = false;
            errdefer {
                if (textInit) rend.text.deinit();
                if (shapesInit) rend.shapes.deinit();
                if (tintedInit) rend.tinted.deinit();
                if (spritesInit) rend.sprites.deinit();
            }

            std.log.info("Initializing shaders.", .{});
            const texShader = try resMgr.loadShader(shaders.TextureShader, &shaders.TexVertexShader, &shaders.TexPixelShader);
            const tintShader = try resMgr.loadShader(shaders.TintTextureShader, &shaders.TexVertexShader, &shaders.TexTintPixelShader);

            rend.active = .none;
            rend.sprites = try SpriteBatchQueue.initCapacity(alloc, texShader, opts.maxSprites);
            spritesInit = true;
            rend.tinted = try SpriteBatchQueue.initCapacity(alloc, tintShader, opts.maxSprites);
            tintedInit = true;

            if (opts.shapeRendering) {
                std.log.info("Setting up shaders for shape renderering.", .{});
                const colorShader = try resMgr.loadShader(shaders.ColorShader, &shaders.ColorVertexShader, &shaders.ColorPixelShader);
                rend.shapes = try ShapeBatchQueue.initCapacity(alloc, colorShader, opts.maxSprites);
                shapesInit = true;
            }

            if (opts.textRendering) {
                std.log.info("Setting up text renderering.\n", .{});

                if (builtin.os.tag == .emscripten) {
                    _ = try resMgr.loadShader(shaders.FontShader, &shaders.TexVertexShader, &shaders.TextPixelShader_Web);
                    _ = try resMgr.loadShader(shaders.TextColorShader, &shaders.TextColorVertexShader, &shaders.TextColorPixelShader_Web);
                } else {
                    _ = try resMgr.loadShader(shaders.FontShader, &shaders.TexVertexShader, &shaders.TextPixelShader_Desktop);
                    _ = try resMgr.loadShader(shaders.TextColorShader, &shaders.TextColorVertexShader, &shaders.TextColorPixelShader_Desktop);
                }

                rend.text = try TextRenderer.initCapacity(alloc, resMgr, opts.maxSprites);
                textInit = true;

                switch (initOpts.font) {
                    .embedded => |e| {
                        if (embedded_default_font) |bytes| {
                            try rend.text.setFont(try resMgr.loadFontFromTtfData(DefaultFontName, bytes, 0, e.size));
                        } else if (builtin.mode == .debug) {
                            std.log.warn("The build embedded no default font (default_font = .none). Text rendering will not work until a FontAtlas is set.", .{});
                        }
                    },
                    .path => |p| {
                        try rend.text.setFont(try resMgr.loadFontFromTtfFileIndexed(DefaultFontName, p.face, p.faceIndex, p.size));
                    },
                    .data => |d| {
                        try rend.text.setFont(try resMgr.loadFontFromTtfData(DefaultFontName, d.bytes, d.faceIndex, d.size));
                    },
                    .id => |id| {
                        try rend.text.setFont(try resMgr.getFontAtlas(id));
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

            return .{ .alloc = alloc, .impl = rend, .viewport = viewport };
        }

        pub fn deinit(self: *Self) void {
            self.impl.sprites.deinit();
            self.impl.tinted.deinit();
            if (opts.shapeRendering) {
                self.impl.shapes.deinit();
            }

            if (opts.textRendering) {
                self.impl.text.deinit();
            }

            self.alloc.destroy(self.impl);
        }

        /// Set the renderer's default font to an already-loaded font in `resMgr`.
        /// Useful when the font is loaded post-init (e.g. via a manifest boot group).
        pub fn setDefaultFont(self: *Self, resMgr: *ResourceManager, id: []const u8) !void {
            requireFlag("setDefaultFont", "textRendering");
            try self.impl.text.setFont(try resMgr.getFontAtlas(id));
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
            const handle = self.impl.text.font orelse return null;
            return &handle.val;
        }

        /// Starts a pass: opens the sprite batches (plus shape/text batches
        /// if enabled) in the given coordinate space, e.g. `begin(.logical)`
        /// or `begin(.{ .camera = &cam })`. Pair with `end()`; draw calls
        /// between them are buffered, and flushed when the next draw needs a
        /// different batch or at `end()`.
        pub fn begin(self: *Self, projection: Projection) void {
            const mvp = switch (projection) {
                .logical => self.viewport.projection(),
                .screen => blk: {
                    const fw: f32 = @floatFromInt(self.viewport.framebufferSize.x);
                    const fh: f32 = @floatFromInt(self.viewport.framebufferSize.y);
                    break :blk zmath.orthographicOffCenterLhGl(0, fw, 0, fh, -0.1, 1000);
                },
                .camera => |cam| cam.matrix(self.viewport),
                .matrix => |m| m,
            };

            self.impl.active = .none;
            self.impl.sprites.begin(mvp);
            self.impl.tinted.begin(mvp);

            if (opts.shapeRendering) {
                self.impl.shapes.begin(mvp);
            }

            if (opts.textRendering) {
                self.impl.text.begin(mvp);
            }
        }

        /// Flushes whatever is still queued and closes every batch. Only the
        /// active batch can hold draws at this point, so the others' `end`
        /// just closes them.
        pub fn end(self: *Self) void {
            self.impl.sprites.end();
            self.impl.tinted.end();

            if (opts.shapeRendering) {
                self.impl.shapes.end();
            }

            if (opts.textRendering) {
                self.impl.text.end();
            }
            self.impl.active = .none;
        }

        /// Makes `kind` the batch receiving draws, flushing the previously
        /// active batch if it was a different one so earlier draws land
        /// underneath later ones.
        fn use(self: *Self, kind: BatchKind) void {
            if (self.impl.active == kind) return;
            switch (self.impl.active) {
                .none => {},
                .sprites => self.impl.sprites.flush(),
                .tinted => self.impl.tinted.flush(),
                .shapes => if (comptime opts.shapeRendering) self.impl.shapes.flush(),
                .text, .text_colored => if (comptime opts.textRendering) self.impl.text.flush(),
            }
            self.impl.active = kind;
        }

        /// Flushes queued draws, so draws made before a GL state change
        /// (scissor, blend mode, ...) render under the old state.
        pub fn flush(self: *Self) void {
            self.use(.none);
        }

        /// Clips subsequent draws to `rect`, given in logical coordinates
        /// (clamped to the logical screen). `null` restores the viewport's
        /// own clip. Queued draws are flushed first, so they keep the
        /// previous clip.
        pub fn setClip(self: *Self, rect: ?RectF) void {
            self.flush();
            const r = rect orelse {
                self.viewport.apply();
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

        /// Draws a `Sprite`. When `sprite.tint` is set this routes to the
        /// tinted batch (see `drawSpriteColored`); otherwise it goes to the
        /// plain sprite batch.
        pub fn drawSprite(self: *Self, sprite: *const Sprite) void {
            if (sprite.tint) |color| {
                self.drawSpriteColored(sprite, color);
                return;
            }
            self.use(.sprites);
            self.impl.sprites.drawSprite(sprite);
        }

        /// Draws a `Sprite` multiplied by `color` (a straight per-channel
        /// multiply, so alpha < 1 fades it and rgb < 1 darkens/tints it).
        /// Submits to a separate batch bound to `TintTextureShader`; runs of
        /// same-colour draws still coalesce into one GL call.
        pub fn drawSpriteColored(self: *Self, sprite: *const Sprite, color: Color) void {
            self.use(.tinted);
            self.impl.tinted.setTint(color.r, color.g, color.b, color.a);
            self.impl.tinted.drawSprite(sprite);
        }

        /// Draws the `srcCoords` region (UVs of the underlying image) of
        /// `texture` into `dest`. Takes a borrowed or acquired handle alike.
        pub fn drawTexture(self: *Self, texture: *TextureHandle, dest: RectF, srcCoords: RectF) void {
            self.use(.sprites);
            self.impl.sprites.draw(&texture.val, dest, srcCoords, .none);
        }

        /// Draws the whole texture (frame) at `pos`, scaled uniformly by `scale`.
        pub fn drawFullTexture(self: *Self, texture: *TextureHandle, pos: Vec2I, scale: f32) void {
            const tex = &texture.val;
            const tsx = @as(f32, @floatFromInt(tex.size.x)) * scale;
            const tsy = @as(f32, @floatFromInt(tex.size.y)) * scale;
            self.use(.sprites);
            self.impl.sprites.draw(tex, RectF.fromPosSize(pos.x, pos.y, @intFromFloat(tsx), @intFromFloat(tsy)), tex.src, .none);
        }

        /// Requires `RendererOptions.shapeRendering == true`; calling it with
        /// shape rendering compiled out is a compile error.
        pub fn drawFilledRect(self: *Self, dest: RectF, color: Color) void {
            requireFlag("drawFilledRect", "shapeRendering");
            self.use(.shapes);
            self.impl.shapes.drawFilledRect(dest, color);
        }

        /// Requires `RendererOptions.shapeRendering == true`; see `drawFilledRect()`.
        pub fn drawRect(self: *Self, dest: RectF, color: Color, lineWidth: u8) void {
            requireFlag("drawRect", "shapeRendering");
            self.use(.shapes);
            self.impl.shapes.drawRect(dest, color, lineWidth);
        }

        // This moves the outline of the rect to enclose the dest by lineWidth.
        /// Requires `RendererOptions.shapeRendering == true`; see `drawFilledRect()`.
        pub fn drawEnclosingRect(self: *Self, dest: RectF, color: Color, lineWidth: u8) void {
            requireFlag("drawEnclosingRect", "shapeRendering");
            self.use(.shapes);
            self.impl.shapes.drawEnclosingRect(dest, color, lineWidth);
        }

        /// Requires `RendererOptions.textRendering == true`; calling it with
        /// text rendering compiled out is a compile error. Draws nothing (and
        /// logs an error) if no default font has been set (see `setDefaultFont`).
        pub fn drawString(self: *Self, text: []const u8, pos: Vec2I) Vec2I {
            requireFlag("drawString", "textRendering");
            self.use(.text);
            return self.impl.text.drawString(text, pos);
        }

        /// Requires `RendererOptions.textRendering == true`; see `drawString()`.
        pub fn drawScaledString(self: *Self, text: []const u8, pos: Vec2I, scale: f32) Vec2I {
            requireFlag("drawScaledString", "textRendering");
            self.use(.text);
            return self.impl.text.drawScaledString(text, pos, scale);
        }

        /// Like `drawString`, but tints every glyph by `color` instead of
        /// rendering plain white. Requires `RendererOptions.textRendering == true`.
        pub fn drawStringColored(self: *Self, text: []const u8, pos: Vec2I, color: Color) Vec2I {
            requireFlag("drawStringColored", "textRendering");
            self.use(.text_colored);
            return self.impl.text.drawStringColored(text, pos, color);
        }

        /// Like `drawString`, but only the parts of glyphs inside `clip` are
        /// drawn (edge glyphs are trimmed, not dropped). Requires
        /// `RendererOptions.textRendering == true`.
        pub fn drawClippedString(self: *Self, text: []const u8, pos: Vec2I, clip: RectF) Vec2I {
            requireFlag("drawClippedString", "textRendering");
            self.use(.text);
            return self.impl.text.drawClippedString(text, pos, clip);
        }

        /// The default font's line height in pixels, or null when no font is
        /// set. Requires `RendererOptions.textRendering == true`.
        pub fn lineHeight(self: *const Self) ?i32 {
            requireFlag("lineHeight", "textRendering");
            const font = self.impl.text.font orelse return null;
            return font.val.maxY;
        }

        /// Measures `text` without drawing it. Requires `RendererOptions.textRendering == true`.
        pub fn measureString(self: *Self, text: []const u8) Vec2I {
            requireFlag("measureString", "textRendering");
            return self.impl.text.measureString(text);
        }
    };
}
