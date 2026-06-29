const std = @import("std");
const builtin = @import("builtin");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

const common = @import("../common.zig");

const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");
const resources = @import("../resources.zig");
const Sprite = @import("./sprites.zig").Sprite;
const C = @import("./constants.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Rotate = common.Rotate;
const Texture = textures.Texture;
const Shader = shaders.Shader;
const ShaderPool = resources.ShaderPool;
const ShaderHandle = resources.ShaderHandle;

/// SpriteBatchQueue lets the user queue up multiple sprites to draw in one go.
/// It uses buffers for vertices, texture coords and indices to make a single draw
/// call.  This entire batch is drawn via the `flush` call which will happen on
/// render, switching the current texture, or drawing more than C.MaxSprites.
pub const SpriteBatchQueue = struct {
    /// Refcounted handle to the shader. Refreshed in `begin` when the pool
    /// signals a hot-reload.
    shader_handle: *ShaderHandle,
    /// The pool that owns the shader handle. Stored so we can reacquire
    /// after a dirty signal without re-doing the name lookup.
    shader_pool: *ShaderPool,
    /// Cached `&shader_handle.val` so the hot draw path doesn't repeatedly
    /// chase through the handle.
    shader: *const Shader,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboTexCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: []f32 = undefined,
    texCoords: []f32 = undefined,
    indices: []u16 = undefined,
    allocator: std.mem.Allocator,

    attrCoord: c_uint = 0,
    attrTexCoord: c_uint = 0,
    uniformMVP: c_int = 0,

    currVert: usize = 0,
    currTexCoord: usize = 0,
    currIdx: usize = 0,
    currNumSprites: usize = 0,

    mvpArr: [16]f32 = .{0} ** 16,
    texture: ?*Texture = null,
    begun: bool = false,

    /// Initializes the SpriteBatchQueue, creating the buffers and OpenGL objects needed.
    pub fn init(alloc: std.mem.Allocator, shader_pool: *ShaderPool) !SpriteBatchQueue {
        const handle = shader_pool.acquire() orelse return error.NoShaderInPool;
        errdefer shader_pool.release(handle);

        var batch = SpriteBatchQueue{
            .allocator = alloc,
            .shader_handle = handle,
            .shader_pool = shader_pool,
            .shader = &handle.val,
        };

        batch.vertices = try alloc.alloc(f32, C.NumVerts);
        errdefer alloc.free(batch.vertices);

        batch.texCoords = try alloc.alloc(f32, C.NumVerts);
        errdefer alloc.free(batch.texCoords);

        batch.indices = try alloc.alloc(u16, C.NumIndices);
        errdefer alloc.free(batch.indices);

        gl.genVertexArrays(1, &batch.vao);
        gl.bindVertexArray(batch.vao);

        gl.genBuffers(1, &batch.vboVertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * C.MaxSprites, &batch.vertices[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboTexCoords);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * C.MaxSprites, &batch.texCoords[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboIndices);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, batch.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 6 * C.MaxSprites, &batch.indices[0], gl.DYNAMIC_DRAW);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        gl.enable(gl.TEXTURE_2D);

        batch.cacheShaderLocations();

        return batch;
    }

    /// Cleans up the OpenGL objects associated with the SpriteBatchQueue and fress the buffer memory.
    pub fn deinit(self: *SpriteBatchQueue) void {
        self.shader_pool.release(self.shader_handle);
        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboTexCoords);
        gl.deleteBuffers(1, &self.vboIndices);
        self.allocator.free(self.vertices);
        self.allocator.free(self.texCoords);
        self.allocator.free(self.indices);
    }

    fn cacheShaderLocations(self: *SpriteBatchQueue) void {
        self.attrCoord = @intCast(gl.getAttribLocation(self.shader.program, "coord3d"));
        self.attrTexCoord = @intCast(gl.getAttribLocation(self.shader.program, "texcoord"));
        self.uniformMVP = @intCast(gl.getUniformLocation(self.shader.program, "projectionMatrix"));
    }

    /// If the shader was hot-reloaded, swap to the fresh handle and refetch
    /// uniform/attribute locations (a new GL program means new ids).
    fn refreshShader(self: *SpriteBatchQueue) void {
        if (!self.shader_handle.dirty) return;
        const new_handle = self.shader_pool.acquire() orelse return;
        self.shader_pool.release(self.shader_handle);
        self.shader_handle = new_handle;
        self.shader = &new_handle.val;
        self.cacheShaderLocations();
    }

    /// Swap to a different shader pool entirely (e.g. text renderer toggling
    /// between alpha and RGB pixel shaders). Releases the current handle,
    /// acquires from `new_pool`, and re-caches uniform/attribute locations.
    pub fn swapShader(self: *SpriteBatchQueue, new_pool: *ShaderPool) !void {
        const new_handle = new_pool.acquire() orelse return error.NoShaderInPool;
        self.shader_pool.release(self.shader_handle);
        self.shader_pool = new_pool;
        self.shader_handle = new_handle;
        self.shader = &new_handle.val;
        self.cacheShaderLocations();
    }

    /// Begins a new render frame, setting the Model-View-Projection matrix to use.
    pub fn begin(self: *SpriteBatchQueue, mvp: zmath.Mat) void {
        if (self.begun) {
            self.end();
        }
        self.refreshShader();
        self.begun = true;
        self.mvpArr = zmath.matToArr(mvp);
    }

    // Enqueues drawing a `Sprite`
    pub fn drawSprite(self: *SpriteBatchQueue, sprite: *Sprite) void {
        self.draw(&sprite.texture.val, sprite.dest, sprite.src_coords, sprite.rotate);
    }

    /// Enqueues drawing a portion of a texture to the screen, with optional 90deg rotation or flips.
    pub fn draw(self: *SpriteBatchQueue, texture: *Texture, dest: RectF, srcCoords: RectF, rot: Rotate) void {
        std.debug.assert(self.begun);

        if (self.texture == null) {
            self.texture = texture;
        }

        if (self.texture.?.texture != texture.texture) {
            self.flush();
            self.texture = texture;
        }

        if (self.currNumSprites >= C.MaxSprites) {
            self.flush();
            self.texture = texture;
        }

        const verts = self.vertices[self.currVert .. self.currVert + 8];
        verts[0] = dest.l;
        verts[1] = dest.b;

        verts[2] = dest.l;
        verts[3] = dest.t;

        verts[4] = dest.r;
        verts[5] = dest.t;

        verts[6] = dest.r;
        verts[7] = dest.b;

        const texCoords = self.texCoords[self.currTexCoord .. self.currTexCoord + 8];
        switch (rot) {
            .none => {
                texCoords[0] = srcCoords.l;
                texCoords[1] = srcCoords.b;

                texCoords[2] = srcCoords.l;
                texCoords[3] = srcCoords.t;

                texCoords[4] = srcCoords.r;
                texCoords[5] = srcCoords.t;

                texCoords[6] = srcCoords.r;
                texCoords[7] = srcCoords.b;
            },
            .rot90 => {
                texCoords[0] = srcCoords.l;
                texCoords[1] = srcCoords.t;

                texCoords[2] = srcCoords.r;
                texCoords[3] = srcCoords.t;

                texCoords[4] = srcCoords.r;
                texCoords[5] = srcCoords.b;

                texCoords[6] = srcCoords.l;
                texCoords[7] = srcCoords.b;
            },
            .rot180 => {
                texCoords[0] = srcCoords.r;
                texCoords[1] = srcCoords.t;

                texCoords[2] = srcCoords.r;
                texCoords[3] = srcCoords.b;

                texCoords[4] = srcCoords.l;
                texCoords[5] = srcCoords.b;

                texCoords[6] = srcCoords.l;
                texCoords[7] = srcCoords.t;
            },
            .rot270 => {
                texCoords[0] = srcCoords.r;
                texCoords[1] = srcCoords.b;

                texCoords[2] = srcCoords.l;
                texCoords[3] = srcCoords.b;

                texCoords[4] = srcCoords.l;
                texCoords[5] = srcCoords.t;

                texCoords[6] = srcCoords.r;
                texCoords[7] = srcCoords.t;
            },
            .flipHorz => {
                texCoords[0] = srcCoords.r;
                texCoords[1] = srcCoords.b;

                texCoords[2] = srcCoords.r;
                texCoords[3] = srcCoords.t;

                texCoords[4] = srcCoords.l;
                texCoords[5] = srcCoords.t;

                texCoords[6] = srcCoords.l;
                texCoords[7] = srcCoords.b;
            },
            .flipVert => {
                texCoords[0] = srcCoords.l;
                texCoords[1] = srcCoords.t;

                texCoords[2] = srcCoords.l;
                texCoords[3] = srcCoords.b;

                texCoords[4] = srcCoords.r;
                texCoords[5] = srcCoords.b;

                texCoords[6] = srcCoords.r;
                texCoords[7] = srcCoords.t;
            },
        }

        const indices = self.indices[self.currIdx .. self.currIdx + 6];
        const currVertIdx: u16 = @intCast(self.currVert / 2);
        indices[0] = currVertIdx + 0;
        indices[1] = currVertIdx + 1;
        indices[2] = currVertIdx + 2;
        indices[3] = currVertIdx + 2;
        indices[4] = currVertIdx + 3;
        indices[5] = currVertIdx + 0;

        self.currVert += 8;
        self.currTexCoord += 8;
        self.currIdx += 6;

        self.currNumSprites += 1;
    }

    // Ends the current batch and flushes any sprites to the screen.
    pub fn end(self: *SpriteBatchQueue) void {
        self.flush();
        self.begun = false;
    }

    /// Draws the current contents of the queue to the screen.
    /// This assumes we have called `begin` beforehand.
    /// Flushes queued sprites while keeping the batch open for further draws.
    pub fn flush(self: *SpriteBatchQueue) void {
        std.debug.assert(self.begun);

        if (self.currNumSprites == 0) return;

        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&self.mvpArr[0]));

        // Set 'tex' to use texture unit 0
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.texture.?.texture);

        gl.uniform1i(gl.getUniformLocation(self.shader.program, "tex"), 0);

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.vertices[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrCoord, 2, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.enableVertexAttribArray(self.attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.texCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrTexCoord, 2, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.currNumSprites), &self.indices[0], gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(6 * self.currNumSprites), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrTexCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        self.currVert = 0;
        self.currTexCoord = 0;
        self.currIdx = 0;
        self.currNumSprites = 0;
        self.texture = null;
    }
};
