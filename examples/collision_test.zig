// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import ("zstbi");
const zmath = @import("zmath"); 
const flecs = @import("zflecs"); 
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;
const Sprite = pixzig.sprites.Sprite;
const CollisionGrid = pixzig.collision.CollisionGrid;

const CollisionGridEntity = CollisionGrid(flecs.entity_t, 4);

const AppRunner =  pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    projMat: zmath.Mat,
    scrollOffset: Vec2F,
    spriteBatch: pixzig.renderer.SpriteBatchQueue,
    tex: *pixzig.Texture,
    texShader: pixzig.shaders.Shader,
    collideGrid: CollisionGridEntity,
    mouse: pixzig.input.Mouse,
    // colorShader: pixzig.shaders.Shader,
    // shapeBatch: pixzig.renderer.ShapeBatchQueue,
    fps: FpsCounter,
    paused: bool,
    world: *flecs.world_t,
    update_query: *flecs.query_t,
    draw_query: *flecs.query_t,
 
    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        var texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader
        );

        const bigtex = try eng.textures.loadTexture("tiles", "assets/pac-tiles.png");
        const tex = try eng.textures.addSubTexture(bigtex, "guy", RectF.fromCoords(32, 32, 32, 32, 512, 512));

        const spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(alloc, &texShader);

        // var colorShader = try pixzig.shaders.Shader.init(
        //         &pixzig.shaders.ColorVertexShader,
        //         &pixzig.shaders.ColorPixelShader
        //     );
        //
        // const shapeBatch = try pixzig.renderer.ShapeBatchQueue.init(alloc, &colorShader);
        std.debug.print("Done creating renderering data.\n", .{});

        const world = flecs.init();

        // flecs.COMPONENT(world, Player);
        flecs.COMPONENT(world, Sprite);
        // flecs.COMPONENT(world, Velocity);
        // flecs.COMPONENT(world, DebugOutline);

        const update_query = try flecs.query_init(world, &.{
            .terms = [_]flecs.term_t{
                .{ .id = flecs.id(Sprite) },
                // .{ .id = flecs.id(Velocity) },
            } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX - 1),
        });

        const query = try flecs.query_init(world, &.{
            .terms = [_]flecs.term_t{
                .{ .id = flecs.id(Sprite) },
            } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX - 1),
        });


        var app = try alloc.create(App);
        app.* = App{
            .alloc = alloc,
            .projMat = projMat,
            .scrollOffset = .{ .x = 0, .y = 0}, 
            .paused = false,
            .spriteBatch = spriteBatch,
            .mouse = pixzig.input.Mouse.init(eng.window, eng.allocator),
            // .shapeBatch = shapeBatch,
            .tex = tex,
            .texShader = texShader,
            .collideGrid = try CollisionGridEntity.init(alloc, .{ .x=100, .y=100}, .{.x=8, .y=8}),
            // .colorShader = colorShader,
            .fps = FpsCounter.init(),
            .world = world,
            .update_query = update_query,
            .draw_query = query,
        };

        for(0..10) |y| {
            for(0..10) |x| {
                try app.spawn(16, @intCast(x*16), @intCast(y*16));
            }
        }

        return app;
    }

    pub fn deinit(self: *App) void {
        self.spriteBatch.deinit();
        // self.shapeBatch.deinit();
        // self.colorShader.deinit();
        self.texShader.deinit();
        self.collideGrid.deinit();

        flecs.query_fini(self.update_query);
        flecs.query_fini(self.draw_query);
        _ = flecs.fini(self.world);

        self.alloc.destroy(self);
    }

    pub fn spawn(self: *App, which: usize, x: i32, y: i32) !void
    {
        const ent = flecs.new_id(self.world);
        _ = which;
        // const srcX: i32 = @intCast(32*@rem(which, 16));
        // const srcY: i32 = @intCast(32*@divTrunc(which, 16));
        var spr = Sprite.create(self.tex,
                .{ .x = 32, .y = 32});

        spr.setPos(x, y);
        _ = flecs.set(self.world, ent, Sprite, spr);

        try self.collideGrid.insertRect(spr.dest, ent);

        // var prng = std.rand.DefaultPrng.init(blk: {
        //     var seed: u64 = undefined;
        //     std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        //     break :blk seed;
        // });
        // 
        // const vel = Velocity{ .speed = .{
        //     .x = 2*prng.random().floatNorm(f32),
        //     .y = 2*prng.random().floatNorm(f32)
        // }};
        //
        // _ = flecs.set(self.world, ent, Velocity, vel);

        // if(val) {
        //     _ = flecs.set(self.world, ent, DebugOutline, .{ .color = Color.from(100, 255, 200, 220)});
        // }

    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();
        self.mouse.update();

        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
        // const ScrollAmount = 3;
        // if (eng.keyboard.down(.left)) {
        //     self.scrollOffset.x += ScrollAmount;
        // }
        // if (eng.keyboard.down(.right)) {
        //     self.scrollOffset.x -= ScrollAmount;
        // }
        // if (eng.keyboard.down(.up)) {
        //     self.scrollOffset.y += ScrollAmount;
        // }
        // if (eng.keyboard.down(.down)) {
        //     self.scrollOffset.y -= ScrollAmount;
        // }
        // if(eng.keyboard.pressed(.p)) {
        //     self.paused = !self.paused;
        // }
        if(eng.keyboard.pressed(.escape)) {
            return false;
        }

        
        if(!self.paused) {
            var it = flecs.query_iter(self.world, self.update_query);
            while (flecs.query_next(&it)) {
                const spr = flecs.field(&it, Sprite, 0).?;
                // const vel = flecs.field(&it, Velocity, 2).?;

                //const entities = it.entities();
                for (0..it.count()) |idx| {

                    // var v: *Velocity = &vel[idx];
                    var sp: *Sprite = &spr[idx];

                    // sp.dest.l += v.speed.x;
                    // if(sp.dest.l < 0 or sp.dest.l > 800 - sp.size.x) {
                    //     v.speed.x = -v.speed.x;
                    // }
                    //
                    // sp.dest.t += v.speed.y;
                    // if(sp.dest.t < 0 or sp.dest.t > 600 - sp.size.y) {
                    //     v.speed.y = -v.speed.y;
                    // }

                    sp.dest.ensureSize(@as(i32, @intFromFloat(sp.size.x)), @as(i32, @intFromFloat(sp.size.y)));

                    //spr[idx].draw(&self.spriteBatch) catch {};

                    //const e = entities[idx];

                    // const outline = flecs.get(self.world, e, DebugOutline);
                    // if(outline != null) {
                    //     self.shapeBatch.drawEnclosingRect(spr[idx].dest, outline.?.color, 2);
                    // }
                }
            }
        }

        const mousePos = self.mouse.pos().asVec2I();
        var hits: [4]?flecs.entity_t = .{ null, null, null, null };
        const num = try self.collideGrid.checkPoint(mousePos, &hits[0..]);
        if(num > 0) {
            for(0..num) |idx| {
                std.debug.print("Hit {?}\n", .{hits[idx]});
                try self.collideGrid.removeRect(RectF.fromPosSize(mousePos.x, mousePos.y, 16, 16), hits[idx].?);
                flecs.delete(self.world, hits[idx].?);
            }
        }
        
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        self.fps.renderTick();
       
        self.spriteBatch.begin(self.projMat);

        var it = flecs.query_iter(self.world, self.draw_query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 0).?;
            //const debug = flecs.field(&it, DebugOutline, 2).?;

            // const entities = it.entities();
            for (0..it.count()) |idx| {
                self.spriteBatch.drawSprite(&spr[idx]);
                // const e = entities[idx];

                // const outline = flecs.get(self.world, e, DebugOutline);
                // if(outline != null) {
                //     self.shapeBatch.drawEnclosingRect(spr[idx].dest, outline.?.color, 2);
                // }
            }
        }

        self.spriteBatch.end();
    }
};



pub fn main() !void {
    std.log.info("Pixzig Tile Collision Example", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig: Tile Collision Example.", alloc, .{});

    std.log.info("Initializing app.\n", .{});
    const app: *App = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
