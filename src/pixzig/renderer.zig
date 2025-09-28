const std = @import("std");
const builtin = @import("builtin");

const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

pub const stb_tt = @import("stb_truetype");

const textMod = @import("./renderer/text.zig");
const common = @import("./common.zig");
const textures = @import("./renderer/textures.zig");
const shaders = @import("./renderer/shaders.zig");

const Sprite = @import("./renderer/sprites.zig").Sprite;
const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Rotate = common.Rotate;
const Texture = textures.Texture;
const ResourceManager = textures.ResourceManager;
const Shader = shaders.Shader;
pub const FontAtlas = textMod.FontAtlas;

pub const SpriteBatchQueue = @import("./renderer/sprite_batch.zig").SpriteBatchQueue;
pub const ShapeBatchQueue = @import("./renderer/shape.zig").ShapeBatchQueue;
pub const TextRenderer = textMod.TextRenderer;

pub const RendererOptions = struct {
    numSpriteTextures: u8 = 1,
    shapeRendering: bool = true,
    textRenderering: bool = false,
};

pub const RendererInitOpts = struct {
    fontFace: ?[:0]const u8 = null,
};

pub fn Renderer(opts: RendererOptions) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        impl: *Impl,

        const Impl = struct {
            batches: [opts.numSpriteTextures]SpriteBatchQueue,

            shapes: ShapeBatchQueue = undefined,
            text: TextRenderer = undefined,
            fontAtlas: ?FontAtlas = null,
        };

        pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager, initOpts: RendererInitOpts) !@This() {
            var rend = try alloc.create(Impl);

            std.log.info("Initializing shaders.", .{});
            const texShader = try resMgr.loadShader(shaders.TextureShader, &shaders.TexVertexShader, &shaders.TexPixelShader);

            std.log.info("Setting up {} sprite batch queues.", .{opts.numSpriteTextures});
            for (0..opts.numSpriteTextures) |idx| {
                const sbq = try SpriteBatchQueue.init(alloc, texShader);
                rend.batches[idx] = sbq;
            }

            if (opts.shapeRendering) {
                std.log.info("Setting up shaders for shape renderering.", .{});
                const colorShader = try resMgr.loadShader(shaders.ColorShader, &shaders.ColorVertexShader, &shaders.ColorPixelShader);

                rend.shapes = try ShapeBatchQueue.init(alloc, colorShader);
            }

            if (opts.textRenderering) {
                std.log.info("Setting up text renderering.\n", .{});

                if (builtin.os.tag == .emscripten) {
                    _ = try resMgr.loadShader(shaders.FontShader, &shaders.TexVertexShader, &shaders.TextPixelShader_Web);
                } else {
                    _ = try resMgr.loadShader(shaders.FontShader, &shaders.TexVertexShader, &shaders.TextPixelShader_Desktop);
                }

                rend.text = try TextRenderer.init(alloc, resMgr);

                if (initOpts.fontFace != null) {
                    rend.fontAtlas = try FontAtlas.initFromTtfFile(initOpts.fontFace.?, 32.0, alloc);
                    rend.text.setAtlas(&rend.fontAtlas.?);
                } else {
                    if (builtin.mode == .Debug) {
                        std.log.warn("No default font provided. Text rendering will not work until a FontAtlas is set.", .{});
                    }
                }
            }

            // set texture options
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
            gl.enable(gl.BLEND);
            gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

            return .{ .alloc = alloc, .impl = rend };
        }

        pub fn deinit(self: *Self) void {
            for (0..self.impl.batches.len) |idx| {
                self.impl.batches[idx].deinit();
            }

            self.impl.texShader.deinit();

            if (opts.shapeRendering) {
                self.impl.colorShader.deinit();
                self.impl.shapes.deinit();
            }

            if (opts.textRenderering) {
                self.impl.text.deinit();
            }

            self.alloc.destroy(self.impl);
        }

        pub fn begin(self: *Self, mvp: zmath.Mat) void {
            for (0..self.impl.batches.len) |idx| {
                self.impl.batches[idx].begin(mvp);
            }

            if (opts.shapeRendering) {
                self.impl.shapes.begin(mvp);
            }

            if (opts.textRenderering) {
                self.impl.text.begin(mvp, null);
            }
        }

        pub fn end(self: *Self) void {
            for (0..self.impl.batches.len) |idx| {
                self.impl.batches[idx].end();
            }

            if (opts.shapeRendering) {
                self.impl.shapes.end();
            }

            if (opts.textRenderering) {
                self.impl.text.end();
            }
        }

        pub fn clear(self: *const Self, r: f32, g: f32, b: f32, a: f32) void {
            _ = self;
            gl.clearColor(r, g, b, a);
            gl.clear(gl.COLOR_BUFFER_BIT);
        }

        pub fn draw(self: *Self, texture: *Texture, dest: RectF, srcCoords: RectF) void {
            // TODO: Handle multiple batches
            self.impl.batches[0].draw(texture, dest, srcCoords, .none);
        }

        pub fn drawSprite(self: *Self, sprite: *Sprite) void {
            // TODO: Handle batches
            self.impl.batches[0].drawSprite(sprite);
        }

        pub fn drawTexture(self: *Self, texture: *Texture, dest: RectF, srcCoords: RectF) void {
            self.impl.batches[0].draw(texture, dest, srcCoords, .none);
        }

        pub fn drawFullTexture(self: *Self, texture: *Texture, pos: Vec2I, scale: f32) void {
            const tsx = @as(f32, @floatFromInt(texture.size.x)) * scale;
            const tsy = @as(f32, @floatFromInt(texture.size.y)) * scale;
            self.impl.batches[0].draw(texture, RectF.fromPosSize(pos.x, pos.y, @intFromFloat(tsx), @intFromFloat(tsy)), texture.src, .none);
        }

        pub fn drawFilledRect(self: *Self, dest: RectF, color: Color) void {
            std.debug.assert(opts.shapeRendering);
            self.impl.shapes.drawFilledRect(dest, color);
        }

        pub fn drawRect(self: *Self, dest: RectF, color: Color, lineWidth: u8) void {
            std.debug.assert(opts.shapeRendering);
            self.impl.shapes.drawRect(dest, color, lineWidth);
        }

        // This moves the outline of the rect to enclose the dest by lineWidth.
        pub fn drawEnclosingRect(self: *Self, dest: RectF, color: Color, lineWidth: u8) void {
            std.debug.assert(opts.shapeRendering);
            self.impl.shapes.drawEnclosingRect(dest, color, lineWidth);
        }

        pub fn drawString(self: *Self, text: []const u8, pos: Vec2I) Vec2I {
            std.debug.assert(opts.textRenderering);
            return self.impl.text.drawString(text, pos);
        }
    };
}
