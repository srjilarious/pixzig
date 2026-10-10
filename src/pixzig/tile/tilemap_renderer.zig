const std = @import("std");
const zmath = @import("zmath");

const common = @import("../common.zig");
const resources = @import("../resources.zig");
const shaders = @import("../renderer/shaders.zig");
const camera_mod = @import("../camera.zig");
const window_mod = @import("../window.zig");
const tilemap = @import("./tilemap.zig");
const ChunkedTiledLayerRenderer = @import("./chunked_tile_renderer.zig").ChunkedTiledLayerRenderer;

const RectF = common.RectF;
const Vec2F = common.Vec2F;
const ResourceManager = resources.ResourceManager;
const ShaderHandle = resources.ShaderHandle;
const TileMapHandle = resources.TileMapHandle;
const TileMap = tilemap.TileMap;
const Camera2D = camera_mod.Camera2D;
const Viewport = window_mod.Viewport;

const LayerEntry = struct {
    renderer: ChunkedTiledLayerRenderer,
    parallaxX: f32,
    parallaxY: f32,
    layerIndex: usize,
    /// Draw order depth. Layers are rendered lowest-z-first. Set via the
    /// `z` float custom property on the layer in Tiled; defaults to 0.
    z: f32,
};

fn entryLessThan(_: void, a: LayerEntry, b: LayerEntry) bool {
    if (a.z != b.z) return a.z < b.z;
    return a.layerIndex < b.layerIndex;
}

/// Renders every tile layer of a map registered with the `ResourceManager`,
/// one chunked layer renderer per layer.
///
/// The renderer is built from a map *name*, and works the rest out itself: it
/// acquires the tilemap handle, borrows the built-in texture shader, and
/// resolves each layer's tileset image (the `<image source>` in the .tmx) to a
/// texture via `ResourceManager.tilesetTexture`. Nothing else needs passing in,
/// and the render calls take only a camera and a viewport.
///
/// Per-layer properties read from Tiled custom properties:
///   `z`          - draw order depth (f32, default 0.0); lower renders first
///   `parallax_x` - horizontal scroll factor (f32, default 1.0)
///   `parallax_y` - vertical scroll factor   (f32, default 1.0)
///
/// Entries are sorted by z ascending and stay in that order.
///
/// Hot-reload is handled here: every render call first picks up a reloaded
/// .tmx and rebuilds its layers. Call `sync` directly when something outside
/// the renderer (camera bounds, spawn points) is derived from the map too.
pub const TileMapRenderer = struct {
    alloc: std.mem.Allocator,
    /// Where new layer textures come from, including after a reload.
    resources: *ResourceManager,
    /// Our own reference to the map, released in `deinit`. Re-acquired by
    /// `sync` when the .tmx is hot-reloaded.
    map: *TileMapHandle,
    entries: []LayerEntry,
    /// Our own reference, so `reload` can still build renderers for newly
    /// added layers. Released in `deinit`.
    shader: *ShaderHandle,

    const Self = @This();

    /// Builds a renderer for the tilemap registered as `mapName` (by
    /// `loadTileMap` or `addTileMap`).
    pub fn init(alloc: std.mem.Allocator, res: *ResourceManager, mapName: []const u8) !Self {
        const map = try res.acquireTileMap(mapName);
        errdefer map.release();

        const shader = try res.getShader(shaders.TextureShader);

        const entries = try buildEntries(alloc, res, shader, &map.val);
        errdefer {
            for (entries) |*e| e.renderer.deinit();
            alloc.free(entries);
        }

        return .{
            .alloc = alloc,
            .resources = res,
            .map = map,
            .entries = entries,
            .shader = shader.retain(),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries) |*e| e.renderer.deinit();
        self.alloc.free(self.entries);
        self.shader.release();
        self.map.release();
    }

    /// The map this renderer draws. Valid until the next `sync`, which swaps
    /// in the reloaded generation.
    pub fn tileMap(self: *const Self) *TileMap {
        return &self.map.val;
    }

    /// Picks up a hot-reloaded .tmx: re-acquires the map handle and rebuilds
    /// every layer from it. Returns true when that happened, so a caller can
    /// refresh whatever else it derived from the map (camera bounds, object
    /// positions). Every render call does this first, so calling it is only
    /// necessary for those extra derived values.
    ///
    /// A rebuild that fails is logged and leaves the previous layers drawing.
    pub fn sync(self: *Self) bool {
        if (!self.map.dirty) return false;
        self.map = self.map.reacquire();
        self.reload() catch |err| {
            std.log.err("TileMapRenderer: could not rebuild after a map reload: {}", .{err});
        };
        return true;
    }

    /// Marks the chunk holding tile (x, y) of the layer at `layerIndex` dirty,
    /// after the game changed that tile (e.g. with `TileLayer.setTileData`).
    /// The chunk is rebuilt on its next render. An index that matches no
    /// layer is ignored.
    pub fn tileChanged(self: *Self, layerIndex: usize, x: i32, y: i32) void {
        for (self.entries) |*entry| {
            if (entry.layerIndex == layerIndex) {
                entry.renderer.tileChanged(x, y);
                return;
            }
        }
    }

    /// Mark all chunks in all layers as dirty. Chunks rebuild lazily as they
    /// come into view. Use rebuildAll for an immediate forced rebuild.
    pub fn markAllDirty(self: *Self) void {
        for (self.entries) |*e| e.renderer.markAllDirty();
    }

    /// Immediately rebuild every chunk in every layer from the current map
    /// data, regardless of viewport. Only safe when the map's layer count and
    /// structure are unchanged -- use `reload` after a hot-reload that may
    /// have added, removed, or reordered layers.
    pub fn rebuildAll(self: *Self) void {
        const map = &self.map.val;
        for (self.entries) |*entry| {
            const layer = map.layerByIndex(entry.layerIndex) orelse continue;
            entry.renderer.rebuildAll(layer);
        }
    }

    /// Full rebuild: tears down all layer renderers and rebuilds them from the
    /// current map state. Handles added layers, removed layers, a changed
    /// tileset image, and changes to z or parallax properties. On error the
    /// existing renderers are left intact.
    pub fn reload(self: *Self) !void {
        const map = &self.map.val;

        const new_entries = try buildEntries(self.alloc, self.resources, self.shader, map);
        errdefer {
            for (new_entries) |*e| e.renderer.deinit();
            self.alloc.free(new_entries);
        }

        for (new_entries) |*entry| {
            const layer = map.layerByIndex(entry.layerIndex) orelse continue;
            entry.renderer.rebuildAll(layer);
        }

        for (self.entries) |*e| e.renderer.deinit();
        self.alloc.free(self.entries);
        self.entries = new_entries;
    }

    /// Render all layers in ascending z order.
    pub fn render(self: *Self, camera: *const Camera2D, viewport: *const Viewport) void {
        _ = self.sync();
        for (self.entries) |*entry| {
            self.renderEntry(entry, camera, viewport);
        }
    }

    /// Render a single layer by its original map index.
    pub fn renderLayer(
        self: *Self,
        layerIndex: usize,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        _ = self.sync();
        for (self.entries) |*entry| {
            if (entry.layerIndex == layerIndex) {
                self.renderEntry(entry, camera, viewport);
                return;
            }
        }
    }

    /// Render a single layer by its name in Tiled. A name that matches no
    /// layer draws nothing.
    pub fn renderLayerNamed(
        self: *Self,
        name: []const u8,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        _ = self.sync();
        const map = &self.map.val;
        for (self.entries) |*entry| {
            const layer = map.layerByIndex(entry.layerIndex) orelse continue;
            const layerName = layer.name orelse continue;
            if (std.mem.eql(u8, layerName, name)) {
                self.renderEntry(entry, camera, viewport);
                return;
            }
        }
    }

    /// Render all layers whose z is strictly less than `zThreshold`.
    pub fn renderLayersBelow(
        self: *Self,
        zThreshold: f32,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        _ = self.sync();
        for (self.entries) |*entry| {
            if (entry.z >= zThreshold) break; // entries are sorted; can stop early
            self.renderEntry(entry, camera, viewport);
        }
    }

    /// Render all layers whose z is greater than or equal to `zThreshold`.
    pub fn renderLayersAbove(
        self: *Self,
        zThreshold: f32,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        _ = self.sync();
        for (self.entries) |*entry| {
            if (entry.z >= zThreshold) {
                self.renderEntry(entry, camera, viewport);
            }
        }
    }

    // -------------------------------------------------------------------------

    /// Builds one layer renderer per layer in `map`, sorted into draw order.
    /// Each layer draws from its own tileset's image, so a map with more than
    /// one tileset renders correctly.
    fn buildEntries(
        alloc: std.mem.Allocator,
        res: *ResourceManager,
        shader: *ShaderHandle,
        map: *const TileMap,
    ) ![]LayerEntry {
        const entries = try alloc.alloc(LayerEntry, map.layers.items.len);
        errdefer alloc.free(entries);

        var inited: usize = 0;
        errdefer for (entries[0..inited]) |*e| e.renderer.deinit();

        for (map.layers.items, 0..) |*layer, i| {
            // A layer with no tileset has no tiles to draw; it gets a renderer
            // with no texture, which renders nothing.
            const texture = if (layer.tileset) |tileset|
                try res.tilesetTexture(map, tileset)
            else
                null;

            entries[i] = .{
                .renderer = try ChunkedTiledLayerRenderer.init(alloc, shader, texture, layer),
                .parallaxX = layer.floatPropWithDefault("parallax_x", 1.0),
                .parallaxY = layer.floatPropWithDefault("parallax_y", 1.0),
                .layerIndex = i,
                .z = layer.floatPropWithDefault("z", 0.0),
            };
            inited += 1;
        }

        std.sort.block(LayerEntry, entries, {}, entryLessThan);
        return entries;
    }

    fn renderEntry(
        self: *Self,
        entry: *LayerEntry,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        const layer = self.map.val.layerByIndex(entry.layerIndex) orelse return;
        const view = camera.viewRect(viewport);
        const mvp = camera.matrixAt(viewport, parallaxCenter(view, entry.parallaxX, entry.parallaxY));
        const vp_rect = layerViewport(view, entry.parallaxX, entry.parallaxY);
        entry.renderer.render(layer, mvp, vp_rect);
    }

    /// The camera center scaled by (px, py). Centering a layer's matrix here
    /// gives a parallax effect: a layer with px=0.5 scrolls at half the
    /// camera speed.
    fn parallaxCenter(view: RectF, px: f32, py: f32) Vec2F {
        return .{ .x = (view.l + view.r) * 0.5 * px, .y = (view.t + view.b) * 0.5 * py };
    }

    /// Compute the world-space culling rect for a parallax layer. The visible
    /// half-extents are the same as the camera's, but the center is scaled by
    /// the parallax factors.
    fn layerViewport(view: RectF, px: f32, py: f32) RectF {
        const cam_x = (view.l + view.r) * 0.5;
        const cam_y = (view.t + view.b) * 0.5;
        const half_w = (view.r - view.l) * 0.5;
        const half_h = (view.b - view.t) * 0.5;
        return .{
            .l = cam_x * px - half_w,
            .t = cam_y * py - half_h,
            .r = cam_x * px + half_w,
            .b = cam_y * py + half_h,
        };
    }
};
