const std = @import("std");
const zmath = @import("zmath");
const common = @import("./common.zig");
const windowing = @import("./window.zig");

const Vec2F = common.Vec2F;
const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Viewport = windowing.Viewport;

/// A 2D orthographic camera. `pos` is the world coordinate shown at the
/// center of the logical viewport.
pub const Camera2D = struct {
    pos: Vec2F = .{ .x = 0, .y = 0 },
    zoom: f32 = 1.0,
    rotation: f32 = 0.0,
    logical_size: Vec2I,

    pub fn init(logical_size: Vec2I) Camera2D {
        return .{ .logical_size = logical_size };
    }

    /// Returns a matrix mapping world coordinates to NDC via the given viewport.
    /// Transform order: translate world so pos lands at origin, scale by zoom,
    /// rotate, translate to logical center, then apply viewport projection.
    pub fn matrix(self: *const Camera2D, viewport: *const Viewport) zmath.Mat {
        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        const cx = lw / 2.0;
        const cy = lh / 2.0;
        const z = self.zoom;

        const t_neg = zmath.translation(-self.pos.x, -self.pos.y, 0.0);
        const t_scale = zmath.scaling(z, z, 1.0);
        const t_rot = zmath.rotationZ(self.rotation);
        const t_center = zmath.translation(cx, cy, 0.0);
        const cam = zmath.mul(t_neg, zmath.mul(t_scale, zmath.mul(t_rot, t_center)));
        return zmath.mul(cam, viewport.projection());
    }

    /// World-space rectangle currently visible through this camera.
    pub fn viewRect(self: *const Camera2D) RectF {
        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        const half_w = lw / (2.0 * self.zoom);
        const half_h = lh / (2.0 * self.zoom);
        return .{
            .l = self.pos.x - half_w,
            .t = self.pos.y - half_h,
            .r = self.pos.x + half_w,
            .b = self.pos.y + half_h,
        };
    }

    /// Converts a world coordinate to logical viewport space.
    pub fn worldToLogical(self: *const Camera2D, world: Vec2F) Vec2F {
        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        return .{
            .x = (world.x - self.pos.x) * self.zoom + lw / 2.0,
            .y = (world.y - self.pos.y) * self.zoom + lh / 2.0,
        };
    }

    /// Converts a logical viewport coordinate to world space.
    pub fn logicalToWorld(self: *const Camera2D, logical: Vec2F) Vec2F {
        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        return .{
            .x = (logical.x - lw / 2.0) / self.zoom + self.pos.x,
            .y = (logical.y - lh / 2.0) / self.zoom + self.pos.y,
        };
    }
};
