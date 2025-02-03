// zig fmt: off
const std = @import("std");
const math = @import("zmath");
const flecs = @import("zflecs");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const Vec2F = pixzig.common.Vec2F;
const Vec2I = pixzig.common.Vec2I;
const Color = pixzig.common.Color;

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

pub const HumanController = struct {
    dummy: bool = false,
    cursorTile: Vec2I,
    cursorLoc: RectF,
    cursorColor: Color
};

pub const Camera = struct {
    cameraMat: math.Mat,
    cameraPos: Vec2F,
    winOffset: Vec2F,
    tracked: ?flecs.entity_t = null,
};

pub fn setupEntities(world: *flecs.world_t) void {
    std.log.info("Setting up entities!\n", .{});
    flecs.COMPONENT(world, Player);
    flecs.COMPONENT(world, Mover);
    flecs.COMPONENT(world, Sprite);
    flecs.COMPONENT(world, HumanController);
    flecs.COMPONENT(world, Camera);
}

pub fn spawn(world: *flecs.world_t, which: Entities, tex: *Texture, sprNum: i32) flecs.entity_t {
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

            const human: HumanController = .{ 
                .cursorTile = .{ .x = 0, .y = 0},
                .cursorLoc = RectF.fromPosSize(0, 0, 32, 32),
                .cursorColor = Color.from(0, 0, 0, 0),
            };
            _ = flecs.set(world, ent, HumanController, human);
        },
        else => {
            std.debug.print("Entity not setup to spawn yet!", .{});
        }
    }

    return ent;
}

pub fn spawnCamera(world: *flecs.world_t, tracked: ?flecs.entity_t, offset: Vec2F) flecs.entity_t {
    const ent = flecs.new_id(world);
    const cam = Camera{
        .cameraMat = math.identity(),
        .cameraPos = .{ .x = 0, .y = 0 },
        .winOffset = offset,
        .tracked = tracked,
    };
    _ = flecs.set(world, ent, Camera, cam);
    return ent;
}
