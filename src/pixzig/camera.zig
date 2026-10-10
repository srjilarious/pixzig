const std = @import("std");
const zmath = @import("zmath");
const common = @import("./common.zig");
const windowing = @import("./window.zig");

const Vec2F = common.Vec2F;
const RectF = common.RectF;
const Viewport = windowing.Viewport;

/// A 2D orthographic camera. `pos` is the world coordinate shown at the
/// center of the logical viewport, and `rotation` (radians) turns the view
/// around that center.
///
/// The camera doesn't store a screen size: every method takes the viewport
/// it renders through, so it follows the logical size when that tracks the
/// window (`EngineInitOptions.logicalSize = null`).
///
/// Set `bounds` to a world-space rectangle to prevent the camera from
/// showing area outside it. When the viewport is larger than the bounds
/// in either axis, that axis is centered on the bounds instead.
pub const Camera2D = struct {
    pos: Vec2F = .{ .x = 0, .y = 0 },
    zoom: f32 = 1.0,
    rotation: f32 = 0.0,
    bounds: ?RectF = null,

    pub fn init() Camera2D {
        return .{};
    }

    /// Returns a matrix mapping world coordinates to NDC via the given viewport.
    /// Transform order: translate world so pos lands at origin, scale by zoom,
    /// rotate, translate to logical center, then apply viewport projection.
    pub fn matrix(self: *const Camera2D, viewport: *const Viewport) zmath.Mat {
        return self.matrixAt(viewport, self.clampedPos(viewport));
    }

    /// Like `matrix`, but centered on `center` instead of the camera's
    /// (bounds-clamped) position. Keeps zoom and rotation; used for
    /// parallax layers that scroll at a fraction of the camera's speed.
    pub fn matrixAt(self: *const Camera2D, viewport: *const Viewport, center: Vec2F) zmath.Mat {
        const half = halfLogical(viewport);
        const z = self.zoom;

        const t_neg = zmath.translation(-center.x, -center.y, 0.0);
        const t_scale = zmath.scaling(z, z, 1.0);
        const t_rot = zmath.rotationZ(self.rotation);
        const t_center = zmath.translation(half.x, half.y, 0.0);
        const cam = zmath.mul(t_neg, zmath.mul(t_scale, zmath.mul(t_rot, t_center)));
        return zmath.mul(cam, viewport.projection());
    }

    /// World-space rectangle currently visible through this camera.
    /// Reflects the clamped position when bounds are set. With a rotated
    /// camera this is the axis-aligned box around the visible area, so it
    /// is still safe to cull against.
    pub fn viewRect(self: *const Camera2D, viewport: *const Viewport) RectF {
        const half = self.halfExtents(viewport);
        const p = self.clampedPos(viewport);
        return .{
            .l = p.x - half.x,
            .t = p.y - half.y,
            .r = p.x + half.x,
            .b = p.y + half.y,
        };
    }

    /// Converts a world coordinate to logical viewport space.
    pub fn worldToLogical(self: *const Camera2D, viewport: *const Viewport, world: Vec2F) Vec2F {
        // `Vec2F.rotate` turns the same way `zmath.rotationZ` does in `matrix`.
        return world.sub(self.clampedPos(viewport))
            .scale(self.zoom)
            .rotate(self.rotation)
            .add(halfLogical(viewport));
    }

    /// Converts a logical viewport coordinate to world space.
    pub fn logicalToWorld(self: *const Camera2D, viewport: *const Viewport, logical: Vec2F) Vec2F {
        return logical.sub(halfLogical(viewport))
            .rotate(-self.rotation)
            .scale(1.0 / self.zoom)
            .add(self.clampedPos(viewport));
    }

    /// Half the logical viewport size, i.e. its center in logical space.
    fn halfLogical(viewport: *const Viewport) Vec2F {
        return .{
            .x = @as(f32, @floatFromInt(viewport.logicalSize.x)) / 2.0,
            .y = @as(f32, @floatFromInt(viewport.logicalSize.y)) / 2.0,
        };
    }

    /// Half the world-space size of the axis-aligned box around the visible
    /// area, after zoom and rotation.
    fn halfExtents(self: *const Camera2D, viewport: *const Viewport) Vec2F {
        const half = halfLogical(viewport);
        const hw = half.x / self.zoom;
        const hh = half.y / self.zoom;
        const c = @abs(@cos(self.rotation));
        const s = @abs(@sin(self.rotation));
        return .{
            .x = hw * c + hh * s,
            .y = hw * s + hh * c,
        };
    }

    /// Returns pos clamped so the visible area stays within bounds.
    /// When the visible area is wider/taller than bounds in an axis, centers
    /// on bounds for that axis rather than inverting the clamp.
    fn clampedPos(self: *const Camera2D, viewport: *const Viewport) Vec2F {
        var p = self.pos;
        const b = self.bounds orelse return p;

        const half = self.halfExtents(viewport);
        const bw = b.width();
        const bh = b.height();

        if (bw <= half.x * 2.0) {
            p.x = b.l + bw / 2.0;
        } else {
            p.x = std.math.clamp(p.x, b.l + half.x, b.r - half.x);
        }

        if (bh <= half.y * 2.0) {
            p.y = b.t + bh / 2.0;
        } else {
            p.y = std.math.clamp(p.y, b.t + half.y, b.b - half.y);
        }

        return p;
    }
};
