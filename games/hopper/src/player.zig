//! The frog: running, jumping, and which frame of it to draw.

const pixzig = @import("pixzig");
const RectF = pixzig.RectF;

const Engine = @import("main.zig").Engine;
const Tuning = @import("config.zig").Tuning;
const Body = @import("body.zig").Body;
const Level = @import("level.zig").Level;
const sheet = @import("sheet.zig");

/// Hitbox size. The 16x16 sprite is drawn centred over it, bottoms lined up.
pub const Width = 12;
pub const Height = 13;

pub const Player = struct {
    body: Body,
    facing_left: bool = false,
    /// Time left to jump after leaving the ground (see Tuning.coyote_ms).
    coyote_ms: f64 = 0,
    /// Time left on a jump pressed in the air (see Tuning.jump_buffer_ms).
    jump_buffer_ms: f64 = 0,
    /// Distance run, for picking the run frame.
    run_px: f32 = 0,

    pub fn init(x: f32, y: f32) Player {
        return .{ .body = Body.init(x, y, Width, Height) };
    }

    /// One tick of `delta` ms: steer from the controls, then move.
    pub fn update(self: *Player, eng: *Engine, tun: *const Tuning, level: *const Level, delta: f64) void {
        const dt: f32 = @floatCast(delta / 1000.0);
        const actions = eng.actions;
        const body = &self.body;

        // Run: speed up toward the held direction, or slow to a stop.
        var dir: f32 = 0;
        if (actions.down(.left)) dir -= 1;
        if (actions.down(.right)) dir += 1;
        if (dir != 0) {
            const accel = if (body.on_ground) tun.ground_accel else tun.air_accel;
            body.vel.x = approach(body.vel.x, dir * tun.run_speed, accel * dt);
            self.facing_left = dir < 0;
        } else if (body.on_ground) {
            body.vel.x = approach(body.vel.x, 0, tun.ground_friction * dt);
        }

        // Jump, with a little forgiveness either side of being on the
        // ground (coyote time and the jump buffer).
        self.coyote_ms = if (body.on_ground) tun.coyote_ms else self.coyote_ms - delta;
        self.jump_buffer_ms = if (actions.pressed(.jump)) tun.jump_buffer_ms else self.jump_buffer_ms - delta;
        if (self.jump_buffer_ms > 0 and self.coyote_ms > 0) {
            body.vel.y = -tun.jump_speed;
            self.jump_buffer_ms = 0;
            self.coyote_ms = 0;
        }
        // Letting go early cuts the jump short.
        if (actions.released(.jump) and body.vel.y < 0) body.vel.y *= tun.jump_release_cut;

        _ = body.step(dt, level.mainLayer(), tun);

        // Keep inside the level's left and right edges.
        if (body.rect.l < 0) body.teleport(0, body.rect.t);
        if (body.rect.r > level.width()) body.teleport(level.width() - Width, body.rect.t);

        self.run_px += @abs(body.vel.x) * dt;
    }

    /// Whether it came down onto `rect` from above this tick: falling, with
    /// its feet above `rect`'s top a tick ago. That's a stomp; touching
    /// something any other way is a hit.
    pub fn landedOn(self: *const Player, rect: *const RectF) bool {
        const was_above = self.body.prev.y + Height <= rect.t + 2;
        return self.body.vel.y > 0 and was_above;
    }

    /// Bounces up off something it stomped: a full jump with jump held, a
    /// smaller hop without.
    pub fn bounce(self: *Player, jump_held: bool, tun: *const Tuning) void {
        self.body.vel.y = -(if (jump_held) tun.jump_speed else tun.stomp_bounce);
    }

    /// The sheet cell for its current pose.
    pub fn cell(self: *const Player) usize {
        if (!self.body.on_ground) return sheet.FrogJump;
        if (@abs(self.body.vel.x) > 5) {
            return if (@mod(self.run_px, 16) < 8) sheet.FrogRun1 else sheet.FrogRun2;
        }
        return sheet.FrogIdle;
    }
};

/// `value` moved toward `target` by at most `step`.
fn approach(value: f32, target: f32, step: f32) f32 {
    if (value < target) return @min(value + step, target);
    return @max(value - step, target);
}
