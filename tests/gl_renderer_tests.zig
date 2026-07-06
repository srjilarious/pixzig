const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const zmath = pixzig.zmath;

const tile = pixzig.tile;
const TileMap = tile.TileMap;
const TileLayer = tile.TileLayer;
const TileSet = tile.TileSet;
const ChunkedTiledRenderer = tile.ChunkedTiledRenderer;
const RectF = pixzig.RectF;
const GlTestContext = pixzig.GlTestContext;

fn glCtx() *GlTestContext {
    return GlTestContext.get();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn makeLayer(alloc: std.mem.Allocator) !TileLayer {
    return TileLayer.initEmpty(alloc, .{ .x = 4, .y = 4 }, .{ .x = 8, .y = 8 });
}

fn addZProp(alloc: std.mem.Allocator, layer: *TileLayer, z: f32) !void {
    var buf: [32]u8 = undefined;
    const z_str = try std.fmt.bufPrint(&buf, "{d}", .{z});
    const name = try alloc.dupe(u8, "z");
    errdefer alloc.free(name);
    const val = try alloc.dupe(u8, z_str);
    errdefer alloc.free(val);
    try layer.properties.append(alloc, .{ .name = name, .value = val });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

pub fn glContextInitTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    _ = glCtx();
}

pub fn spriteBatchSmokeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var shader_pool = try ctx.makeManagedShader(alloc);
    defer shader_pool.deinit();

    var batch = try pixzig.renderer.SpriteBatchQueue.init(alloc, &shader_pool);
    defer batch.deinit();

    const mvp = zmath.identity();
    batch.begin(mvp);
    batch.end();
}

pub fn tiledReloadAddsLayerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var shader_pool = try ctx.makeManagedShader(alloc);
    defer shader_pool.deinit();
    var tex_pool = try ctx.makeDummyManagedTexture(alloc);
    defer tex_pool.deinit();

    // Start with one layer.
    var map1 = try TileMap.init(alloc);
    defer map1.deinit();
    const layer1 = try makeLayer(alloc);
    try map1.layers.append(alloc, layer1);

    var renderer = try ChunkedTiledRenderer.init(alloc, &map1, &shader_pool, &tex_pool);
    defer renderer.deinit();

    try testz.expectEqual(renderer.entries.len, 1);

    // Reload with two layers.
    var map2 = try TileMap.init(alloc);
    defer map2.deinit();
    try map2.layers.append(alloc, try makeLayer(alloc));
    try map2.layers.append(alloc, try makeLayer(alloc));

    try renderer.reload(&map2);

    try testz.expectEqual(renderer.entries.len, 2);
}

pub fn tiledReloadRemovesLayerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var shader_pool = try ctx.makeManagedShader(alloc);
    defer shader_pool.deinit();
    var tex_pool = try ctx.makeDummyManagedTexture(alloc);
    defer tex_pool.deinit();

    // Start with two layers.
    var map1 = try TileMap.init(alloc);
    defer map1.deinit();
    try map1.layers.append(alloc, try makeLayer(alloc));
    try map1.layers.append(alloc, try makeLayer(alloc));

    var renderer = try ChunkedTiledRenderer.init(alloc, &map1, &shader_pool, &tex_pool);
    defer renderer.deinit();

    try testz.expectEqual(renderer.entries.len, 2);

    // Reload with one layer.
    var map2 = try TileMap.init(alloc);
    defer map2.deinit();
    try map2.layers.append(alloc, try makeLayer(alloc));

    try renderer.reload(&map2);

    try testz.expectEqual(renderer.entries.len, 1);
}

pub fn tiledReloadZOrderTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var shader_pool = try ctx.makeManagedShader(alloc);
    defer shader_pool.deinit();
    var tex_pool = try ctx.makeDummyManagedTexture(alloc);
    defer tex_pool.deinit();

    // Initial map: both layers at z=0, order by layer_index.
    var map1 = try TileMap.init(alloc);
    defer map1.deinit();
    try map1.layers.append(alloc, try makeLayer(alloc));
    try map1.layers.append(alloc, try makeLayer(alloc));

    var renderer = try ChunkedTiledRenderer.init(alloc, &map1, &shader_pool, &tex_pool);
    defer renderer.deinit();

    // Reload: layer 0 gets z=1, layer 1 stays z=0.
    // After sort, layer 1 (z=0) should be first, layer 0 (z=1) second.
    var map2 = try TileMap.init(alloc);
    defer map2.deinit();
    var la = try makeLayer(alloc);
    try addZProp(alloc, &la, 1.0);
    var lb = try makeLayer(alloc);
    try addZProp(alloc, &lb, 0.0);
    try map2.layers.append(alloc, la);
    try map2.layers.append(alloc, lb);

    try renderer.reload(&map2);

    try testz.expectEqual(renderer.entries.len, 2);
    // entries are sorted ascending by z; entry[0] should have z=0, entry[1] z=1.
    try testz.expectEqual(renderer.entries[0].z, @as(f32, 0.0));
    try testz.expectEqual(renderer.entries[1].z, @as(f32, 1.0));
    // Verify original layer indices are tracked correctly.
    try testz.expectEqual(renderer.entries[0].layer_index, @as(usize, 1));
    try testz.expectEqual(renderer.entries[1].layer_index, @as(usize, 0));
}
