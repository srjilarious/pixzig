//! A box that falls, moves and stops against the level's solid tiles. The
//! player and the walkers are both one of these.

const pixzig = @import("pixzig");
const tile = pixzig.tile;
const RectF = pixzig.RectF;
const Vec2F = pixzig.Vec2F;

const Tuning = @import("config.zig").Tuning;

pub const Body = struct {
    /// Its hitbox, in world pixels.
    rect: RectF,
    /// Where `rect`'s top-left was before the last `step`, for drawing it
    /// between ticks (see `drawPos`).
    prev: Vec2F,
    /// Pixels per second; +y is down.
    vel: Vec2F = .{ .x = 0, .y = 0 },
    /// Whether it ended the last step standing on a solid tile.
    on_ground: bool = false,

    pub fn init(x: f32, y: f32, w: f32, h: f32) Body {
        return .{ .rect = RectF.fromPosSize(x, y, w, h), .prev = .{ .x = x, .y = y } };
    }

    /// Where it collided during a `step`.
    pub const Hits = struct { wall: bool = false, floor: bool = false, ceiling: bool = false };

    /// Pulls it down by gravity, then moves it by its velocity over `dt`
    /// seconds, one axis at a time so it slides along walls and floors.
    /// Hitting something zeroes the velocity along that axis.
    pub fn step(self: *Body, dt: f32, layer: *tile.TileLayer, tun: *const Tuning) Hits {
        self.prev = .{ .x = self.rect.l, .y = self.rect.t };
        self.vel.y = @min(self.vel.y + tun.gravity * dt, tun.max_fall_speed);

        var hits: Hits = .{};
        const dx = self.vel.x * dt;
        if (dx > 0) {
            hits.wall = tile.Mover.moveRight(&self.rect, dx, layer, tile.BlocksAll);
        } else if (dx < 0) {
            hits.wall = tile.Mover.moveLeft(&self.rect, -dx, layer, tile.BlocksAll);
        }
        if (hits.wall) self.vel.x = 0;

        const dy = self.vel.y * dt;
        if (dy > 0) {
            hits.floor = tile.Mover.moveDown(&self.rect, dy, layer, tile.BlocksAll);
        } else if (dy < 0) {
            hits.ceiling = tile.Mover.moveUp(&self.rect, -dy, layer, tile.BlocksAll);
        }
        if (hits.floor or hits.ceiling) self.vel.y = 0;
        self.on_ground = hits.floor;
        return hits;
    }

    /// Moves it straight to (x, y) (its top-left), with nothing to
    /// interpolate from.
    pub fn teleport(self: *Body, x: f32, y: f32) void {
        const w = self.rect.width();
        const h = self.rect.height();
        self.rect = RectF.fromPosSize(x, y, w, h);
        self.prev = .{ .x = x, .y = y };
    }

    /// Its top-left `alpha` of the way from the last tick's position to
    /// this one's, so movement stays smooth however the frame rate and the
    /// fixed tick line up.
    pub fn drawPos(self: *const Body, alpha: f32) Vec2F {
        return self.prev.lerp(.{ .x = self.rect.l, .y = self.rect.t }, alpha);
    }
};
