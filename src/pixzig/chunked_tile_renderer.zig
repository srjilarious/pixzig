// zig fmt: off
const std = @import("std");
const gl  = @import("zopengl").bindings;
const zmath = @import("zmath");

const common  = @import("./common.zig");
const textures = @import("./renderer/textures.zig");
const shaders  = @import("./renderer/shaders.zig");
const tile_mod = @import("./tile.zig");

const RectF   = common.RectF;
const Texture = textures.Texture;
const Shader  = shaders.Shader;
const TileSet = tile_mod.TileSet;
const TileLayer = tile_mod.TileLayer;

/// Tiles per chunk along each axis. 32×32 = 1024 tiles/chunk.
pub const ChunkTiles: u32 = 32;

const MaxTilesPerChunk   = ChunkTiles * ChunkTiles;  // 1024
const MaxVertsPerChunk   = MaxTilesPerChunk * 4;     // 4096 vertices
const MaxFloatsPerChunk  = MaxVertsPerChunk * 2;     // 8192 floats (x,y per vert)
const MaxIndicesPerChunk = MaxTilesPerChunk * 6;     // 6144 u16 indices

/// Per-chunk GPU state. Holds only GL handles and bookkeeping — no CPU buffers.
/// A single shared scratch buffer in ChunkedTileMapRenderer is used for builds.
const TileChunk = struct {
    vao:          u32,
    vbo_coords:   u32,
    vbo_texcoords: u32,
    ibo:          u32,
    num_indices:  usize,
    dirty:        bool,
    origin_x:     u32,   // tile-space top-left corner of this chunk
    origin_y:     u32,
    tile_w:       u32,   // actual tile count (≤ ChunkTiles; may be less at map edges)
    tile_h:       u32,
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
pub const ChunkedTileMapRenderer = struct {
    alloc:         std.mem.Allocator,
    chunks:        []TileChunk,
    chunks_wide:   u32,
    chunks_tall:   u32,
    shader:        *const Shader,
    attr_coord:    c_uint,
    attr_texcoord: c_uint,
    uniform_mvp:   c_int,
    // One shared scratch buffer; reused for every chunk build.
    scratch_verts:     []f32,
    scratch_texcoords: []f32,
    scratch_indices:   []u16,

    const Self = @This();

    /// Allocates the chunk grid and creates all GL objects.
    /// The layer's size is read here to determine the chunk layout; tile data
    /// is read lazily on the first render() call (all chunks start dirty=true).
    pub fn init(
        alloc:  std.mem.Allocator,
        shader: *const Shader,
        layer:  *const TileLayer,
    ) !Self {
        const map_w: u32 = @intCast(layer.size.x);
        const map_h: u32 = @intCast(layer.size.y);

        const chunks_wide = (map_w + ChunkTiles - 1) / ChunkTiles;
        const chunks_tall = (map_h + ChunkTiles - 1) / ChunkTiles;
        const num_chunks  = chunks_wide * chunks_tall;

        const chunks = try alloc.alloc(TileChunk, num_chunks);
        errdefer alloc.free(chunks);

        for (0..chunks_tall) |cy| {
            for (0..chunks_wide) |cx| {
                const idx      = cy * chunks_wide + cx;
                const origin_x: u32 = @intCast(cx * ChunkTiles);
                const origin_y: u32 = @intCast(cy * ChunkTiles);

                var chunk = TileChunk{
                    .vao          = 0,
                    .vbo_coords   = 0,
                    .vbo_texcoords = 0,
                    .ibo          = 0,
                    .num_indices  = 0,
                    .dirty        = true,
                    .origin_x     = origin_x,
                    .origin_y     = origin_y,
                    .tile_w       = @min(ChunkTiles, map_w - origin_x),
                    .tile_h       = @min(ChunkTiles, map_h - origin_y),
                };

                gl.genVertexArrays(1, &chunk.vao);
                gl.genBuffers(1, &chunk.vbo_coords);
                gl.genBuffers(1, &chunk.vbo_texcoords);
                gl.genBuffers(1, &chunk.ibo);

                chunks[idx] = chunk;
            }
        }

        const scratch_verts     = try alloc.alloc(f32,  MaxFloatsPerChunk);
        errdefer alloc.free(scratch_verts);
        const scratch_texcoords = try alloc.alloc(f32,  MaxFloatsPerChunk);
        errdefer alloc.free(scratch_texcoords);
        const scratch_indices   = try alloc.alloc(u16, MaxIndicesPerChunk);
        errdefer alloc.free(scratch_indices);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.TEXTURE_2D);

        return .{
            .alloc         = alloc,
            .chunks        = chunks,
            .chunks_wide   = chunks_wide,
            .chunks_tall   = chunks_tall,
            .shader        = shader,
            .attr_coord    = @intCast(gl.getAttribLocation(shader.program, "coord3d")),
            .attr_texcoord = @intCast(gl.getAttribLocation(shader.program, "texcoord")),
            .uniform_mvp   = @intCast(gl.getUniformLocation(shader.program, "projectionMatrix")),
            .scratch_verts     = scratch_verts,
            .scratch_texcoords = scratch_texcoords,
            .scratch_indices   = scratch_indices,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.chunks) |*chunk| {
            gl.deleteVertexArrays(1, &chunk.vao);
            gl.deleteBuffers(1, &chunk.vbo_coords);
            gl.deleteBuffers(1, &chunk.vbo_texcoords);
            gl.deleteBuffers(1, &chunk.ibo);
        }
        self.alloc.free(self.chunks);
        self.alloc.free(self.scratch_verts);
        self.alloc.free(self.scratch_texcoords);
        self.alloc.free(self.scratch_indices);
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
        if (cx >= self.chunks_wide or cy >= self.chunks_tall) return;
        self.chunks[cy * self.chunks_wide + cx].dirty = true;
    }

    /// Render all chunks that intersect `viewport` (world-space rectangle).
    /// Dirty chunks are rebuilt (GPU upload) before drawing.
    /// The texture must already be bound to GL_TEXTURE0 by the caller.
    pub fn render(
        self:     *Self,
        texture:  *Texture,
        layer:    *const TileLayer,
        mvp:      zmath.Mat,
        viewport: RectF,
    ) void {
        const tileset = layer.tileset orelse return;

        const mvp_arr = zmath.matToArr(mvp);
        const tw_f: f32 = @floatFromInt(layer.tileSize.x);
        const th_f: f32 = @floatFromInt(layer.tileSize.y);

        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniform_mvp, 1, gl.FALSE, @ptrCast(&mvp_arr[0]));

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, texture.texture);
        gl.uniform1i(gl.getUniformLocation(self.shader.program, "tex"), 0);

        for (self.chunks) |*chunk| {
            // --- Viewport culling ---
            const cl: f32 = @as(f32, @floatFromInt(chunk.origin_x)) * tw_f;
            const ct: f32 = @as(f32, @floatFromInt(chunk.origin_y)) * th_f;
            const cr: f32 = @as(f32, @floatFromInt(chunk.origin_x + chunk.tile_w)) * tw_f;
            const cb: f32 = @as(f32, @floatFromInt(chunk.origin_y + chunk.tile_h)) * th_f;
            if (cl >= viewport.r or cr <= viewport.l or
                ct >= viewport.b or cb <= viewport.t) continue;

            // --- Rebuild if dirty ---
            if (chunk.dirty) {
                buildChunk(self, chunk, tileset, layer);
                chunk.dirty = false;
            }

            if (chunk.num_indices == 0) continue;

            drawChunk(self, chunk);
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers

    fn tileUVs(tile_idx: i32, tileset: *const TileSet) RectF {
        if (tile_idx < 0) return .{ .l = 0.99, .t = 0.99, .r = 0.99, .b = 0.99 };
        const i: i32    = tile_idx;
        const tu: f32   = @floatFromInt(@rem(i, tileset.columns));
        const tv: f32   = @floatFromInt(@divTrunc(i, tileset.columns));
        const tsx: f32  = @floatFromInt(tileset.tileSize.x);
        const tsy: f32  = @floatFromInt(tileset.tileSize.y);
        const txw: f32  = @floatFromInt(tileset.textureSize.x);
        const txh: f32  = @floatFromInt(tileset.textureSize.y);
        const l = (tu * tsx) / txw;
        const t = (tv * tsy) / txh;
        return .{ .l = l, .t = t, .r = l + tsx / txw, .b = t + tsy / txh };
    }

    /// Rebuild a single chunk: walk its tiles, emit quads into scratch buffers,
    /// then upload to the chunk's GL objects and wire up the VAO.
    fn buildChunk(
        self:    *Self,
        chunk:   *TileChunk,
        tileset: *const TileSet,
        layer:   *const TileLayer,
    ) void {
        var vi: usize = 0;  // float index into scratch_verts / scratch_texcoords
        var ii: usize = 0;  // index into scratch_indices

        const ts = layer.tileSize;

        for (0..chunk.tile_h) |dy| {
            for (0..chunk.tile_w) |dx| {
                const tx: i32 = @intCast(chunk.origin_x + dx);
                const ty: i32 = @intCast(chunk.origin_y + dy);
                const tv = layer.tileData(tx, ty);
                if (tv < 0) continue;  // air — skip

                const uv   = tileUVs(tv, tileset);
                const xf:  f32 = @floatFromInt(tx * ts.x);
                const yf:  f32 = @floatFromInt(ty * ts.y);
                const xf1: f32 = @floatFromInt((tx + 1) * ts.x);
                const yf1: f32 = @floatFromInt((ty + 1) * ts.y);

                // Vertex 0: top-left
                self.scratch_verts[vi + 0] = xf  - 0.01;
                self.scratch_verts[vi + 1] = yf  - 0.01;
                self.scratch_texcoords[vi + 0] = uv.l;
                self.scratch_texcoords[vi + 1] = uv.t;

                // Vertex 1: top-right
                self.scratch_verts[vi + 2] = xf1 + 0.01;
                self.scratch_verts[vi + 3] = yf  - 0.01;
                self.scratch_texcoords[vi + 2] = uv.r;
                self.scratch_texcoords[vi + 3] = uv.t;

                // Vertex 2: bottom-right
                self.scratch_verts[vi + 4] = xf1 + 0.01;
                self.scratch_verts[vi + 5] = yf1 + 0.01;
                self.scratch_texcoords[vi + 4] = uv.r;
                self.scratch_texcoords[vi + 5] = uv.b;

                // Vertex 3: bottom-left
                self.scratch_verts[vi + 6] = xf  - 0.01;
                self.scratch_verts[vi + 7] = yf1 + 0.01;
                self.scratch_texcoords[vi + 6] = uv.l;
                self.scratch_texcoords[vi + 7] = uv.b;

                // Two triangles: (0,1,3) and (1,2,3)
                const base: u16 = @intCast(vi / 2);
                self.scratch_indices[ii + 0] = base;
                self.scratch_indices[ii + 1] = base + 1;
                self.scratch_indices[ii + 2] = base + 3;
                self.scratch_indices[ii + 3] = base + 1;
                self.scratch_indices[ii + 4] = base + 2;
                self.scratch_indices[ii + 5] = base + 3;

                vi += 8;
                ii += 6;
            }
        }

        chunk.num_indices = ii;
        if (ii == 0) return;  // Empty chunk (all air) — nothing to upload.

        const sz_verts: isize = @intCast(vi * @sizeOf(f32));
        const sz_inds:  isize = @intCast(ii * @sizeOf(u16));

        // Upload data and record VAO state in one go.
        // Binding the VAO here stores the attrib pointer / IBO bindings permanently,
        // so drawChunk only needs to bind the VAO and call drawElements.
        gl.bindVertexArray(chunk.vao);

        gl.enableVertexAttribArray(self.attr_coord);
        gl.bindBuffer(gl.ARRAY_BUFFER, chunk.vbo_coords);
        gl.bufferData(gl.ARRAY_BUFFER, sz_verts, &self.scratch_verts[0], gl.DYNAMIC_DRAW);
        gl.vertexAttribPointer(self.attr_coord, 2, gl.FLOAT, gl.FALSE, 0, null);

        gl.enableVertexAttribArray(self.attr_texcoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, chunk.vbo_texcoords);
        gl.bufferData(gl.ARRAY_BUFFER, sz_verts, &self.scratch_texcoords[0], gl.DYNAMIC_DRAW);
        gl.vertexAttribPointer(self.attr_texcoord, 2, gl.FLOAT, gl.FALSE, 0, null);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, chunk.ibo);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, sz_inds, &self.scratch_indices[0], gl.DYNAMIC_DRAW);

        gl.bindVertexArray(0);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    }

    fn drawChunk(self: *const Self, chunk: *const TileChunk) void {
        _ = self;
        gl.bindVertexArray(chunk.vao);
        gl.drawElements(gl.TRIANGLES, @intCast(chunk.num_indices), gl.UNSIGNED_SHORT, null);
        gl.bindVertexArray(0);
    }
};
