const std = @import("std");
const builtin = @import("builtin");

const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
const flecs = pixzig.flecs;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;
const Sprite = pixzig.sprites.Sprite;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

pub const Player = struct { alive: bool };
pub const DebugOutline = struct { color: Color };

pub const Velocity = struct { speed: Vec2F };

pub const Dot = struct {};

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    scrollOffset: Vec2F,
    tex: *pixzig.Texture,
    fps: FpsCounter,
    paused: bool,
    world: *flecs.world_t,
    update_query: *flecs.query_t,
    draw_query: *flecs.query_t,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const bigtex = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");

        const tex = try eng.resources.addSubTexture(bigtex, "guy", RectF.fromCoords(192, 64, 32, 32, 512, 512));

        std.log.info("Initializing world.\n", .{});

        const world = flecs.init();

        std.log.info("Finished world init.", .{});
        flecs.COMPONENT(world, Player);
        flecs.COMPONENT(world, Sprite);
        flecs.COMPONENT(world, Velocity);
        flecs.COMPONENT(world, DebugOutline);

        std.log.info("Created components", .{});
        const update_query = try flecs.query_init(world, &.{
            .terms = [_]flecs.term_t{
                .{ .id = flecs.id(Sprite) },
                .{ .id = flecs.id(Velocity) },
            } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX - 2),
        });

        const query = try flecs.query_init(world, &.{
            .terms = [_]flecs.term_t{
                .{ .id = flecs.id(Sprite) },
            } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX - 1),
        });

        std.log.info("Created queries.", .{});

        var app = try alloc.create(App);
        app.* = App{
            .alloc = alloc,
            .scrollOffset = .{ .x = 0, .y = 0 },
            .paused = false,
            .tex = tex,
            .fps = FpsCounter.init(),
            .world = world,
            .update_query = update_query,
            .draw_query = query,
        };

        std.log.info("Spawning 50 entities...", .{});
        std.log.info("  - Creating prng", .{});
        var prng = std.Random.DefaultPrng.init(0xdeadbeef);
        var random = prng.random();
        for (0..50) |_| {
            app.spawn(&random, 1, 10, 50, true);
        }

        std.log.info("Done initializing the app.", .{});
        return app;
    }

    pub fn deinit(self: *App) void {
        flecs.query_fini(self.draw_query);
        _ = flecs.fini(self.world);
        self.alloc.destroy(self);
    }

    pub fn spawn(self: *App, random: *std.Random, which: usize, x: i32, y: i32, val: bool) void {
        std.log.info("Creating entity", .{});
        const ent = flecs.new_id(self.world);
        _ = which;
        // const srcX: i32 = @intCast(32*@rem(which, 16));
        // const srcY:i32 = @intCast(32*@divTrunc(which, 16));
        std.log.info("  - Creating sprite", .{});
        var spr = Sprite.create(self.tex, .{ .x = 32, .y = 32 });

        spr.setPos(x, y);
        std.log.info("  - Setting sprite", .{});
        flecs.set(self.world, ent, Sprite, spr);

        std.log.info("  - Creating velocity component", .{});
        const vel = Velocity{ .speed = .{ .x = 2 * random.floatNorm(f32), .y = 2 * random.floatNorm(f32) } };

        flecs.set(self.world, ent, Velocity, vel);

        if (val) {
            std.log.info("  - Setting debug outline.", .{});
            flecs.set(self.world, ent, DebugOutline, .{ .color = Color.from(100, 255, 200, 220) });
        }
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
        const ScrollAmount = 3;
        if (eng.keyboard.down(.left)) {
            self.scrollOffset.x += ScrollAmount;
        }
        if (eng.keyboard.down(.right)) {
            self.scrollOffset.x -= ScrollAmount;
        }
        if (eng.keyboard.down(.up)) {
            self.scrollOffset.y += ScrollAmount;
        }
        if (eng.keyboard.down(.down)) {
            self.scrollOffset.y -= ScrollAmount;
        }
        if (eng.keyboard.pressed(.p)) {
            self.paused = !self.paused;
        }
        if (eng.keyboard.pressed(.escape)) {
            return false;
        }

        if (!self.paused) {
            var it = flecs.query_iter(self.world, self.update_query);
            while (flecs.query_next(&it)) {
                const spr = flecs.field(&it, Sprite, 0).?;
                const vel = flecs.field(&it, Velocity, 1).?;

                //const entities = it.entities();
                for (0..it.count()) |idx| {
                    var v: *Velocity = &vel[idx];
                    var sp: *Sprite = &spr[idx];

                    sp.dest.l += v.speed.x;
                    if (sp.dest.l < 0 or sp.dest.l > 800 - sp.size.x) {
                        v.speed.x = -v.speed.x;
                    }

                    sp.dest.t += v.speed.y;
                    if (sp.dest.t < 0 or sp.dest.t > 600 - sp.size.y) {
                        v.speed.y = -v.speed.y;
                    }

                    sp.dest.ensureSize(@as(i32, @intFromFloat(sp.size.x)), @as(i32, @intFromFloat(sp.size.y)));
                }
            }
        }

        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);

        self.fps.renderTick();

        eng.renderer.begin(eng.projMat);

        var it = flecs.query_iter(self.world, self.draw_query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 0).?;

            const entities = it.entities();
            for (0..it.count()) |idx| {
                eng.renderer.drawSprite(&spr[idx]);
                const e = entities[idx];

                // Check for a DebugOutline component on the entity.
                const outline = flecs.get(self.world, e, DebugOutline);
                if (outline != null) {
                    eng.renderer.drawEnclosingRect(spr[idx].dest, outline.?.color, 2);
                }
            }
        }

        eng.renderer.end();
    }
};

pub fn main() !void {
    std.log.info("Pixzig: Flecs Example", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig: Flecs Example.", alloc, .{});

    std.log.info("Initializing app.\n", .{});
    const app: *App = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
