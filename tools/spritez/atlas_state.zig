const std = @import("std");
const pixzig = @import("pixzig");
const core = @import("./core.zig");

pub const AtlasState = struct {
    pub fn update(self: *AtlasState, eng: *core.Engine, delta: f64) bool {
        _ = delta;
        _ = eng;
        _ = self;
        return true;
    }

    pub fn render(self: *AtlasState, eng: *core.Engine) void {
        _ = self;
        eng.renderer.clear(0, 1, 0, 1);
    }

    pub fn activate(self: *AtlasState) void {
        _ = self;
        std.debug.print("Atlas state activated!\n", .{});
    }

    pub fn deactivate(self: *AtlasState) void {
        _ = self;
        std.debug.print("Atlas state deactivated!\n", .{});
    }
};
