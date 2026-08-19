const std = @import("std");
const zmath = @import("zmath");
const common = @import("./common.zig");

const Vec3F = common.Vec3F;

/// A standalone first-person perspective camera. `pos` is the eye position
/// in world space; `yaw` is the heading in radians, measured so that
/// yaw == 0 looks down +z and increasing yaw rotates toward +x (matching
/// zmath's left-handed convention used by `perspectiveFovLhGl`).
pub const Camera3D = struct {
    pos: Vec3F = .{ .x = 0, .y = 0, .z = 0 },
    yaw: f32 = 0,
    fovYRadians: f32 = std.math.degreesToRadians(70.0),
    near: f32 = 1.0,
    far: f32 = 1000.0,

    /// Returns the normalized forward direction for the current yaw.
    pub fn forward(self: *const Camera3D) Vec3F {
        return .{ .x = @sin(self.yaw), .y = 0, .z = @cos(self.yaw) };
    }

    /// Returns a combined view*projection matrix mapping world coordinates
    /// to clip space, for the given viewport aspect ratio (width / height).
    pub fn viewProjMatrix(self: *const Camera3D, aspect: f32) zmath.Mat {
        const eye = zmath.Vec{ self.pos.x, self.pos.y, self.pos.z, 1.0 };
        const fwd = self.forward();
        const focus = zmath.Vec{ self.pos.x + fwd.x, self.pos.y + fwd.y, self.pos.z + fwd.z, 1.0 };
        const up = zmath.Vec{ 0.0, 1.0, 0.0, 0.0 };

        const view = zmath.lookAtLh(eye, focus, up);
        const proj = zmath.perspectiveFovLhGl(self.fovYRadians, aspect, self.near, self.far);
        return zmath.mul(view, proj);
    }
};
