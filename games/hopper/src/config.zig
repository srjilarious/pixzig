//! Gameplay numbers, read from assets/tuning.json at startup. The Python
//! version reads the same file, so tweaking it changes both.

const std = @import("std");
const pixzig = @import("pixzig");

/// Distances are in pixels (a tile is 16), speeds in pixels per second,
/// accelerations in pixels per second squared, times in milliseconds. A
/// field missing from tuning.json keeps the default here.
pub const Tuning = struct {
    /// Top running speed, and how fast the player gets there on the
    /// ground and in the air.
    run_speed: f32 = 95,
    ground_accel: f32 = 900,
    air_accel: f32 = 600,
    /// How fast the player slows to a stop on the ground with no direction
    /// held. In the air they keep their speed.
    ground_friction: f32 = 1100,

    gravity: f32 = 1000,
    max_fall_speed: f32 = 320,
    /// Upward speed at the start of a jump. The jump's height is
    /// jump_speed^2 / (2 * gravity).
    jump_speed: f32 = 380,
    /// Letting go of jump while still rising multiplies the upward speed by
    /// this, so a tap is a short hop and a hold a full jump.
    jump_release_cut: f32 = 0.45,
    /// A jump still works this long after running off a ledge...
    coyote_ms: f64 = 90,
    /// ...and a jump pressed this long before landing happens on landing.
    jump_buffer_ms: f64 = 110,

    walker_speed: f32 = 28,
    /// Whether walkers turn around at the edge of a drop rather than
    /// walking off it.
    walkers_turn_at_ledges: bool = true,
    /// How high the player bounces off a walker they land on (more with
    /// jump held).
    stomp_bounce: f32 = 260,
    /// How long a squashed walker stays on screen.
    squash_ms: f64 = 450,

    lives: u8 = 3,
    /// How long the game freezes after the player dies, before the level
    /// restarts.
    death_pause_ms: f64 = 900,

    /// How far the player can move from the middle of the screen before
    /// the camera follows, and how quickly it catches up (see
    /// Camera2D.FollowOptions).
    camera_deadzone_x: f32 = 12,
    camera_smoothing: f32 = 9,
};

/// Reads the manifest asset `id` (a JSON file) into a Tuning. Unknown
/// fields, like "_comment", are ignored.
pub fn load(alloc: std.mem.Allocator, manifest: anytype, id: []const u8) !Tuning {
    const path = try manifest.resolvePath(alloc, id);
    defer alloc.free(path);
    const bytes = try pixzig.asset_io.readFile(alloc, path);
    defer alloc.free(bytes);

    const parsed = std.json.parseFromSlice(Tuning, alloc, bytes, .{ .ignore_unknown_fields = true }) catch |err| {
        std.log.err("Couldn't read {s}: {s}", .{ path, @errorName(err) });
        return err;
    };
    defer parsed.deinit();
    return parsed.value;
}
