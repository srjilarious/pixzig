const std = @import("std");
const pixzig = @import("pixzig");
const core = @import("./core.zig");

pub const AnimationState = struct {
    pub fn update(self: *AnimationState, eng: *core.Engine, delta: f64) bool {
        _ = delta;
        _ = eng;
        _ = self;
        return true;
    }

    pub fn render(self: *AnimationState, eng: *core.Engine) void {
        _ = self;
        eng.renderer.clear(1, 0, 0, 1);
    }

    pub fn activate(self: *AnimationState) void {
        _ = self;
        std.debug.print("Animation state activated!\n", .{});
    }

    pub fn deactivate(self: *AnimationState) void {
        _ = self;
        std.debug.print("Animation state deactivated!\n", .{});
    }
};
