// zig fmt: off
const std = @import("std");
const pixzig = @import("pixzig");
const flecs = @import("zflecs"); 
const math = @import("zmath");

const RectF = pixzig.common.RectF;

const entities = @import("../entities.zig");
const Player = entities.Player;
const Mover = entities.Mover;
const Sprite = pixzig.sprites.Sprite;
const TileLayer = pixzig.tile.TileLayer;
const Vec2F = pixzig.common.Vec2F;
const C = @import("../constants.zig");

pub const Camera = struct {
    world: *flecs.world_t,
    eng: *pixzig.PixzigEngine,
    baseMat: math.Mat,
    cameraMat: math.Mat,
    cameraPos: Vec2F,
    winOffset: Vec2F,
    tracked: ?flecs.entity_t,
    // query: *flecs.query_t,
    
    const Self = @This();

    pub fn init(world: *flecs.world_t, eng: *pixzig.PixzigEngine, projMat: math.Mat) !Self {
        const baseMat = math.mul(math.scaling(C.Scale, C.Scale, 1.0), projMat);

        const offsX: f32 = @as(f32, @floatFromInt(eng.options.windowSize.x)) / 2.0 / C.Scale;
        const offsY: f32 = @as(f32, @floatFromInt(eng.options.windowSize.y)) / 2.0 / C.Scale;
        return .{
            .world = world,
            .eng = eng,
            .baseMat = baseMat,
            .cameraMat = projMat,
            .winOffset = .{ .x = offsX, .y = offsY},
            .cameraPos = .{ .x = 0, .y = 0 },
            .tracked = null,
            // .query = try flecs.query_init(world, &.{
            //     .filter = .{
            //         .terms = [_]flecs.term_t{
            //             .{ .id = flecs.id(Sprite) },
            //             .{ .id = flecs.id(Mover) },
            //         } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_DESC_MAX - 2),
            //     },
            // }),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // flecs.query_fini(self.query);
    }

    pub fn update(self: *Self) void {
        if(self.tracked) |tr| {
            const spr: ?*const Sprite = flecs.get(self.world, tr, Sprite);
            if(spr) |sp| {
                self.cameraPos = sp.dest.pos2F();
                self.cameraMat = math.mul(
                    math.translation(@trunc(-self.cameraPos.x+self.winOffset.x), @trunc(-self.cameraPos.y+self.winOffset.y), 0.0), 
                    self.baseMat);
            }
        }

        // var it = flecs.query_iter(self.world, self.query);
        // while (flecs.query_next(&it)) {
        //     const spr = flecs.field(&it, Sprite, 1).?;
        //     const vel = flecs.field(&it, Mover, 2).?;
        //
        //     for (0..it.count()) |idx| {
        //         var v: *Mover = &vel[idx];
        //         var sp: *Sprite = &spr[idx];
        //
        //         if(!v.inAir and self.eng.keyboard.down(.up)) {
        //             std.debug.print("YEET!\n", .{});
        //             v.speed.y = -3;
        //             v.inAir = true;
        //         }
        //
        //         // Handle guy movement.
        //         if (self.eng.keyboard.down(.left)) {
        //             _ = pixzig.tile.Mover.moveLeft(&sp.dest, 2, map, pixzig.tile.BlocksAll);
        //         }
        //         if (self.eng.keyboard.down(.right)) {
        //             _ = pixzig.tile.Mover.moveRight(&sp.dest, 2, map, pixzig.tile.BlocksAll);
        //         }
        //
        //         if(self.mouse.down(.left)) {
        //             v.speed.y = 0;
        //             const mousePos = self.mouse.pos().asVec2I();
        //             sp.setPos(
        //                 @divFloor(mousePos.x,C.Scale), 
        //                 @divFloor(mousePos.y,C.Scale)
        //             );
        //         }
        //         sp.dest.ensureSize(@as(i32, @intFromFloat(sp.size.x)), @as(i32, @intFromFloat(sp.size.y)));
        //     }
        // }
    }
};