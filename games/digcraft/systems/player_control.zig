// zig fmt: off
const std = @import("std");
const pixzig = @import("pixzig");
const flecs = @import("zflecs"); 

const Vec2I = pixzig.common.Vec2I;
const RectF = pixzig.common.RectF;

const entities = @import("../entities.zig");
const Player = entities.Player;
const Mover = entities.Mover;
const Sprite = pixzig.sprites.Sprite;
const HumanController = entities.HumanController;
const TileLayer = pixzig.tile.TileLayer;
const TileMapRenderer = pixzig.tile.TileMapRenderer;

const C = @import("../constants.zig");

pub const PlayerControl = struct {
    world: *flecs.world_t,
    eng: *pixzig.PixzigEngine,
    mouse: *pixzig.input.Mouse,
    query: *flecs.query_t,

    pub fn init(world: *flecs.world_t, eng: *pixzig.PixzigEngine, mouse: *pixzig.input.Mouse) !@This() {
        return .{
            .world = world,
            .eng = eng,
            .mouse = mouse,
            .query = try flecs.query_init(world, &.{
                .filter = .{
                    .terms = [_]flecs.term_t{
                        .{ .id = flecs.id(Sprite) },
                        .{ .id = flecs.id(Mover) },
                        .{ .id = flecs.id(HumanController) },
                    } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_DESC_MAX - 3),
                },
            }),
        };
    }

    pub fn deinit(self: *@This()) void {
        flecs.query_fini(self.query);
    }

    fn getLeftBlockIndex(player: *RectF, map: *TileLayer) Vec2I {
        const right: i32 = @intFromFloat(player.l);
        const mid: i32 = @intFromFloat((player.t+player.b)/2.0);
        const tx = @divTrunc(right,map.tileSize.y) - 1;
        const ty = @divTrunc(mid,map.tileSize.y);

        return .{ .x = tx, .y = ty };
    }

    fn getRightBlockIndex(player: *RectF, map: *TileLayer) Vec2I {
        const right: i32 = @intFromFloat(player.r);
        const mid: i32 = @intFromFloat((player.t+player.b)/2.0);
        const tx = @divTrunc(right,map.tileSize.y) + 1;
        const ty = @divTrunc(mid,map.tileSize.y);

        return .{ .x = tx, .y = ty };
    }

    pub fn update(self: *@This(), map: *TileLayer, mapRenderer: *TileMapRenderer) !void {
        var it = flecs.query_iter(self.world, self.query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 1).?;
            const vel = flecs.field(&it, Mover, 2).?;
            const humCtrl = flecs.field(&it, HumanController, 3).?;

            for (0..it.count()) |idx| {
                var v: *Mover = &vel[idx];
                var sp: *Sprite = &spr[idx];
                var hum: *HumanController = &humCtrl[idx];

                if(!v.inAir and self.eng.keyboard.down(.up)) {
                    std.debug.print("YEET!\n", .{});
                    v.speed.y = -3;
                    v.inAir = true;
                }

                // Handle guy movement.
                if (self.eng.keyboard.down(.left)) {
                    _ = pixzig.tile.Mover.moveLeft(&sp.dest, 2, map, pixzig.tile.BlocksAll);
                }
                if (self.eng.keyboard.down(.right)) {
                    _ = pixzig.tile.Mover.moveRight(&sp.dest, 2, map, pixzig.tile.BlocksAll);
                }

                const tile: i32 = blk: {
                    if(self.eng.keyboard.down(.left_control)) {
                        break :blk -1;
                    }
                    else {
                        break :blk 1;
                    }
                };

                if(self.eng.keyboard.pressed(.a)) {
                    const tileLoc = getLeftBlockIndex(&sp.dest, map);
                    std.debug.print("Placing block at {}, {}\n", .{tileLoc.x, tileLoc.y});
                    map.setTileData(tileLoc.x, tileLoc.y, tile);
                    try mapRenderer.tileChanged(map.tileset.?, map, tileLoc, tile);
                    // mapRenderer.recreateVertices(map.tileset.?, map) catch unreachable;
                }
                if(self.eng.keyboard.pressed(.d)) {
                    const tileLoc = getRightBlockIndex(&sp.dest, map);
                    std.debug.print("Placing block at {}, {}\n", .{tileLoc.x, tileLoc.y});
                    map.setTileData(tileLoc.x, tileLoc.y, tile);
                    try mapRenderer.tileChanged(map.tileset.?, map, tileLoc, tile);
                    // mapRenderer.recreateVertices(map.tileset.?, map) catch unreachable;
                }

                const mousePos = self.mouse.pos().asVec2I();
                hum.cursorTile = .{ .x = @divFloor(mousePos.x,C.Scale), .y = @divFloor(mousePos.y,C.Scale) };
                // if(self.mouse.down(.left)) {
                //     v.speed.y = 0;
                //     sp.setPos(
                //         , 
                //         
                //     );
                // }

                // Respawn shortcut.
                if(self.eng.keyboard.pressed(.r)) {
                    sp.setPos(48, -100);
                }

                if(sp.dest.t > 900) {
                    std.debug.print("Respawning since too low!\n", .{});
                    sp.setPos(48, -100);
                }

                sp.dest.ensureSize(@as(i32, @intFromFloat(sp.size.x)), @as(i32, @intFromFloat(sp.size.y)));
            }
        }
    }
};
