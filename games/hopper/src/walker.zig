//! The beetles: they walk back and forth until stomped.

const Tuning = @import("config.zig").Tuning;
const Body = @import("body.zig").Body;
const Level = @import("level.zig").Level;
const sheet = @import("sheet.zig");

/// Hitbox size. The 16x16 sprite is drawn centred over it, bottoms lined up.
pub const Width = 14;
pub const Height = 11;

pub const Walker = struct {
    body: Body,
    /// -1 walking left, 1 walking right.
    dir: f32 = -1,
    /// Time left on screen once squashed; null while alive.
    squashed_ms: ?f64 = null,

    pub fn init(x: f32, y: f32) Walker {
        return .{ .body = Body.init(x, y, Width, Height) };
    }

    /// One tick of `delta` ms: walk, turning at walls (and, by default, at
    /// drops). A squashed walker only counts down until it's gone.
    pub fn update(self: *Walker, tun: *const Tuning, level: *const Level, delta: f64) void {
        if (self.squashed_ms) |*ms| {
            ms.* -= delta;
            return;
        }
        const dt: f32 = @floatCast(delta / 1000.0);
        self.body.vel.x = self.dir * tun.walker_speed;
        const hits = self.body.step(dt, level.mainLayer(), tun);
        if (hits.wall) self.dir = -self.dir;

        if (tun.walkers_turn_at_ledges and self.body.on_ground) {
            const r = self.body.rect;
            const ahead_x = if (self.dir > 0) r.r + 1 else r.l - 1;
            if (!level.solidAt(ahead_x, r.b + 1)) self.dir = -self.dir;
        }
    }

    pub fn squash(self: *Walker, tun: *const Tuning) void {
        self.squashed_ms = tun.squash_ms;
    }

    pub fn isSquashed(self: *const Walker) bool {
        return self.squashed_ms != null;
    }

    /// Squashed, and finished showing it: time to remove it.
    pub fn isGone(self: *const Walker) bool {
        const ms = self.squashed_ms orelse return false;
        return ms <= 0;
    }

    /// The sheet cell to draw, `elapsed_ms` into the level.
    pub fn cell(self: *const Walker, elapsed_ms: f64) usize {
        if (self.isSquashed()) return sheet.BeetleSquashed;
        return if (@mod(elapsed_ms, 300) < 150) sheet.BeetleWalk1 else sheet.BeetleWalk2;
    }
};
