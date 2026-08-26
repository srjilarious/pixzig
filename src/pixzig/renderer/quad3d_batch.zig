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

/// A pre-built, static batch of world-space textured quads sharing a single
/// texture: build it once (or whenever the source data changes) via
/// beginBuild/addQuad/endBuild, then call draw() every frame for a single
/// draw call. Use this instead of Quad3DBatchQueue for geometry that doesn't
/// change often, e.g. a level's wall/floor/ceiling quads. Callers needing
/// multiple textures should keep one Quad3DBatch per texture and draw each
/// in turn.
pub const Quad3DBatch = struct {
    shader: *ShaderHandle,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboTexCoords: u32 = 0,
    vboIndices: u32 = 0,
    allocator: std.mem.Allocator,

    attrCoord: c_uint = 0,
    attrTexCoord: c_uint = 0,
    uniformMVP: c_int = 0,

    // CPU-side scratch, only populated between beginBuild() and endBuild().
    vertices: std.ArrayList(f32) = .empty,
    texCoords: std.ArrayList(f32) = .empty,
    indices: std.ArrayList(u16) = .empty,

    numIndices: usize = 0,
    texture: ?*const Texture = null,
    building: bool = false,

    /// Initializes the Quad3DBatch, creating its GL objects and loading (or
    /// reusing) the quad3d shader via the resource manager. No quad data is
    /// uploaded yet; call beginBuild/addQuad/endBuild before drawing.
    pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager) !Quad3DBatch {
        const shader_managed = try resMgr.loadShader(
            shaders.Quad3DShader,
            &shaders.Quad3DVertexShader,
            &shaders.TexPixelShader,
        );
        const handle = shader_managed.acquire() orelse return error.NoShaderInPool;
        errdefer handle.release();

        var batch = Quad3DBatch{
            .allocator = alloc,
            .shader = handle,
        };

        gl.genVertexArrays(1, &batch.vao);
        errdefer gl.deleteVertexArrays(1, &batch.vao);
        gl.genBuffers(1, &batch.vboVertices);
        errdefer gl.deleteBuffers(1, &batch.vboVertices);
        gl.genBuffers(1, &batch.vboTexCoords);
        errdefer gl.deleteBuffers(1, &batch.vboTexCoords);
        gl.genBuffers(1, &batch.vboIndices);
        errdefer gl.deleteBuffers(1, &batch.vboIndices);

        batch.cacheShaderLocations();

        return batch;
    }

    /// Cleans up the OpenGL objects and any CPU-side scratch buffers.
    pub fn deinit(self: *Quad3DBatch) void {
        self.shader.release();
        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboTexCoords);
        gl.deleteBuffers(1, &self.vboIndices);
        gl.deleteVertexArrays(1, &self.vao);
        self.vertices.deinit(self.allocator);
        self.texCoords.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }

    fn cacheShaderLocations(self: *Quad3DBatch) void {
        self.attrCoord = @intCast(gl.getAttribLocation(self.shader.val.program, "coord3d"));
        self.attrTexCoord = @intCast(gl.getAttribLocation(self.shader.val.program, "texcoord"));
        self.uniformMVP = @intCast(gl.getUniformLocation(self.shader.val.program, "projectionMatrix"));
    }

    /// Re-points the already-uploaded VBOs at the current shader's attribute
    /// locations without re-uploading any data. Needed because endBuild()
    /// bakes attribute locations into the VAO, and a shader hot-reload can
    /// hand back a new program where those locations moved.
    fn rebindVaoAttribs(self: *Quad3DBatch) void {
        if (self.numIndices == 0) return;

        gl.bindVertexArray(self.vao);

        gl.enableVertexAttribArray(self.attrCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices);
        gl.vertexAttribPointer(self.attrCoord, 3, gl.FLOAT, gl.FALSE, 0, null);

        gl.enableVertexAttribArray(self.attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords);
        gl.vertexAttribPointer(self.attrTexCoord, 2, gl.FLOAT, gl.FALSE, 0, null);

        gl.bindVertexArray(0);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    }

    fn refreshShader(self: *Quad3DBatch) void {
        if (!self.shader.dirty) return;
        self.shader = self.shader.reacquire();
        self.cacheShaderLocations();
        self.rebindVaoAttribs();
    }

    /// Starts (re)building the batch's quad list from scratch. Every quad
    /// added before the matching endBuild() shares `texture`. Safe to call
    /// again later (e.g. after the underlying map data changes) to fully
    /// rebuild the batch; the previous GPU contents keep drawing correctly
    /// until endBuild() uploads the new ones.
    pub fn beginBuild(self: *Quad3DBatch, texture: *const Texture) void {
        std.debug.assert(!self.building);
        self.building = true;
        self.texture = texture;
        self.vertices.clearRetainingCapacity();
        self.texCoords.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    /// Adds a quad's 4 world-space corners to the batch, in the same winding
    /// order as Quad3DBatchQueue.drawQuad: bottom-left, top-left, top-right,
    /// bottom-right (relative to srcCoords).
    pub fn addQuad(self: *Quad3DBatch, corners: [4]Vec3F, srcCoords: RectF) !void {
        std.debug.assert(self.building);

        const baseVert: u16 = @intCast(self.vertices.items.len / 3);

        var vbuf: [12]f32 = undefined;
        inline for (0..4) |i| {
            vbuf[i * 3 + 0] = corners[i].x;
            vbuf[i * 3 + 1] = corners[i].y;
            vbuf[i * 3 + 2] = corners[i].z;
        }
        try self.vertices.appendSlice(self.allocator, &vbuf);

        try self.texCoords.appendSlice(self.allocator, &.{
            srcCoords.l, srcCoords.b,
            srcCoords.l, srcCoords.t,
            srcCoords.r, srcCoords.t,
            srcCoords.r, srcCoords.b,
        });

        try self.indices.appendSlice(self.allocator, &.{
            baseVert + 0, baseVert + 1, baseVert + 2,
            baseVert + 2, baseVert + 3, baseVert + 0,
        });
    }

    /// Uploads the accumulated quad data to the GPU. After this call the
    /// batch can be drawn any number of times via draw() until the next
    /// beginBuild/endBuild cycle.
    pub fn endBuild(self: *Quad3DBatch) void {
        std.debug.assert(self.building);
        self.building = false;
        self.numIndices = self.indices.items.len;

        if (self.numIndices == 0) return;

        gl.bindVertexArray(self.vao);

        gl.enableVertexAttribArray(self.attrCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(self.vertices.items.len * @sizeOf(f32)), &self.vertices.items[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrCoord, 3, gl.FLOAT, gl.FALSE, 0, null);

        gl.enableVertexAttribArray(self.attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(self.texCoords.items.len * @sizeOf(f32)), &self.texCoords.items[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrTexCoord, 2, gl.FLOAT, gl.FALSE, 0, null);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(self.indices.items.len * @sizeOf(u16)), &self.indices.items[0], gl.STATIC_DRAW);

        gl.bindVertexArray(0);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    }

    /// Draws the batch's current GPU contents with the given view*projection
    /// matrix. Enables depth testing for the duration of the call so
    /// overlapping wall/floor/ceiling quads occlude correctly, then disables
    /// it again so it doesn't leak into any 2d rendering that runs after.
    pub fn draw(self: *Quad3DBatch, viewProj: zmath.Mat) void {
        self.refreshShader();

        if (self.numIndices == 0 or self.texture == null) return;

        const mvpArr = zmath.matToArr(viewProj);

        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LESS);
        gl.clear(gl.DEPTH_BUFFER_BIT);

        gl.useProgram(self.shader.val.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&mvpArr[0]));

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.texture.?.texture);
        gl.uniform1i(gl.getUniformLocation(self.shader.val.program, "tex"), 0);

        gl.bindVertexArray(self.vao);
        gl.drawElements(gl.TRIANGLES, @intCast(self.numIndices), gl.UNSIGNED_SHORT, null);
        gl.bindVertexArray(0);

        gl.disable(gl.DEPTH_TEST);
    }
};
