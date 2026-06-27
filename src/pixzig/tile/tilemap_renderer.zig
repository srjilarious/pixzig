const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");
const xml = @import("xml");

const common = @import("../common.zig");
const textures = @import("../renderer/textures.zig");
const shaders = @import("../renderer/shaders.zig");
const resources = @import("../resources.zig");
const tilemap = @import("./tilemap.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Texture = textures.Texture;
const Shader = shaders.Shader;
const ShaderPool = resources.ShaderPool;
const ShaderHandle = resources.ShaderHandle;
const TextureAtlasPool = resources.TextureAtlasPool;
const TextureHandle = resources.TextureHandle;

const TileLayer = tilemap.TileLayer;
const TileMap = tilemap.TileMap;
const TileSet = tilemap.TileSet;
const TileIndexMap = @import("./tile_index_map.zig").TileIndexMap;

pub const TileMapRenderer = struct {
    mapSize: Vec2U = undefined,
    shader_handle: *ShaderHandle,
    shader_pool: *ShaderPool,
    shader: *const Shader,
    texture_handle: *TextureHandle,
    texture_pool: *TextureAtlasPool,
    texture: *const Texture,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboTexCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: []f32 = undefined,
    texCoords: []f32 = undefined,
    indices: []u16 = undefined,
    cpuBuffersInitialized: bool = false,
    alloc: std.mem.Allocator,
    attrCoord: c_uint = 0,
    attrTexCoord: c_uint = 0,
    uniformMVP: c_int = 0,
    numActualIndices: usize = 0,
    numBuffVals: usize = 0,
    tileIndexMap: TileIndexMap,

    pub fn init(
        alloc: std.mem.Allocator,
        shader_pool: *ShaderPool,
        texture_pool: *TextureAtlasPool,
    ) !TileMapRenderer {
        const shader_handle = shader_pool.acquire() orelse return error.NoShaderInPool;
        errdefer shader_pool.release(shader_handle);
        const texture_handle = texture_pool.acquire() orelse return error.NoTextureInPool;
        errdefer texture_pool.release(texture_handle);

        var tr = TileMapRenderer{
            .shader_handle = shader_handle,
            .shader_pool = shader_pool,
            .shader = &shader_handle.val,
            .texture_handle = texture_handle,
            .texture_pool = texture_pool,
            .texture = &texture_handle.val,
            .alloc = alloc,
            .tileIndexMap = TileIndexMap.init(alloc),
        };

        gl.genVertexArrays(1, &tr.vao);

        gl.genBuffers(1, &tr.vboVertices);
        gl.genBuffers(1, &tr.vboTexCoords);
        gl.genBuffers(1, &tr.vboIndices);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.TEXTURE_2D);

        tr.cacheShaderLocations();

        return tr;
    }

    pub fn deinit(self: *TileMapRenderer) void {
        self.texture_pool.release(self.texture_handle);
        self.shader_pool.release(self.shader_handle);
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboTexCoords);
        gl.deleteBuffers(1, &self.vboIndices);
        if (self.cpuBuffersInitialized) {
            self.alloc.free(self.vertices);
            self.alloc.free(self.texCoords);
            self.alloc.free(self.indices);
        }
        self.tileIndexMap.deinit();
    }

    fn cacheShaderLocations(self: *TileMapRenderer) void {
        self.attrCoord = @intCast(gl.getAttribLocation(self.shader.program, "coord3d"));
        self.attrTexCoord = @intCast(gl.getAttribLocation(self.shader.program, "texcoord"));
        self.uniformMVP = @intCast(gl.getUniformLocation(self.shader.program, "projectionMatrix"));
    }

    fn refreshShader(self: *TileMapRenderer) void {
        if (!self.shader_handle.dirty) return;
        const new_handle = self.shader_pool.acquire() orelse return;
        self.shader_pool.release(self.shader_handle);
        self.shader_handle = new_handle;
        self.shader = &new_handle.val;
        self.cacheShaderLocations();
    }

    fn refreshTexture(self: *TileMapRenderer) void {
        if (!self.texture_handle.dirty) return;
        const new_handle = self.texture_pool.acquire() orelse return;
        self.texture_pool.release(self.texture_handle);
        self.texture_handle = new_handle;
        self.texture = &new_handle.val;
    }

    fn tileCoords(idx: i32, tileset: *TileSet) RectF {
        const i: i32 = @intCast(idx);
        if (idx < 0) {
            return .{
                .l = 0.99,
                .t = 0.99,
                .r = 0.99,
                .b = 0.99,
            };
        }

        const tu: f32 = @as(f32, @floatFromInt(@rem(i, tileset.columns)));
        const tv: f32 = @as(f32, @floatFromInt(@divTrunc(i, tileset.columns)));
        const tsx: f32 = @floatFromInt(tileset.tileSize.x);
        const tsy: f32 = @floatFromInt(tileset.tileSize.y);
        const txw: f32 = @floatFromInt(tileset.textureSize.x);
        const txh: f32 = @floatFromInt(tileset.textureSize.y);
        const l = (tu * tsx) / txw;
        const t = (tv * tsy) / txh;
        return .{
            .l = l,
            .t = t,
            .r = l + tsx / txw,
            .b = t + tsy / txh,
        };
    }

    fn dump(self: *TileMapRenderer) void {
        std.log.debug("*****************\n", .{});

        std.log.debug("### tileIndexMap:\n", .{});
        for (self.tileIndexMap.arr.items, 0..) |kv, idx| {
            std.log.debug("[{}] tIdx={}, bIdx={}\n", .{ idx, kv.tileIdx, kv.bufferIdx });
            var vIdx = (kv.bufferIdx) * 8;
            var iIdx = (kv.bufferIdx) * 6;

            std.log.debug("Vertices: \n", .{});
            for (0..4) |_| {
                std.log.debug("({}, {}) ", .{ @as(i32, @intFromFloat(self.vertices[vIdx])), @as(i32, @intFromFloat(self.vertices[vIdx + 1])) });
                vIdx += 2;
            }
            std.log.debug("\n", .{});

            std.log.debug("Indices: \n", .{});
            for (0..2) |_| {
                std.log.debug("({}, {}, {}) ", .{ self.indices[iIdx], self.indices[iIdx + 1], self.indices[iIdx + 2] });
                iIdx += 3;
            }
            std.log.debug("\n\n", .{});
        }

        std.log.debug("*****************\n", .{});
    }

    pub fn tileChanged(self: *TileMapRenderer, tileset: *TileSet, tiles: *TileLayer, loc: Vec2I, tile: i32) !void {
        const layerWidth: usize = @intCast(tiles.size.x);
        const layerHeight: usize = @intCast(tiles.size.y);
        if (loc.x < 0 or loc.x >= layerWidth) return;
        if (loc.y < 0 or loc.y >= layerHeight) return;

        const tileIdx: usize = @intCast(loc.y * @as(i32, @intCast(layerWidth)) + loc.x);

        // Check for a tile add/change
        if (tile >= 0) {
            // if location exists in map
            if (self.tileIndexMap.getBuffIndex(tileIdx)) |buffIdx| {
                // Update buffer data
                const vertIdx = buffIdx * 8;
                const indicesIdx = buffIdx * 6;
                self.setTileRenderData(loc, vertIdx, indicesIdx, tiles.tileSize, tile, tileset);
            }
            // if location no in map
            else {
                // Add to end of buffer
                const vertIdx = self.numBuffVals * 8;
                const indicesIdx = self.numBuffVals * 6;
                self.setTileRenderData(loc, vertIdx, indicesIdx, tiles.tileSize, tile, tileset);

                _ = try self.tileIndexMap.put(tileIdx, self.numBuffVals);

                self.numBuffVals += 1;
                self.numActualIndices += 6;
            }
        }
        // A tile is being removed.
        else {
            //std.debug.print("Removing block at {}, {}\n", .{ loc.x, loc.y });

            // Find the bufferIndex if location exists in map
            if (self.tileIndexMap.getBuffIndex(tileIdx)) |buffIdx| {
                const lastBuffIdx = self.numBuffVals - 1;

                // If buffIdx is the last, simply stop drawing its indices
                if (buffIdx == lastBuffIdx) {
                    const rem = self.tileIndexMap.removeByTileIndex(tileIdx);
                    std.debug.assert(rem);
                    self.numBuffVals -= 1;
                    self.numActualIndices -= 6;
                }
                // Otherwise, the block to remove is somewhere in the middle,
                // so swap the last block with it updating our map indices.
                else {
                    // Update buffer data
                    const destVertIdx = buffIdx * 8;

                    const srcVertIdx = (lastBuffIdx) * 8;
                    const lastK = self.tileIndexMap.getTileIndex(lastBuffIdx).?;

                    // Copy from the end into the slot we want to erase
                    // Note we don't want to change the indices, since we're moving the vertex data
                    // the indices in that slot should stay the same.
                    @memcpy(self.vertices[destVertIdx .. destVertIdx + 8], self.vertices[srcVertIdx .. srcVertIdx + 8]);
                    @memcpy(self.texCoords[destVertIdx .. destVertIdx + 8], self.texCoords[srcVertIdx .. srcVertIdx + 8]);

                    // Remove the bufferIndex of the removed item.
                    _ = self.tileIndexMap.removeByTileIndex(tileIdx);
                    _ = self.tileIndexMap.update(lastK, buffIdx);

                    self.numBuffVals -= 1;
                    self.numActualIndices -= 6;
                }
            } else {
                std.log.err("No tile set in position!\n", .{});
            }
        }

        // self.dump();
    }

    fn setTileRenderData(self: *TileMapRenderer, loc: Vec2I, vertIdx: usize, indicesIdx: usize, ts: Vec2I, tile: i32, tileset: *TileSet) void {
        const uv = tileCoords(tile, tileset);
        var idx = vertIdx;
        const x = loc.x;
        const y = loc.y;

        // Coord 1
        self.vertices[idx] = @as(f32, @floatFromInt(x * ts.x)) - 0.01;
        self.vertices[idx + 1] = @as(f32, @floatFromInt(y * ts.y)) - 0.01;
        self.texCoords[idx] = uv.l;
        self.texCoords[idx + 1] = uv.t;
        idx += 2;

        // Coord 2
        self.vertices[idx] = @as(f32, @floatFromInt((x + 1) * ts.x)) + 0.01;
        self.vertices[idx + 1] = @as(f32, @floatFromInt(y * ts.y)) - 0.01;
        self.texCoords[idx] = uv.r;
        self.texCoords[idx + 1] = uv.t;
        idx += 2;

        // Coord 3
        self.vertices[idx] = @as(f32, @floatFromInt((x + 1) * ts.x)) + 0.01;
        self.vertices[idx + 1] = @as(f32, @floatFromInt((y + 1) * ts.y)) + 0.01;
        self.texCoords[idx] = uv.r;
        self.texCoords[idx + 1] = uv.b;
        idx += 2;

        // Coord 4
        self.vertices[idx] = @as(f32, @floatFromInt(x * ts.x)) - 0.01;
        self.vertices[idx + 1] = @as(f32, @floatFromInt((y + 1) * ts.y)) + 0.01;
        self.texCoords[idx] = uv.l;
        self.texCoords[idx + 1] = uv.b;
        idx += 2;

        // const baseIdx: u16 = 4 * @as(u16, @intCast(y*@as(i32, @intCast(layerWidth)) + x));
        const baseIdx: u16 = @divTrunc(@as(u16, @intCast(idx - 8)), 2);
        self.indices[indicesIdx] = baseIdx;
        self.indices[indicesIdx + 1] = baseIdx + 1;
        self.indices[indicesIdx + 2] = baseIdx + 3;
        self.indices[indicesIdx + 3] = baseIdx + 1;
        self.indices[indicesIdx + 4] = baseIdx + 2;
        self.indices[indicesIdx + 5] = baseIdx + 3;
    }

    pub fn recreateVertices(self: *TileMapRenderer, tileset: *TileSet, tiles: *TileLayer) !void {

        // const tw = tileset.tileSize.x;
        // const th = tileset.tileSize.y;
        const layerWidth: usize = @intCast(tiles.size.x);
        const layerHeight: usize = @intCast(tiles.size.y);
        self.mapSize = .{ .x = @intCast(layerWidth), .y = @intCast(layerHeight) };
        const mapSize: i32 = @intCast(layerWidth * layerHeight);
        _ = mapSize;
        const numVerts: usize = @intCast(2 * 4 * layerWidth * layerHeight);
        const numIndices: usize = @intCast(6 * layerWidth * layerHeight);

        std.log.debug("Creating map render data: verts={}, texCoords={}, indices={}", .{ numVerts, numVerts, numIndices });

        // Allocate new arrays first so a partial failure leaves the old ones intact.
        const newVertices = try self.alloc.alloc(f32, numVerts);
        errdefer self.alloc.free(newVertices);

        const newTexCoords = try self.alloc.alloc(f32, numVerts);
        errdefer self.alloc.free(newTexCoords);

        const newIndices = try self.alloc.alloc(u16, numIndices);

        // All allocations succeeded; free previous CPU arrays if they existed.
        if (self.cpuBuffersInitialized) {
            self.alloc.free(self.vertices);
            self.alloc.free(self.texCoords);
            self.alloc.free(self.indices);
        }

        self.vertices = newVertices;
        self.texCoords = newTexCoords;
        self.indices = newIndices;
        self.cpuBuffersInitialized = true;

        std.log.debug("Creating {} vertices\n", .{self.vertices.len});
        // self.tileIndexMap.clearRetainingCapacity();
        var buffIdx: usize = 0;
        var idx: usize = 0;
        var indicesIdx: usize = 0;
        for (0..layerHeight) |yy| {
            for (0..layerWidth) |xx| {
                const y: i32 = @intCast(yy);
                const x: i32 = @intCast(xx);
                const tile = tiles.tileData(x, y);
                if (tile < 0) continue;

                // Keep a map of which tile index maps to what buffer index.
                // This lets us handle adding/removing tiles dynamically.
                const tileIdx = y * @as(i32, @intCast(layerWidth)) + x;
                _ = try self.tileIndexMap.put(@intCast(tileIdx), buffIdx);
                // std.debug.print("Placing tileIdx={} in buffIdx={}\n", .{tileIdx, buffIdx});
                self.setTileRenderData(.{ .x = x, .y = y }, idx, indicesIdx, tileset.tileSize, tile, tileset);
                idx += 8;
                indicesIdx += 6;

                // Since we skip empty tiles, keep track of which index in the buffer each drawn tile
                // is going to map to.
                buffIdx += 1;
            }
        }

        self.numActualIndices = indicesIdx;
        self.numBuffVals = buffIdx;
        std.log.info("TileMapRenderer.recreateVertices finished.", .{});
    }

    pub fn draw(self: *TileMapRenderer, tiles: *TileLayer, mvp: zmath.Mat) !void {
        self.refreshShader();
        self.refreshTexture();

        const mvpArr = zmath.matToArr(mvp);
        const layerWidth: usize = @intCast(tiles.size.x);
        const layerHeight: usize = @intCast(tiles.size.y);
        const mapSize: i32 = @intCast(layerWidth * layerHeight);
        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&mvpArr[0]));

        // Set 'tex' to use texture unit 0
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.texture.texture);
        gl.uniform1i(gl.getUniformLocation(self.shader.program, "tex"), 0);

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * mapSize), &self.vertices[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrCoord, 2, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.enableVertexAttribArray(self.attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * mapSize), &self.texCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrTexCoord, 2, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(u16) * self.numActualIndices), &self.indices[0], gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(self.numActualIndices), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrTexCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    }
};
