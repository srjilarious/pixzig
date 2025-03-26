// zig fmt: off
const std = @import("std");
const pixzig = @import("pixzig");
const flecs = pixzig.flecs;

const RectF = pixzig.common.RectF;

const entities = @import("../entities.zig");
const Player = entities.Player;
const Mover = entities.Mover;
const Sprite = pixzig.sprites.Sprite;
const TileLayer = pixzig.tile.TileLayer;

pub const Gravity = struct {
    world: *flecs.world_t,
    query: *flecs.query_t,

    pub fn init(world: *flecs.world_t) !@This() {
        return .{
            .world = world,
            .query = try flecs.query_init(world, &.{
                    .terms = [_]flecs.term_t{
                        .{ .id = flecs.id(Sprite) },
                        .{ .id = flecs.id(Mover) },
                    } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX - 2),
            }),
        };
    }

    pub fn deinit(self: *@This()) void {
        flecs.query_fini(self.query);
    }

    pub fn update(self: *@This(), map: *TileLayer) void {
        var it = flecs.query_iter(self.world, self.query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 0).?;
            const vel = flecs.field(&it, Mover, 1).?;

            for (0..it.count()) |idx| {
                var v: *Mover = &vel[idx];
                var sp: *Sprite = &spr[idx];
                v.speed.y += 0.08;
                if(v.speed.y > 4.0) {
                    v.speed.y = 4.0;
                }

                if(v.speed.y > 0) {
                    if(pixzig.tile.Mover.moveDown(&sp.dest, v.speed.y, map, pixzig.tile.BlocksAll)) {
                        v.speed.y = 0;
                        v.inAir = false;
                    }
                    else {
                        v.inAir = true;
                    }
                }
                else {
                    if(pixzig.tile.Mover.moveUp(&sp.dest, -v.speed.y, map, pixzig.tile.BlocksAll)) {
                        v.speed.y = 0;
                    }
                }

                sp.dest.ensureSize(@as(i32, @intFromFloat(sp.size.x)), @as(i32, @intFromFloat(sp.size.y)));
            }
        }
    }
};
