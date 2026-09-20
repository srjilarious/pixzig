const std = @import("std");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

const common = @import("../common.zig");
const textures = @import("../renderer/textures.zig");
const shaders = @import("../renderer/shaders.zig");
const resources = @import("../resources.zig");
const tilemap = @import("./tilemap.zig");

const RectF = common.RectF;
const ShaderHandle = resources.ShaderHandle;
const TextureHandle = resources.TextureHandle;
const TileSet = tilemap.TileSet;
const TileLayer = tilemap.TileLayer;

/// Tiles per chunk along each axis. 32×32 = 1024 tiles/chunk.
pub const ChunkTiles: u32 = 32;

const MaxTilesPerChunk = ChunkTiles * ChunkTiles; // 1024
const MaxVertsPerChunk = MaxTilesPerChunk * 4; // 4096 vertices
const MaxFloatsPerChunk = MaxVertsPerChunk * 2; // 8192 floats (x,y per vert)
const MaxIndicesPerChunk = MaxTilesPerChunk * 6; // 6144 u16 indices

/// Per-chunk GPU state. Holds only GL handles and bookkeeping — no CPU buffers.
/// A single shared scratch buffer in ChunkedTiledLayerRenderer is used for builds.
const TileChunk = struct {
    vao: u32,
    vboCoords: u32,
    vboTexcoords: u32,
    ibo: u32,
    numIndices: usize,
    dirty: bool,
    originX: u32, // tile-space top-left corner of this chunk
    originY: u32,
    tileW: u32, // actual tile count (≤ ChunkTiles; may be less at map edges)
    tileH: u32,
};

/// Renders a TileLayer split into fixed-size chunks.
///
/// All chunk GL objects are created upfront in init(). Tile data is never
/// copied into per-chunk CPU buffers; a single shared scratch buffer is used
/// to build each chunk's vertex data just before uploading it to the GPU.
///
/// All chunks start dirty; the first render() call builds all of them.
/// Subsequent builds are triggered only by tileChanged() calls.
///
/// Viewport culling is applied in render(): chunks whose world-space AABB
/// does not intersect the supplied viewport rectangle are skipped entirely.
pub const ChunkedTiledLayerRenderer = struct {
    alloc: std.mem.Allocator,
    chunks: []TileChunk,
    chunksWide: u32,
    chunksTall: u32,
    /// Refcounted shader handle. Refreshed in `render` when dirty.
    shader: *ShaderHandle,
    /// Refcounted texture handle. Refreshed in `render` when dirty.
    texture: *TextureHandle,
    attrCoord: c_uint,
    attrTexcoord: c_uint,
    uniformMvp: c_int,
    // One shared scratch buffer; reused for every chunk build.
    scratchVerts: []f32,
    scratchTexcoords: []f32,
    scratchIndices: []u16,

    const Self = @This();

    /// Allocates the chunk grid and creates all GL objects.
    /// The layer's size is read here to determine the chunk layout; tile data
    /// is read lazily on the first render() call (all chunks start dirty=true).
    pub fn init(
        alloc: std.mem.Allocator,
        shader: *ShaderHandle,
        texture: *TextureHandle,
        layer: *const TileLayer,
    ) !Self {
        const shader_handle = shader.retain();
        errdefer shader_handle.release();
        const texture_handle = texture.retain();
        errdefer texture_handle.release();

        const map_w: u32 = @intCast(layer.size.x);
        const map_h: u32 = @intCast(layer.size.y);

        const chunksWide = (map_w + ChunkTiles - 1) / ChunkTiles;
        const chunksTall = (map_h + ChunkTiles - 1) / ChunkTiles;
        const num_chunks = chunksWide * chunksTall;

        const chunks = try alloc.alloc(TileChunk, num_chunks);
        errdefer alloc.free(chunks);

        for (0..chunksTall) |cy| {
            for (0..chunksWide) |cx| {
                const idx = cy * chunksWide + cx;
                const originX: u32 = @intCast(cx * ChunkTiles);
                const originY: u32 = @intCast(cy * ChunkTiles);

                var chunk = TileChunk{
                    .vao = 0,
                    .vboCoords = 0,
                    .vboTexcoords = 0,
                    .ibo = 0,
                    .numIndices = 0,
                    .dirty = true,
                    .originX = originX,
                    .originY = originY,
                    .tileW = @min(ChunkTiles, map_w - originX),
                    .tileH = @min(ChunkTiles, map_h - originY),
                };

                gl.genVertexArrays(1, &chunk.vao);
                gl.genBuffers(1, &chunk.vboCoords);
                gl.genBuffers(1, &chunk.vboTexcoords);
                gl.genBuffers(1, &chunk.ibo);

                chunks[idx] = chunk;
            }
        }
        errdefer for (chunks) |*c| {
            gl.deleteVertexArrays(1, &c.vao);
            gl.deleteBuffers(1, &c.vboCoords);
            gl.deleteBuffers(1, &c.vboTexcoords);
            gl.deleteBuffers(1, &c.ibo);
        };

        const scratchVerts = try alloc.alloc(f32, MaxFloatsPerChunk);
        errdefer alloc.free(scratchVerts);
        const scratchTexcoords = try alloc.alloc(f32, MaxFloatsPerChunk);
        errdefer alloc.free(scratchTexcoords);
        const scratchIndices = try alloc.alloc(u16, MaxIndicesPerChunk);
        errdefer alloc.free(scratchIndices);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.TEXTURE_2D);

        return .{
            .alloc = alloc,
            .chunks = chunks,
            .chunksWide = chunksWide,
            .chunksTall = chunksTall,
            .shader = shader_handle,
            .texture = texture_handle,
            .attrCoord = @intCast(gl.getAttribLocation(shader_handle.val.program, "coord3d")),
            .attrTexcoord = @intCast(gl.getAttribLocation(shader_handle.val.program, "texcoord")),
            .uniformMvp = @intCast(gl.getUniformLocation(shader_handle.val.program, "projectionMatrix")),
            .scratchVerts = scratchVerts,
            .scratchTexcoords = scratchTexcoords,
            .scratchIndices = scratchIndices,
        };
    }

    pub fn deinit(self: *Self) void {
        self.texture.release();
        self.shader.release();
        for (self.chunks) |*chunk| {
            gl.deleteVertexArrays(1, &chunk.vao);
            gl.deleteBuffers(1, &chunk.vboCoords);
            gl.deleteBuffers(1, &chunk.vboTexcoords);
            gl.deleteBuffers(1, &chunk.ibo);
        }
        self.alloc.free(self.chunks);
        self.alloc.free(self.scratchVerts);
        self.alloc.free(self.scratchTexcoords);
        self.alloc.free(self.scratchIndices);
    }

    fn refreshShader(self: *Self) void {
        if (!self.shader.dirty) return;
        self.shader = self.shader.reacquire();
        self.attrCoord = @intCast(gl.getAttribLocation(self.shader.val.program, "coord3d"));
        self.attrTexcoord = @intCast(gl.getAttribLocation(self.shader.val.program, "texcoord"));
        self.uniformMvp = @intCast(gl.getUniformLocation(self.shader.val.program, "projectionMatrix"));
        // Chunk VAOs bake in attrib pointer setup; rebuild them so they use the
        // new attribute locations from the reloaded shader.
        self.markAllDirty();
    }

    fn refreshTexture(self: *Self) void {
        if (!self.texture.dirty) return;
        self.texture = self.texture.reacquire();
    }

    pub fn markAllDirty(self: *Self) void {
        for (self.chunks) |*chunk| chunk.dirty = true;
    }

    /// Immediately rebuild every chunk from `layer`, regardless of viewport.
    /// Use this after a hot-reload of tile data so off-screen chunks don't
    /// carry stale GPU state until the camera reaches them.
    pub fn rebuildAll(self: *Self, layer: *const TileLayer) void {
        const tileset = layer.tileset orelse return;
        for (self.chunks) |*chunk| {
            buildChunk(self, chunk, tileset, layer);
            chunk.dirty = false;
        }
    }

    /// Mark the chunk containing tile (x, y) as dirty.
    /// Call this after updating tile data in the layer (e.g. after setTileData).
    /// The actual GPU rebuild is deferred until the next render() call.
    pub fn tileChanged(self: *Self, x: i32, y: i32) void {
        if (x < 0 or y < 0) return;
        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        const cx = ux / ChunkTiles;
        const cy = uy / ChunkTiles;
        if (cx >= self.chunksWide or cy >= self.chunksTall) return;
        self.chunks[cy * self.chunksWide + cx].dirty = true;
    }

    /// Render all chunks that intersect `viewport` (world-space rectangle).
    /// Dirty chunks are rebuilt (GPU upload) before drawing. The held shader
    /// and texture handles are refreshed first so hot-reloads land here.
    pub fn render(
        self: *Self,
        layer: *const TileLayer,
        mvp: zmath.Mat,
        viewport: RectF,
    ) void {
        self.refreshShader();
        self.refreshTexture();

        const tileset = layer.tileset orelse return;

        const mvp_arr = zmath.matToArr(mvp);
        const tw_f: f32 = @floatFromInt(layer.tileSize.x);
        const th_f: f32 = @floatFromInt(layer.tileSize.y);

        gl.useProgram(self.shader.val.program);
        gl.uniformMatrix4fv(self.uniformMvp, 1, gl.FALSE, @ptrCast(&mvp_arr[0]));

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.texture.val.texture);
        gl.uniform1i(gl.getUniformLocation(self.shader.val.program, "tex"), 0);

        for (self.chunks) |*chunk| {
            // --- Viewport culling ---
            const cl: f32 = @as(f32, @floatFromInt(chunk.originX)) * tw_f;
            const ct: f32 = @as(f32, @floatFromInt(chunk.originY)) * th_f;
            const cr: f32 = @as(f32, @floatFromInt(chunk.originX + chunk.tileW)) * tw_f;
            const cb: f32 = @as(f32, @floatFromInt(chunk.originY + chunk.tileH)) * th_f;
            if (cl >= viewport.r or cr <= viewport.l or
                ct >= viewport.b or cb <= viewport.t) continue;

            // --- Rebuild if dirty ---
            if (chunk.dirty) {
                buildChunk(self, chunk, tileset, layer);
                chunk.dirty = false;
            }

            if (chunk.numIndices == 0) continue;

            drawChunk(self, chunk);
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers

    fn tileUVs(tile_idx: i32, tileset: *const TileSet) RectF {
        if (tile_idx < 0) return .{ .l = 0.99, .t = 0.99, .r = 0.99, .b = 0.99 };
        const i: i32 = tile_idx;
        const tu: f32 = @floatFromInt(@rem(i, tileset.columns));
        const tv: f32 = @floatFromInt(@divTrunc(i, tileset.columns));
        const tsx: f32 = @floatFromInt(tileset.tileSize.x);
        const tsy: f32 = @floatFromInt(tileset.tileSize.y);
        const txw: f32 = @floatFromInt(tileset.textureSize.x);
        const txh: f32 = @floatFromInt(tileset.textureSize.y);
        const l = (tu * tsx) / txw;
        const t = (tv * tsy) / txh;
        return .{ .l = l, .t = t, .r = l + tsx / txw, .b = t + tsy / txh };
    }

    /// Rebuild a single chunk: walk its tiles, emit quads into scratch buffers,
    /// then upload to the chunk's GL objects and wire up the VAO.
    fn buildChunk(
        self: *Self,
        chunk: *TileChunk,
        tileset: *const TileSet,
        layer: *const TileLayer,
    ) void {
        var vi: usize = 0; // float index into scratchVerts / scratchTexcoords
        var ii: usize = 0; // index into scratchIndices

        const ts = layer.tileSize;

        for (0..chunk.tileH) |dy| {
            for (0..chunk.tileW) |dx| {
                const tx: i32 = @intCast(chunk.originX + dx);
                const ty: i32 = @intCast(chunk.originY + dy);
                const tv = layer.tileData(tx, ty);
                if (tv < 0) continue; // air — skip

                const uv = tileUVs(tv, tileset);
                const xf: f32 = @floatFromInt(tx * ts.x);
                const yf: f32 = @floatFromInt(ty * ts.y);
                const xf1: f32 = @floatFromInt((tx + 1) * ts.x);
                const yf1: f32 = @floatFromInt((ty + 1) * ts.y);

                // Vertex 0: top-left
                self.scratchVerts[vi + 0] = xf - 0.01;
                self.scratchVerts[vi + 1] = yf - 0.01;
                self.scratchTexcoords[vi + 0] = uv.l;
                self.scratchTexcoords[vi + 1] = uv.t;

                // Vertex 1: top-right
                self.scratchVerts[vi + 2] = xf1 + 0.01;
                self.scratchVerts[vi + 3] = yf - 0.01;
                self.scratchTexcoords[vi + 2] = uv.r;
                self.scratchTexcoords[vi + 3] = uv.t;

                // Vertex 2: bottom-right
                self.scratchVerts[vi + 4] = xf1 + 0.01;
                self.scratchVerts[vi + 5] = yf1 + 0.01;
                self.scratchTexcoords[vi + 4] = uv.r;
                self.scratchTexcoords[vi + 5] = uv.b;

                // Vertex 3: bottom-left
                self.scratchVerts[vi + 6] = xf - 0.01;
                self.scratchVerts[vi + 7] = yf1 + 0.01;
                self.scratchTexcoords[vi + 6] = uv.l;
                self.scratchTexcoords[vi + 7] = uv.b;

                // Two triangles: (0,1,3) and (1,2,3)
                const base: u16 = @intCast(vi / 2);
                self.scratchIndices[ii + 0] = base;
                self.scratchIndices[ii + 1] = base + 1;
                self.scratchIndices[ii + 2] = base + 3;
                self.scratchIndices[ii + 3] = base + 1;
                self.scratchIndices[ii + 4] = base + 2;
                self.scratchIndices[ii + 5] = base + 3;

                vi += 8;
                ii += 6;
            }
        }

        chunk.numIndices = ii;
        if (ii == 0) return; // Empty chunk (all air) — nothing to upload.

        const sz_verts: isize = @intCast(vi * @sizeOf(f32));
        const sz_inds: isize = @intCast(ii * @sizeOf(u16));

        // Upload data and record VAO state in one go.
        // Binding the VAO here stores the attrib pointer / IBO bindings permanently,
        // so drawChunk only needs to bind the VAO and call drawElements.
        gl.bindVertexArray(chunk.vao);

        gl.enableVertexAttribArray(self.attrCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, chunk.vboCoords);
        gl.bufferData(gl.ARRAY_BUFFER, sz_verts, &self.scratchVerts[0], gl.DYNAMIC_DRAW);
        gl.vertexAttribPointer(self.attrCoord, 2, gl.FLOAT, gl.FALSE, 0, null);

        gl.enableVertexAttribArray(self.attrTexcoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, chunk.vboTexcoords);
        gl.bufferData(gl.ARRAY_BUFFER, sz_verts, &self.scratchTexcoords[0], gl.DYNAMIC_DRAW);
        gl.vertexAttribPointer(self.attrTexcoord, 2, gl.FLOAT, gl.FALSE, 0, null);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, chunk.ibo);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, sz_inds, &self.scratchIndices[0], gl.DYNAMIC_DRAW);

        gl.bindVertexArray(0);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    }

    fn drawChunk(self: *const Self, chunk: *const TileChunk) void {
        _ = self;
        gl.bindVertexArray(chunk.vao);
        gl.drawElements(gl.TRIANGLES, @intCast(chunk.numIndices), gl.UNSIGNED_SHORT, null);
        gl.bindVertexArray(0);
    }
};
