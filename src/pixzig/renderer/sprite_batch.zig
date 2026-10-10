const std = @import("std");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

const common = @import("../common.zig");
const textures = @import("./textures.zig");
const resources = @import("../resources.zig");
const Sprite = @import("./sprites.zig").Sprite;
const C = @import("./constants.zig");

const RectF = common.RectF;
const Color = common.Color;
const Rotate = common.Rotate;
const Texture = textures.Texture;
const ShaderHandle = resources.ShaderHandle;

/// How the sprite shader combines a quad's texel with its vertex color.
pub const DrawMode = enum(u8) {
    /// texel * color. Plain sprites (white), tinted sprites, shapes (on the
    /// built-in white texture) and bitmap-font text.
    texture = 0,
    /// The texture's red channel is coverage: color, with its alpha scaled
    /// by the texel's red. TTF font atlases.
    mask = 1,
    /// The texel's rgb is replaced by color.rgb (blended by color.a, 1 =
    /// solid) and its alpha kept: a silhouette of the sprite's shape.
    fill = 2,
};

/// One corner of a queued quad, as uploaded to the GPU. The attribute
/// locations match the `layout(location = N)` in `SpriteVertexShader`.
const Vertex = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    /// Normalized by GL to 0..1.
    color: [4]u8,
    /// `DrawMode` in byte 0; the rest pads the vertex to 4-byte alignment.
    mode: [4]u8,
};

const AttrPos = 0;
const AttrUv = 1;
const AttrColor = 2;
const AttrMode = 3;

fn toBytes(c: Color) [4]u8 {
    return .{ channel(c.r), channel(c.g), channel(c.b), channel(c.a) };
}

fn channel(v: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(v, 0, 1) * 255));
}

const white: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 };

/// The renderer's one batch: every sprite, shape and glyph is a textured
/// quad with a per-vertex color and `DrawMode`, so they all queue together
/// and keep their submission order. Shapes draw from a built-in 1x1 white
/// texture. A batch is flushed (one draw call) when the texture changes, the
/// batch is full, or on `flush`/`end`.
pub const SpriteBatch = struct {
    shader: *ShaderHandle,
    /// `shader.version` the uniform locations below were looked up from.
    shaderVersion: u32 = 0,
    uniformMVP: c_int = -1,
    uniformTex: c_int = -1,

    vao: u32 = 0,
    vbo: u32 = 0,
    ibo: u32 = 0,
    /// 1x1 opaque white, for untextured quads.
    whiteTexture: u32 = 0,

    vertices: []Vertex,
    numQuads: usize = 0,
    maxQuads: usize,
    /// GL texture of the queued quads.
    texture: u32 = 0,

    mvpArr: [16]f32 = @splat(0),
    begun: bool = false,
    alloc: std.mem.Allocator,

    /// Creates the batch with the default `C.MaxSprites` quad capacity.
    pub fn init(alloc: std.mem.Allocator, shader: *ShaderHandle) !SpriteBatch {
        return initCapacity(alloc, shader, C.MaxSprites);
    }

    /// Like `init`, but caps the batch at `maxQuads` queued quads before it
    /// auto-flushes. `shader` must be built from `SpriteVertexShader` and
    /// `SpritePixelShader`.
    pub fn initCapacity(alloc: std.mem.Allocator, shader: *ShaderHandle, maxQuads: usize) !SpriteBatch {
        const vertices = try alloc.alloc(Vertex, 4 * maxQuads);
        errdefer alloc.free(vertices);

        // The index pattern never changes, so it is built and uploaded once.
        const indices = try alloc.alloc(u32, 6 * maxQuads);
        defer alloc.free(indices);
        for (0..maxQuads) |q| {
            const base: u32 = @intCast(4 * q);
            // Corners are 0 (l,b), 1 (l,t), 2 (r,t), 3 (r,b).
            indices[6 * q ..][0..6].* = .{ base, base + 1, base + 2, base + 2, base + 3, base };
        }

        var batch = SpriteBatch{
            .shader = shader,
            .vertices = vertices,
            .maxQuads = maxQuads,
            .alloc = alloc,
        };

        gl.genVertexArrays(1, &batch.vao);
        errdefer gl.deleteVertexArrays(1, &batch.vao);
        gl.genBuffers(1, &batch.vbo);
        errdefer gl.deleteBuffers(1, &batch.vbo);
        gl.genBuffers(1, &batch.ibo);
        errdefer gl.deleteBuffers(1, &batch.ibo);

        gl.bindVertexArray(batch.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vbo);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(vertices.len * @sizeOf(Vertex)), null, gl.STREAM_DRAW);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, batch.ibo);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(indices.len * @sizeOf(u32)), indices.ptr, gl.STATIC_DRAW);

        const stride: c_int = @sizeOf(Vertex);
        gl.enableVertexAttribArray(AttrPos);
        gl.vertexAttribPointer(AttrPos, 2, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "pos")));
        gl.enableVertexAttribArray(AttrUv);
        gl.vertexAttribPointer(AttrUv, 2, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "uv")));
        gl.enableVertexAttribArray(AttrColor);
        gl.vertexAttribPointer(AttrColor, 4, gl.UNSIGNED_BYTE, gl.TRUE, stride, @ptrFromInt(@offsetOf(Vertex, "color")));
        gl.enableVertexAttribArray(AttrMode);
        gl.vertexAttribPointer(AttrMode, 1, gl.UNSIGNED_BYTE, gl.FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "mode")));
        gl.bindVertexArray(0);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        gl.genTextures(1, &batch.whiteTexture);
        gl.bindTexture(gl.TEXTURE_2D, batch.whiteTexture);
        const pixel = [4]u8{ 255, 255, 255, 255 };
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &pixel);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

        batch.cacheUniforms();
        return batch;
    }

    pub fn deinit(self: *SpriteBatch) void {
        gl.deleteTextures(1, &self.whiteTexture);
        gl.deleteBuffers(1, &self.ibo);
        gl.deleteBuffers(1, &self.vbo);
        gl.deleteVertexArrays(1, &self.vao);
        self.alloc.free(self.vertices);
    }

    fn cacheUniforms(self: *SpriteBatch) void {
        self.shaderVersion = self.shader.version;
        self.uniformMVP = gl.getUniformLocation(self.shader.val.program, "projectionMatrix");
        self.uniformTex = gl.getUniformLocation(self.shader.val.program, "tex");
    }

    /// Opens the batch with the matrix positions are transformed by.
    pub fn begin(self: *SpriteBatch, mvp: zmath.Mat) void {
        if (self.begun) self.end();
        if (self.shader.version != self.shaderVersion) self.cacheUniforms();
        self.begun = true;
        self.mvpArr = zmath.matToArr(mvp);
    }

    /// Flushes whatever is queued and closes the batch.
    pub fn end(self: *SpriteBatch) void {
        self.flush();
        self.begun = false;
    }

    /// Queues a quad given its 4 corners, in the winding order used
    /// throughout pixzig: 0 is (l,b), 1 is (l,t), 2 is (r,t), 3 is (r,b).
    /// Flushes first if `texture` (a GL texture id) differs from the queued
    /// quads' texture, or the batch is full.
    pub fn addQuad(
        self: *SpriteBatch,
        texture: u32,
        positions: [4][2]f32,
        uvs: [4][2]f32,
        colors: [4]Color,
        mode: DrawMode,
    ) void {
        std.debug.assert(self.begun);

        if (self.numQuads > 0 and (texture != self.texture or self.numQuads >= self.maxQuads)) {
            self.flush();
        }
        self.texture = texture;

        const m = [4]u8{ @backingInt(mode), 0, 0, 0 };
        const v = self.vertices[4 * self.numQuads ..][0..4];
        inline for (0..4) |i| {
            v[i] = .{ .pos = positions[i], .uv = uvs[i], .color = toBytes(colors[i]), .mode = m };
        }
        self.numQuads += 1;
    }

    /// Draws the queued quads in one call, keeping the batch open.
    pub fn flush(self: *SpriteBatch) void {
        std.debug.assert(self.begun);
        if (self.numQuads == 0) return;

        gl.useProgram(self.shader.val.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&self.mvpArr[0]));
        gl.uniform1i(self.uniformTex, 0);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.texture);

        // Orphan the buffer before writing, so the driver needn't wait for
        // the previous draw to finish reading it.
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(self.vertices.len * @sizeOf(Vertex)), null, gl.STREAM_DRAW);
        gl.bufferSubData(gl.ARRAY_BUFFER, 0, @intCast(4 * self.numQuads * @sizeOf(Vertex)), self.vertices.ptr);

        gl.bindVertexArray(self.vao);
        gl.drawElements(gl.TRIANGLES, @intCast(6 * self.numQuads), gl.UNSIGNED_INT, null);
        gl.bindVertexArray(0);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        self.numQuads = 0;
    }

    /// Queues the `srcCoords` region of `texture` into `dest`, with an
    /// optional 90 degree rotation or flip.
    pub fn draw(self: *SpriteBatch, texture: *const Texture, dest: RectF, srcCoords: RectF, rot: Rotate, color: Color, mode: DrawMode) void {
        self.addQuad(texture.texture, corners(dest), texCorners(srcCoords, rot), @splat(color), mode);
    }

    /// Queues a `Sprite`, using its `fill` (silhouette) or else `tint`.
    pub fn drawSprite(self: *SpriteBatch, sprite: *const Sprite) void {
        if (sprite.fill) |c| {
            self.drawSpriteAs(sprite, c, .fill);
        } else {
            self.drawSpriteAs(sprite, sprite.tint orelse white, .texture);
        }
    }

    /// Queues a `Sprite` with an explicit color and mode. Sprites keep float
    /// positions so slow movement accumulates, but the top-left is snapped
    /// to a whole pixel here (size unchanged) so a sprite between pixels
    /// never draws blurry.
    pub fn drawSpriteAs(self: *SpriteBatch, sprite: *const Sprite, color: Color, mode: DrawMode) void {
        const d = sprite.dest;
        const l = @round(d.l);
        const t = @round(d.t);
        const snapped: RectF = .{ .l = l, .t = t, .r = l + (d.r - d.l), .b = t + (d.b - d.t) };
        self.draw(&sprite.texture.val, snapped, sprite.srcCoords, sprite.rotate, color, mode);
    }

    /// Queues a solid rectangle.
    pub fn drawFilledRect(self: *SpriteBatch, dest: RectF, color: Color) void {
        self.addQuad(self.whiteTexture, corners(dest), @splat(.{ 0.5, 0.5 }), @splat(color), .texture);
    }

    /// Queues the outline of `dest`, `lineWidth` pixels thick, drawn inside
    /// it.
    pub fn drawRect(self: *SpriteBatch, dest: RectF, color: Color, lineWidth: u8) void {
        const w: f32 = @floatFromInt(lineWidth);
        self.drawFilledRect(.{ .l = dest.l, .t = dest.t, .r = dest.r, .b = dest.t + w }, color);
        self.drawFilledRect(.{ .l = dest.l, .t = dest.t + w, .r = dest.l + w, .b = dest.b - w }, color);
        self.drawFilledRect(.{ .l = dest.r - w, .t = dest.t + w, .r = dest.r, .b = dest.b - w }, color);
        self.drawFilledRect(.{ .l = dest.l, .t = dest.b - w, .r = dest.r, .b = dest.b }, color);
    }

    /// Like `drawRect`, but the outline sits outside `dest`, enclosing it.
    pub fn drawEnclosingRect(self: *SpriteBatch, dest: RectF, color: Color, lineWidth: u8) void {
        const w: f32 = @floatFromInt(lineWidth);
        self.drawFilledRect(.{ .l = dest.l - w, .t = dest.t - w, .r = dest.r + w, .b = dest.t }, color);
        self.drawFilledRect(.{ .l = dest.l - w, .t = dest.t, .r = dest.l, .b = dest.b }, color);
        self.drawFilledRect(.{ .l = dest.r, .t = dest.t, .r = dest.r + w, .b = dest.b }, color);
        self.drawFilledRect(.{ .l = dest.l - w, .t = dest.b, .r = dest.r + w, .b = dest.b + w }, color);
    }
};

fn corners(r: RectF) [4][2]f32 {
    return .{ .{ r.l, r.b }, .{ r.l, r.t }, .{ r.r, r.t }, .{ r.r, r.b } };
}

/// Texture coordinates for the four corners, rotated or flipped.
fn texCorners(s: RectF, rot: Rotate) [4][2]f32 {
    return switch (rot) {
        .none => .{ .{ s.l, s.b }, .{ s.l, s.t }, .{ s.r, s.t }, .{ s.r, s.b } },
        .rot90 => .{ .{ s.l, s.t }, .{ s.r, s.t }, .{ s.r, s.b }, .{ s.l, s.b } },
        .rot180 => .{ .{ s.r, s.t }, .{ s.r, s.b }, .{ s.l, s.b }, .{ s.l, s.t } },
        .rot270 => .{ .{ s.r, s.b }, .{ s.l, s.b }, .{ s.l, s.t }, .{ s.r, s.t } },
        .flipHorz => .{ .{ s.r, s.b }, .{ s.r, s.t }, .{ s.l, s.t }, .{ s.l, s.b } },
        .flipVert => .{ .{ s.l, s.t }, .{ s.l, s.b }, .{ s.r, s.b }, .{ s.r, s.t } },
    };
}
