const std = @import("std");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

const common = @import("../common.zig");

const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");
const resources = @import("../resources.zig");

const Vec3F = common.Vec3F;
const RectF = common.RectF;
const Texture = textures.Texture;
const ResourceManager = resources.ResourceManager;
const ManagedShader = resources.ManagedShader;
const ShaderHandle = resources.ShaderHandle;

const MaxQuads = 4096;
const NumVerts = 3 * 4 * MaxQuads;
const NumTexCoords = 2 * 4 * MaxQuads;
const NumIndices = 6 * MaxQuads;

/// A batch queue for drawing arbitrary world-space textured quads (walls,
/// floors, ceilings) with a full perspective view*projection matrix. Mirrors
/// SpriteBatchQueue's architecture, but vertex positions are 3d instead of
/// axis-aligned 2d rects, so callers supply the 4 corners directly.
///
/// Unlike the 2d renderer, `begin`/`end` also toggle GL_DEPTH_TEST so
/// overlapping wall/floor/ceiling quads occlude correctly regardless of
/// submission order, without leaking depth testing into any 2d rendering
/// that runs later in the same frame.
pub const Quad3DBatchQueue = struct {
    shader: *ShaderHandle,
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
    currNumQuads: usize = 0,

    mvpArr: [16]f32 = .{0} ** 16,
    texture: ?*const Texture = null,
    begun: bool = false,

    /// Initializes the Quad3DBatchQueue, creating the buffers and OpenGL
    /// objects needed, and loading (or reusing) the quad3d shader via the
    /// resource manager.
    pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager) !Quad3DBatchQueue {
        const shader_managed = try resMgr.loadShader(
            shaders.Quad3DShader,
            &shaders.Quad3DVertexShader,
            &shaders.TexPixelShader,
        );
        const handle = shader_managed.acquire() orelse return error.NoShaderInPool;
        errdefer handle.release();

        var batch = Quad3DBatchQueue{
            .allocator = alloc,
            .shader = handle,
        };

        batch.vertices = try alloc.alloc(f32, NumVerts);
        errdefer alloc.free(batch.vertices);

        batch.texCoords = try alloc.alloc(f32, NumTexCoords);
        errdefer alloc.free(batch.texCoords);

        batch.indices = try alloc.alloc(u16, NumIndices);
        errdefer alloc.free(batch.indices);

        gl.genVertexArrays(1, &batch.vao);
        errdefer gl.deleteVertexArrays(1, &batch.vao);
        gl.bindVertexArray(batch.vao);

        gl.genBuffers(1, &batch.vboVertices);
        errdefer gl.deleteBuffers(1, &batch.vboVertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, 3 * 4 * MaxQuads, &batch.vertices[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboTexCoords);
        errdefer gl.deleteBuffers(1, &batch.vboTexCoords);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxQuads, &batch.texCoords[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboIndices);
        errdefer gl.deleteBuffers(1, &batch.vboIndices);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, batch.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 6 * MaxQuads, &batch.indices[0], gl.DYNAMIC_DRAW);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        gl.enable(gl.TEXTURE_2D);

        batch.cacheShaderLocations();

        return batch;
    }

    /// Cleans up the OpenGL objects associated with the Quad3DBatchQueue and
    /// frees the buffer memory.
    pub fn deinit(self: *Quad3DBatchQueue) void {
        self.shader.release();
        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboTexCoords);
        gl.deleteBuffers(1, &self.vboIndices);
        gl.deleteVertexArrays(1, &self.vao);
        self.allocator.free(self.vertices);
        self.allocator.free(self.texCoords);
        self.allocator.free(self.indices);
    }

    fn cacheShaderLocations(self: *Quad3DBatchQueue) void {
        self.attrCoord = @intCast(gl.getAttribLocation(self.shader.val.program, "coord3d"));
        self.attrTexCoord = @intCast(gl.getAttribLocation(self.shader.val.program, "texcoord"));
        self.uniformMVP = @intCast(gl.getUniformLocation(self.shader.val.program, "projectionMatrix"));
    }

    fn refreshShader(self: *Quad3DBatchQueue) void {
        if (!self.shader.dirty) return;
        self.shader = self.shader.reacquire();
        self.cacheShaderLocations();
    }

    /// Begins a new 3d render pass, setting the view*projection matrix to
    /// use and enabling depth testing (clearing the depth buffer) so
    /// quads submitted in any order occlude correctly.
    pub fn begin(self: *Quad3DBatchQueue, viewProj: zmath.Mat) void {
        if (self.begun) {
            self.end();
        }
        self.refreshShader();
        self.begun = true;
        self.mvpArr = zmath.matToArr(viewProj);

        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LESS);
        gl.clear(gl.DEPTH_BUFFER_BIT);
    }

    /// Enqueues drawing a textured quad given its 4 world-space corners, in
    /// the same winding order RectF-based draws use elsewhere in pixzig:
    /// bottom-left, top-left, top-right, bottom-right (relative to
    /// `srcCoords`, which maps corner 0 to (l,b), 1 to (l,t), 2 to (r,t)
    /// and 3 to (r,b)).
    pub fn drawQuad(self: *Quad3DBatchQueue, texture: *const Texture, corners: [4]Vec3F, srcCoords: RectF) void {
        std.debug.assert(self.begun);

        if (self.texture == null) {
            self.texture = texture;
        }

        if (self.texture.?.texture != texture.texture) {
            self.flush();
            self.texture = texture;
        }

        if (self.currNumQuads >= MaxQuads) {
            self.flush();
            self.texture = texture;
        }

        const verts = self.vertices[self.currVert .. self.currVert + 12];
        inline for (0..4) |i| {
            verts[i * 3 + 0] = corners[i].x;
            verts[i * 3 + 1] = corners[i].y;
            verts[i * 3 + 2] = corners[i].z;
        }

        const texCoords = self.texCoords[self.currTexCoord .. self.currTexCoord + 8];
        texCoords[0] = srcCoords.l;
        texCoords[1] = srcCoords.b;

        texCoords[2] = srcCoords.l;
        texCoords[3] = srcCoords.t;

        texCoords[4] = srcCoords.r;
        texCoords[5] = srcCoords.t;

        texCoords[6] = srcCoords.r;
        texCoords[7] = srcCoords.b;

        const indices = self.indices[self.currIdx .. self.currIdx + 6];
        const currVertIdx: u16 = @intCast(self.currVert / 3);
        indices[0] = currVertIdx + 0;
        indices[1] = currVertIdx + 1;
        indices[2] = currVertIdx + 2;
        indices[3] = currVertIdx + 2;
        indices[4] = currVertIdx + 3;
        indices[5] = currVertIdx + 0;

        self.currVert += 12;
        self.currTexCoord += 8;
        self.currIdx += 6;

        self.currNumQuads += 1;
    }

    /// Ends the current batch, flushing any queued quads and disabling
    /// depth testing so it doesn't affect subsequent 2d rendering.
    pub fn end(self: *Quad3DBatchQueue) void {
        self.flush();
        self.begun = false;
        gl.disable(gl.DEPTH_TEST);
    }

    /// Draws the current contents of the queue to the screen. Assumes
    /// `begin` has already been called. Flushes queued quads while keeping
    /// the batch open for further draws.
    pub fn flush(self: *Quad3DBatchQueue) void {
        std.debug.assert(self.begun);

        if (self.currNumQuads == 0) return;

        gl.useProgram(self.shader.val.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&self.mvpArr[0]));

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.texture.?.texture);

        gl.uniform1i(gl.getUniformLocation(self.shader.val.program, "tex"), 0);

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(3 * 4 * @sizeOf(f32) * self.currNumQuads), &self.vertices[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrCoord, 3, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.enableVertexAttribArray(self.attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumQuads), &self.texCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrTexCoord, 2, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.currNumQuads), &self.indices[0], gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(6 * self.currNumQuads), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrTexCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        self.currVert = 0;
        self.currTexCoord = 0;
        self.currIdx = 0;
        self.currNumQuads = 0;
        self.texture = null;
    }
};
