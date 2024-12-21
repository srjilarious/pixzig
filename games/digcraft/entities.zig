// zig fmt: off
const std = @import("std");
const flecs = @import("zflecs");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const Vec2F = pixzig.common.Vec2F;

const Texture = pixzig.textures.Texture;
const Sprite = pixzig.sprites.Sprite;

const C = @import("./constants.zig");

pub const Entities = enum {
    Player,
    Meeper,
    Sweeper,
};

pub const Player = struct {
    hp: u32,
};

pub const Mover = struct { 
    bounds: RectF,
    speed: Vec2F,
    inAir: bool,
};

pub fn setupEntities(world: *flecs.world_t) void {
    flecs.COMPONENT(world, Player);
    flecs.COMPONENT(world, Mover);
    flecs.COMPONENT(world, Sprite);
}

pub fn spawn(world: *flecs.world_t, which: Entities, tex: *Texture, sprNum: i32) void {
    _ = sprNum;
    const ent = flecs.new_id(world);
    switch(which) {
        .Player => {
            std.debug.print("Spawning player!\n", .{});
            const move: Mover = .{
                .bounds = RectF.fromPosSize(16, 16, C.TileWidth, C.TileHeight),
                .speed = .{ .x=0, .y= 0},
                .inAir = false,
            };
            _ = flecs.set(world, ent, Mover, move);
       
            // const srcX: i32 = @intCast(C.TileWidth*@rem(sprNum, C.NumTilesHorz));
            // const srcY:i32 = @intCast(C.TileHeight*@divTrunc(sprNum, C.NumTilesVert));
            var spr = Sprite.create(
                tex, 
                .{ .x = 16, .y = 16});
            spr.setPos(16, 16);
            _ = flecs.set(world, ent, Sprite, spr);
        },
        else => {
            std.debug.print("Entity not setup to spawn yet!", .{});
        }
    }
}
