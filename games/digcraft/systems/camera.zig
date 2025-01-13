// zig fmt: off
const std = @import("std");
const pixzig = @import("pixzig");
const flecs = @import("zflecs"); 
const math = @import("zmath");
const RectF = pixzig.common.RectF;

const entities = @import("../entities.zig");
const Camera = entities.Camera;
const Player = entities.Player;
const Mover = entities.Mover;
const Sprite = pixzig.sprites.Sprite;
const TileLayer = pixzig.tile.TileLayer;
const Vec2F = pixzig.common.Vec2F;
const C = @import("../constants.zig");

pub const CameraSystem = struct {
    world: *flecs.world_t,
    eng: *pixzig.PixzigEngine,
    baseMat: math.Mat,
    currCamera: ?flecs.entity_t,
    query: *flecs.query_t,
    
    const Self = @This();

    pub fn init(world: *flecs.world_t, eng: *pixzig.PixzigEngine, projMat: math.Mat) !Self {
        const baseMat = math.mul(math.scaling(C.Scale, C.Scale, 1.0), projMat);


        const offsX: f32 = @as(f32, @floatFromInt(eng.options.windowSize.x)) / 2.0 / C.Scale;
        const offsY: f32 = @as(f32, @floatFromInt(eng.options.windowSize.y)) / 2.0 / C.Scale;

        const currCamera = entities.spawnCamera(world, null, .{ .x = offsX, .y = offsY});
        return .{
            .world = world,
            .eng = eng,
            .baseMat = baseMat,
            .currCamera = currCamera,
            .query = try flecs.query_init(world, &.{
                .filter = .{
                    .terms = [_]flecs.term_t{
                        .{ .id = flecs.id(Camera) },
                    } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_DESC_MAX - 1),
                },
            }),
        };
    }

    pub fn deinit(self: *Self) void {
        flecs.query_fini(self.query);
    }

    pub fn currCameraMat(self: *Self) math.Mat {
        if(self.currCamera) |camId| {
            const mainCamera = flecs.get(self.world, camId, entities.Camera).?;
            return mainCamera.cameraMat;
        }
        else {
            return math.identity();
        }
    }

    pub fn update(self: *Self) void {
        var it = flecs.query_iter(self.world, self.query);
        while (flecs.query_next(&it)) {
            const cams = flecs.field(&it, Camera, 1).?;

            for (0..it.count()) |idx| {
                var cam: *Camera = &cams[idx];

                if(cam.tracked) |tr| {
                    const spr: ?*const Sprite = flecs.get(self.world, tr, Sprite);
                    if(spr) |sp| {
                        cam.cameraPos = sp.dest.pos2F();
                        cam.cameraMat = math.mul(
                            math.translation(@trunc(-cam.cameraPos.x+cam.winOffset.x), @trunc(-cam.cameraPos.y+cam.winOffset.y), 0.0), 
                            self.baseMat);
                    }
                }
            }
        }
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
