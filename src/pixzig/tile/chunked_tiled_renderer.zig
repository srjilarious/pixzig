const std = @import("std");
const zmath = @import("zmath");

const common = @import("../common.zig");
const resources = @import("../resources.zig");
const camera_mod = @import("../camera.zig");
const window_mod = @import("../window.zig");
const tilemap = @import("./tilemap.zig");
const ChunkedTiledLayerRenderer = @import("./chunked_tile_renderer.zig").ChunkedTiledLayerRenderer;

const RectF = common.RectF;
const ManagedShader = resources.ManagedShader;
const ManagedTexture = resources.ManagedTexture;
const TileMap = tilemap.TileMap;
const Camera2D = camera_mod.Camera2D;
const Viewport = window_mod.Viewport;

const LayerEntry = struct {
    renderer: ChunkedTiledLayerRenderer,
    parallax_x: f32,
    parallax_y: f32,
    layer_index: usize,
    /// Draw order depth. Layers are rendered lowest-z-first. Set via the
    /// `z` float custom property on the layer in Tiled; defaults to 0.
    z: f32,
};

fn entryLessThan(_: void, a: LayerEntry, b: LayerEntry) bool {
    if (a.z != b.z) return a.z < b.z;
    return a.layer_index < b.layer_index;
}

/// Renders all tile layers in a TileMap, one ChunkedTiledLayerRenderer per
/// layer. Per-layer properties read from Tiled custom properties:
///   `z`           - draw order depth (f32, default 0.0); lower renders first
///   `parallax_x`  - horizontal scroll factor (f32, default 1.0)
///   `parallax_y`  - vertical scroll factor   (f32, default 1.0)
///
/// Entries are sorted by z ascending at init time and remain in that order.
pub const ChunkedTiledRenderer = struct {
    alloc: std.mem.Allocator,
    entries: []LayerEntry,
    /// Retained so reload() can create renderers for newly added layers.
    shader: *ManagedShader,
    texture: *ManagedTexture,

    const Self = @This();

    pub fn init(
        alloc: std.mem.Allocator,
        map: *const TileMap,
        shader: *ManagedShader,
        texture: *ManagedTexture,
    ) !Self {
        const n = map.layers.items.len;
        const entries = try alloc.alloc(LayerEntry, n);
        errdefer alloc.free(entries);

        var inited: usize = 0;
        errdefer for (entries[0..inited]) |*e| e.renderer.deinit();

        for (map.layers.items, 0..) |*layer, i| {
            entries[i] = .{
                .renderer = try ChunkedTiledLayerRenderer.init(alloc, shader, texture, layer),
                .parallax_x = layer.floatPropWithDefault("parallax_x", 1.0),
                .parallax_y = layer.floatPropWithDefault("parallax_y", 1.0),
                .layer_index = i,
                .z = layer.floatPropWithDefault("z", 0.0),
            };
            inited += 1;
        }

        std.sort.block(LayerEntry, entries, {}, entryLessThan);

        return .{ .alloc = alloc, .entries = entries, .shader = shader, .texture = texture };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries) |*e| e.renderer.deinit();
        self.alloc.free(self.entries);
    }

    /// Mark all chunks in all layers as dirty. Chunks rebuild lazily as they
    /// come into view. Use rebuildAll for an immediate forced rebuild.
    pub fn markAllDirty(self: *Self) void {
        for (self.entries) |*e| e.renderer.markAllDirty();
    }

    /// Immediately rebuild every chunk in every layer from the current map
    /// data, regardless of viewport. Only safe when the map's layer count and
    /// structure are unchanged — use reload() after a hot-reload that may have
    /// added, removed, or reordered layers.
    pub fn rebuildAll(self: *Self, map: *const TileMap) void {
        for (self.entries) |*entry| {
            const layer = map.layerByIndex(entry.layer_index) orelse continue;
            entry.renderer.rebuildAll(layer);
        }
    }

    /// Full hot-reload: tears down all layer renderers and rebuilds them from
    /// the current map state. Handles added layers, removed layers, and
    /// changes to z or parallax properties. On error the existing renderers
    /// are left intact.
    pub fn reload(self: *Self, map: *const TileMap) !void {
        const n = map.layers.items.len;
        const new_entries = try self.alloc.alloc(LayerEntry, n);
        errdefer self.alloc.free(new_entries);

        var inited: usize = 0;
        errdefer for (new_entries[0..inited]) |*e| e.renderer.deinit();

        for (map.layers.items, 0..) |*layer, i| {
            new_entries[i] = .{
                .renderer = try ChunkedTiledLayerRenderer.init(self.alloc, self.shader, self.texture, layer),
                .parallax_x = layer.floatPropWithDefault("parallax_x", 1.0),
                .parallax_y = layer.floatPropWithDefault("parallax_y", 1.0),
                .layer_index = i,
                .z = layer.floatPropWithDefault("z", 0.0),
            };
            new_entries[i].renderer.rebuildAll(layer);
            inited += 1;
        }

        for (self.entries) |*e| e.renderer.deinit();
        self.alloc.free(self.entries);
        self.entries = new_entries;

        std.sort.block(LayerEntry, self.entries, {}, entryLessThan);
    }

    /// Render all layers in ascending z order.
    pub fn render(
        self: *Self,
        map: *const TileMap,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        for (self.entries) |*entry| {
            renderEntry(entry, map, camera, viewport);
        }
    }

    /// Render a single layer by its original map index.
    pub fn renderLayer(
        self: *Self,
        layer_index: usize,
        map: *const TileMap,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        for (self.entries) |*entry| {
            if (entry.layer_index == layer_index) {
                renderEntry(entry, map, camera, viewport);
                return;
            }
        }
    }

    /// Render all layers whose z is strictly less than `z_threshold`.
    pub fn renderLayersBelow(
        self: *Self,
        z_threshold: f32,
        map: *const TileMap,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        for (self.entries) |*entry| {
            if (entry.z >= z_threshold) break; // entries are sorted; can stop early
            renderEntry(entry, map, camera, viewport);
        }
    }

    /// Render all layers whose z is greater than or equal to `z_threshold`.
    pub fn renderLayersAbove(
        self: *Self,
        z_threshold: f32,
        map: *const TileMap,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        for (self.entries) |*entry| {
            if (entry.z >= z_threshold) {
                renderEntry(entry, map, camera, viewport);
            }
        }
    }

    // -------------------------------------------------------------------------

    fn renderEntry(entry: *LayerEntry, map: *const TileMap, camera: *const Camera2D, viewport: *const Viewport) void {
        const layer = map.layerByIndex(entry.layer_index) orelse return;
        const mvp = layerMvp(camera, viewport, entry.parallax_x, entry.parallax_y);
        const vp_rect = layerViewport(camera, entry.parallax_x, entry.parallax_y);
        entry.renderer.render(layer, mvp, vp_rect);
    }

    /// Build a camera MVP with the translation scaled by (px, py). This gives
    /// a parallax effect: a layer with px=0.5 scrolls at half the camera speed.
    fn layerMvp(camera: *const Camera2D, vp: *const Viewport, px: f32, py: f32) zmath.Mat {
        const view = camera.viewRect();
        const cam_x = (view.l + view.r) * 0.5;
        const cam_y = (view.t + view.b) * 0.5;
        const lw: f32 = @floatFromInt(camera.logical_size.x);
        const lh: f32 = @floatFromInt(camera.logical_size.y);
        const z = camera.zoom;

        const t_neg = zmath.translation(-cam_x * px, -cam_y * py, 0.0);
        const t_scale = zmath.scaling(z, z, 1.0);
        const t_rot = zmath.rotationZ(camera.rotation);
        const t_center = zmath.translation(lw * 0.5, lh * 0.5, 0.0);
        const cam_mat = zmath.mul(t_neg, zmath.mul(t_scale, zmath.mul(t_rot, t_center)));
        return zmath.mul(cam_mat, vp.projection());
    }

    /// Compute the world-space culling rect for a parallax layer. The visible
    /// half-extents are the same as the camera's, but the center is scaled by
    /// the parallax factors.
    fn layerViewport(camera: *const Camera2D, px: f32, py: f32) RectF {
        const view = camera.viewRect();
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
