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
};

/// Renders all tile layers in a TileMap, one ChunkedTiledLayerRenderer per
/// layer. Parallax per layer is read from the layer's `parallax_x` and
/// `parallax_y` float properties (defaulting to 1.0 if absent).
pub const ChunkedTiledRenderer = struct {
    alloc: std.mem.Allocator,
    entries: []LayerEntry,

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
            };
            inited += 1;
        }

        return .{ .alloc = alloc, .entries = entries };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries) |*e| e.renderer.deinit();
        self.alloc.free(self.entries);
    }

    /// Mark all chunks in all layers as dirty, forcing a full GPU rebuild on
    /// the next render call. Call this after a hot-reload of the map data.
    pub fn markAllDirty(self: *Self) void {
        for (self.entries) |*e| e.renderer.markAllDirty();
    }

    /// Render all layers in order. Each layer's MVP and culling viewport are
    /// derived from `camera` and `viewport` adjusted by the layer's parallax
    /// factors.
    pub fn render(
        self: *Self,
        map: *const TileMap,
        camera: *const Camera2D,
        viewport: *const Viewport,
    ) void {
        for (self.entries) |*entry| {
            const layer = map.layerByIndex(entry.layer_index) orelse continue;
            const mvp = layerMvp(camera, viewport, entry.parallax_x, entry.parallax_y);
            const vp_rect = layerViewport(camera, entry.parallax_x, entry.parallax_y);
            entry.renderer.render(layer, mvp, vp_rect);
        }
    }

    // -------------------------------------------------------------------------

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
