// zig fmt: off
const std = @import("std");
const pixzig = @import("pixzig");
const flecs = @import("zflecs"); 
const math = @import("zmath");

const RectF = pixzig.common.RectF;

const Renderer = pixzig.renderer.Renderer(.{});
const Color = pixzig.common.Color;
const shaders = pixzig.shaders;
const Shader = shaders.Shader;

const entities = @import("../entities.zig");
const Player = entities.Player;
const Mover = entities.Mover;
const Sprite = pixzig.sprites.Sprite;
const TileLayer = pixzig.tile.TileLayer;
const GridRenderer = pixzig.tile.GridRenderer;
const Vec2F = pixzig.common.Vec2F;
const C = @import("../constants.zig");

const Camera = @import("./camera.zig").Camera;

pub const Outlines = struct {
    alloc: std.mem.Allocator,
    world: *flecs.world_t,
    eng: *pixzig.PixzigEngine,
    camera: *Camera,
    query: *flecs.query_t,
    colorShader: pixzig.shaders.Shader,
    grid: GridRenderer,

    enabled: bool,
    
    const Self = @This();


    pub fn init(alloc: std.mem.Allocator, 
                world: *flecs.world_t, 
                eng: *pixzig.PixzigEngine,
                cam: *Camera) !Self 
    {
        const colorShader = try Shader.init(
                &shaders.ColorVertexShader,
                &shaders.ColorPixelShader
            );
        const grid = try GridRenderer.init(
                alloc, 
                colorShader, 
                .{ .x = C.MapWidth, .y = C.MapHeight}, 
                .{ .x = C.TileWidth, .y = C.TileHeight}, 
                1, 
                Color{.r=0.5, .g=0.0, .b=0.5, .a=1}
            );

        return .{
            .alloc = alloc,
            .world = world,
            .eng = eng,
            .camera = cam,
            .query = try flecs.query_init(world, &.{
                .filter = .{
                    .terms = [_]flecs.term_t{
                        .{ .id = flecs.id(Sprite) },
                    } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_DESC_MAX - 1),
                },
            }),
            .enabled = false,
            .colorShader = colorShader,
            .grid = grid
        };
    }

     pub fn deinit(self: *Self) void {
        flecs.query_fini(self.query);
        self.grid.deinit();
        self.colorShader.deinit();
    }

    pub fn update(self: *Self) void {
        if(self.eng.keyboard.pressed(.g)) {
            std.debug.print("Changing debug grid outlines to {}", .{self.enabled});
            self.enabled = !self.enabled;
        }
    }
    
    pub fn drawMapGrid(self: *Self, mvp: math.Mat) !void {
        if(self.enabled) {
            try self.grid.draw(mvp);
        }
    }
    pub fn drawSpriteOutlines(self: *Self, renderer: *Renderer) !void {
        if(self.enabled) {
            var it = flecs.query_iter(self.world, self.query);
            while (flecs.query_next(&it)) {
                const spr = flecs.field(&it, Sprite, 1).?;
                for (0..it.count()) |idx| {
                    renderer.drawEnclosingRect(spr[idx].dest, Color.from(100, 100, 255, 255), 1);
                }
            }
        }
    }
};
