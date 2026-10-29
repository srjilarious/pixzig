const std = @import("std");
const builtin = @import("builtin");

const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

pub const constants = @import("./renderer/constants.zig");
pub const quad_batch = @import("./renderer/quad_batch.zig");
pub const sprite_batch = @import("./renderer/sprite_batch.zig");
pub const render_target = @import("./renderer/render_target.zig");
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
const ShaderHandle = resources.ShaderHandle;
const Vec2F = common.Vec2F;
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
pub const RenderTarget = render_target.RenderTarget;
pub const RenderTargetOptions = render_target.RenderTargetOptions;
pub const TargetFilter = render_target.TargetFilter;
pub const TextStyle = textMod.TextStyle;
pub const TextAlign = textMod.TextAlign;

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

/// How a draw's color combines with what is already there.
pub const BlendMode = enum {
    /// Normal transparency: the draw covers what's behind by its alpha.
    alpha,
    /// Adds the draw's color (scaled by its alpha), brightening what's
    /// behind. Glows, fire, lasers, light.
    additive,
    /// Multiplies what's behind by the draw's color, darkening it. Shadows,
    /// tinting a scene.
    multiply,
    /// Like `alpha`, for colors already multiplied by their alpha. Use it
    /// to draw a `RenderTarget` that was cleared transparent, whose
    /// edges otherwise come out dark.
    premultiplied,
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

            /// Where draws go instead of the screen (see `setTarget`).
            target: ?*RenderTarget = null,
            /// The framebuffer that was bound when a target was set, put
            /// back by `setTarget(null)`.
            screenFramebuffer: u32 = 0,
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
                .screen => if (impl.target) |t|
                    Viewport.rasterOrtho(t.size().asVec2I())
                else
                    self.viewport.applyFullscreen(),
                .camera => |cam| cam.matrix(self.viewport),
                .matrix => |m| m,
            };

            impl.screenPass = projection == .screen and impl.target == null;
            impl.batch.begin(mvp);
            impl.batch.setShader(null);
            applyBlend(.alpha);
        }

        /// Flushes whatever is still queued and closes the pass.
        pub fn end(self: *Self) void {
            const impl = self.implMut();
            impl.batch.end();
            // A pass's blend mode and shader end with it, so they never
            // leak into the next pass or into renderers that draw outside
            // one (tile maps, 3D quads).
            impl.batch.setShader(null);
            applyBlend(.alpha);

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
        /// clip: the letterboxed viewport, the whole framebuffer inside a
        /// `.screen` pass, or the whole target while one is set. Queued
        /// draws are flushed first, so they keep the previous clip.
        pub fn setClip(self: *Self, rect: ?RectF) void {
            self.flush();
            if (self.implMut().target) |t| {
                clipTarget(t, self.viewport, rect);
                return;
            }
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

        /// Sends later passes to `target` instead of the screen, until
        /// `setTarget(null)` puts the screen back. Call it between passes,
        /// not inside a `begin`/`end`. Inside a target, `.logical` and
        /// `.camera` passes stretch the logical screen over the whole
        /// target (so a target the logical size gets it pixel for pixel),
        /// and a `.screen` pass draws in the target's own pixels.
        pub fn setTarget(self: *Self, target: ?*RenderTarget) void {
            const impl = self.implMut();
            std.debug.assert(!impl.batch.begun);
            if (target) |t| {
                if (impl.target == null) impl.screenFramebuffer = render_target.boundFramebuffer();
                impl.target = t;
                gl.bindFramebuffer(gl.FRAMEBUFFER, t.fbo);
                const sz = t.size();
                gl.viewport(0, 0, @intCast(sz.x), @intCast(sz.y));
                clipTarget(t, self.viewport, null);
            } else if (impl.target != null) {
                impl.target = null;
                gl.bindFramebuffer(gl.FRAMEBUFFER, impl.screenFramebuffer);
                self.viewport.apply();
            }
        }

        /// The target passes currently draw into, or null for the screen.
        pub fn currentTarget(self: *const Self) ?*RenderTarget {
            return self.implConst().target;
        }

        /// Sets how later draws in this pass blend with what's behind them
        /// (see `BlendMode`). Queued draws are flushed first, so they keep
        /// the previous mode. Lasts until the pass ends; every pass starts
        /// at `.alpha`.
        pub fn setBlend(self: *Self, mode: BlendMode) void {
            self.flush();
            applyBlend(mode);
        }

        /// Draws later quads in this pass with `shader`, or the default
        /// one for null. Build it with `createShader`, so it takes the
        /// batch's vertex layout. Queued draws are flushed first. Lasts
        /// until the pass ends; every pass starts with the default shader.
        pub fn setShader(self: *Self, shader: ?*ShaderHandle) void {
            self.implMut().batch.setShader(shader);
        }

        /// Sets a uniform the active shader (see `setShader`) declares.
        /// `value` is an `f32`, `i32`, `Vec2F`, `Color` (a `vec4`), or a
        /// `zmath.Mat` (a `mat4`). Queued draws are flushed first, so they
        /// keep the old value. A name the shader doesn't use is ignored, as
        /// GL does. The value stays set on that shader until changed.
        pub fn setUniform(self: *Self, name: [:0]const u8, value: anytype) void {
            const batch = &self.implMut().batch;
            if (batch.begun) batch.flush();
            const program = batch.activeShader().val.program;
            gl.useProgram(program);
            const loc = gl.getUniformLocation(program, name.ptr);
            const T = @TypeOf(value);
            if (T == f32 or T == comptime_float) {
                gl.uniform1f(loc, value);
            } else if (T == i32 or T == comptime_int) {
                gl.uniform1i(loc, value);
            } else if (T == Vec2F) {
                gl.uniform2f(loc, value.x, value.y);
            } else if (T == Color) {
                gl.uniform4f(loc, value.r, value.g, value.b, value.a);
            } else if (T == zmath.Mat) {
                const arr = zmath.matToArr(value);
                gl.uniformMatrix4fv(loc, 1, gl.FALSE, &arr);
            } else {
                @compileError("Renderer.setUniform: unsupported uniform type " ++ @typeName(T));
            }
        }

        /// Compiles a shader for `setShader` from your own GLSL ES 3.00
        /// fragment shader, paired with the batch's vertex shader, and
        /// stores it in `resMgr` under `name`. The fragment shader gets:
        ///
        /// ```glsl
        /// in vec2 Texcoord;   // the texel to sample
        /// in vec4 Col;        // the draw's color (white for plain sprites)
        /// flat in float Mode; // DrawMode: 0 texture, 1 font mask, 2 fill
        /// uniform sampler2D tex;
        /// out vec4 fragColor;
        /// ```
        ///
        /// For sprites and render targets, `texture(tex, Texcoord) * Col`
        /// is the default result to build on. Text and silhouettes use the
        /// other modes; see `shaders.SpritePixelShader`.
        pub fn createShader(self: *Self, resMgr: *ResourceManager, name: []const u8, fragmentSource: [*:0]const u8) !*ShaderHandle {
            _ = self;
            const code: shaders.ShaderCode = fragmentSource;
            return resMgr.loadShader(name, &shaders.SpriteVertexShader, &code);
        }

        /// Covers the logical screen with `color`, its alpha scaled by
        /// `amount` (0 draws nothing, 1 is the color as given): a fade to
        /// black, a hit flash, a dimmed pause screen. A pass of its own, so
        /// call it between passes, usually last in `render`.
        pub fn fade(self: *Self, color: Color, amount: f32) void {
            requireFlag("fade", "shapeRendering");
            const a = color.a * std.math.clamp(amount, 0, 1);
            if (a <= 0) return;
            const w: f32 = @floatFromInt(self.viewport.logicalSize.x);
            const h: f32 = @floatFromInt(self.viewport.logicalSize.y);
            self.begin(.logical);
            self.implMut().batch.drawFilledRect(.{ .l = 0, .t = 0, .r = w, .b = h }, color.withAlpha(a));
            self.end();
        }

        fn applyBlend(mode: BlendMode) void {
            const src: gl.Enum, const dst: gl.Enum = switch (mode) {
                .alpha => .{ gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA },
                .additive => .{ gl.SRC_ALPHA, gl.ONE },
                .multiply => .{ gl.DST_COLOR, gl.ONE_MINUS_SRC_ALPHA },
                .premultiplied => .{ gl.ONE, gl.ONE_MINUS_SRC_ALPHA },
            };
            // Alpha always accumulates as coverage, so a target drawn into
            // ends up with the alpha a later `.premultiplied` draw expects.
            gl.blendFuncSeparate(src, dst, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        }

        /// Scissors to `rect` (logical coordinates) mapped onto `target`,
        /// or to the whole target for null.
        fn clipTarget(target: *const RenderTarget, viewport: *const Viewport, rect: ?RectF) void {
            const sz = target.size();
            const tw: f32 = @floatFromInt(sz.x);
            const th: f32 = @floatFromInt(sz.y);
            gl.enable(gl.SCISSOR_TEST);
            const r = rect orelse {
                gl.scissor(0, 0, @intCast(sz.x), @intCast(sz.y));
                return;
            };
            const sx = tw / @as(f32, @floatFromInt(viewport.logicalSize.x));
            const sy = th / @as(f32, @floatFromInt(viewport.logicalSize.y));
            const l = std.math.clamp(r.l * sx, 0, tw);
            const t = std.math.clamp(r.t * sy, 0, th);
            const right = std.math.clamp(r.r * sx, l, tw);
            const b = std.math.clamp(r.b * sy, t, th);
            // GL counts scissor rows from the bottom; a target's rows are
            // stored bottom first, which `.logical` already accounts for.
            gl.scissor(@intFromFloat(l), @intFromFloat(th - b), @intFromFloat(right - l), @intFromFloat(b - t));
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
        pub fn drawFullTexture(self: *Self, texture: *TextureHandle, pos: Vec2F, scale: f32) void {
            const tex = &texture.val;
            const tsx = @as(f32, @floatFromInt(tex.size.x)) * scale;
            const tsy = @as(f32, @floatFromInt(tex.size.y)) * scale;
            const dest = RectF.fromPosSize(pos.x, pos.y, tsx, tsy);
            self.implMut().batch.draw(tex, dest, tex.src, .none, white, .texture);
        }

        /// Draws the `srcCoords` region of `texture` into `dest`, multiplied
        /// by `color` (alpha < 1 fades it, rgb < 1 tints it).
        pub fn drawTextureColored(self: *Self, texture: *TextureHandle, dest: RectF, srcCoords: RectF, color: Color) void {
            self.implMut().batch.draw(&texture.val, dest, srcCoords, .none, color, .texture);
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

        /// Draws `text` in `style` (font, color, scale, clip, alignment,
        /// shadow; see `TextStyle`) with its line box's top at `pos.y`.
        /// Returns the size drawn, the same as `measureText`. Requires
        /// `RendererOptions.textRendering == true`; calling it with text
        /// rendering compiled out is a compile error. Draws nothing (and
        /// logs an error) if the style names no font and no default font
        /// has been set (see `setDefaultFont`).
        pub fn drawText(self: *Self, text: []const u8, pos: Vec2F, style: TextStyle) Vec2F {
            requireFlag("drawText", "textRendering");
            return self.implMut().text.drawText(text, pos, style);
        }

        /// `drawText` in the default style: the default font, white, at
        /// its own size.
        pub fn drawString(self: *Self, text: []const u8, pos: Vec2F) Vec2F {
            requireFlag("drawString", "textRendering");
            return self.implMut().text.drawText(text, pos, .{});
        }

        /// The size `drawText` would draw `text` in `style` without drawing
        /// it: the advances wide, and the font's ascent plus descent tall,
        /// both scaled. Centering this box centers the text as drawn.
        /// Requires `RendererOptions.textRendering == true`.
        pub fn measureText(self: *Self, text: []const u8, style: TextStyle) Vec2F {
            requireFlag("measureText", "textRendering");
            return self.implMut().text.measureText(text, style);
        }

        /// The default font's line spacing at scale 1 (ascent, descent and
        /// line gap): how far apart to put the tops of consecutive lines.
        /// Null when no font is set. Requires
        /// `RendererOptions.textRendering == true`.
        pub fn lineHeight(self: *const Self) ?f32 {
            requireFlag("lineHeight", "textRendering");
            return self.implConst().text.lineHeight();
        }
    };
}
