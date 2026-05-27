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
///
/// Set `bounds` to a world-space rectangle to prevent the camera from
/// showing area outside it. When the viewport is larger than the bounds
/// in either axis, that axis is centered on the bounds instead.
pub const Camera2D = struct {
    pos: Vec2F = .{ .x = 0, .y = 0 },
    zoom: f32 = 1.0,
    rotation: f32 = 0.0,
    logical_size: Vec2I,
    bounds: ?RectF = null,

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
        const p = self.clampedPos();

        const t_neg = zmath.translation(-p.x, -p.y, 0.0);
        const t_scale = zmath.scaling(z, z, 1.0);
        const t_rot = zmath.rotationZ(self.rotation);
        const t_center = zmath.translation(cx, cy, 0.0);
        const cam = zmath.mul(t_neg, zmath.mul(t_scale, zmath.mul(t_rot, t_center)));
        return zmath.mul(cam, viewport.projection());
    }

    /// World-space rectangle currently visible through this camera.
    /// Reflects the clamped position when bounds are set.
    pub fn viewRect(self: *const Camera2D) RectF {
        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        const half_w = lw / (2.0 * self.zoom);
        const half_h = lh / (2.0 * self.zoom);
        const p = self.clampedPos();
        return .{
            .l = p.x - half_w,
            .t = p.y - half_h,
            .r = p.x + half_w,
            .b = p.y + half_h,
        };
    }

    /// Converts a world coordinate to logical viewport space.
    pub fn worldToLogical(self: *const Camera2D, world: Vec2F) Vec2F {
        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        const p = self.clampedPos();
        return .{
            .x = (world.x - p.x) * self.zoom + lw / 2.0,
            .y = (world.y - p.y) * self.zoom + lh / 2.0,
        };
    }

    /// Converts a logical viewport coordinate to world space.
    pub fn logicalToWorld(self: *const Camera2D, logical: Vec2F) Vec2F {
        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        const p = self.clampedPos();
        return .{
            .x = (logical.x - lw / 2.0) / self.zoom + p.x,
            .y = (logical.y - lh / 2.0) / self.zoom + p.y,
        };
    }

    /// Returns pos clamped so the viewport stays within bounds.
    /// When the viewport is wider/taller than bounds in an axis, centers on
    /// bounds for that axis rather than inverting the clamp.
    fn clampedPos(self: *const Camera2D) Vec2F {
        var p = self.pos;
        const b = self.bounds orelse return p;

        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        const half_w = lw / (2.0 * self.zoom);
        const half_h = lh / (2.0 * self.zoom);
        const bw = b.width();
        const bh = b.height();

        if (bw <= lw / self.zoom) {
            p.x = b.l + bw / 2.0;
        } else {
            p.x = std.math.clamp(p.x, b.l + half_w, b.r - half_w);
        }

        if (bh <= lh / self.zoom) {
            p.y = b.t + bh / 2.0;
        } else {
            p.y = std.math.clamp(p.y, b.t + half_h, b.b - half_h);
        }

        return p;
    }
};
