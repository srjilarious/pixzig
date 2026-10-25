const std = @import("std");

const pixzig = @import("pixzig");
const flecs = pixzig.flecs;
const ecs = pixzig.ecs;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;
const Sprite = pixzig.sprites.Sprite;
pub const Player = struct { alive: bool };

pub const Velocity = struct { speed: Vec2F };

pub const Dot = struct {};

// The engine owns the action map (`eng.actions`) and updates it each tick.
// Scrolling uses two axes, each driven by a pair of arrow keys.
const Action = enum { pause, outlines, quit };
const Axis = enum { scroll_x, scroll_y };

const AppRunner = pixzig.AppRunner(App, .{
    .updateStepHz = 60.0,
    .actionOpts = .{ .Action = Action, .Axes = Axis },
    .screenshotHook = true,
});

pub const App = struct {
    alloc: std.mem.Allocator,
    eng: *AppRunner.Engine,
    scrollOffset: Vec2F,
    fps: FpsCounter,
    paused: bool,
    world: *flecs.world_t,
    updateQuery: *flecs.query_t,
    sprites: ecs.SpriteSystem,
    outlines: ecs.DebugOutlines,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const bigtex = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
        _ = try eng.resources.addSubTexture(bigtex, "guy", RectI.init(192, 64, 32, 32));

        try eng.actions.bind(.pause, .{ .key = .p });
        try eng.actions.bind(.outlines, .{ .key = .o });
        try eng.actions.bind(.quit, .{ .key = .escape });
        try eng.actions.bindAxis(.scroll_x, .{ .buttons = .{
            .negative = .{ .key = .left },
            .positive = .{ .key = .right },
        } });
        try eng.actions.bindAxis(.scroll_y, .{ .buttons = .{
            .negative = .{ .key = .up },
            .positive = .{ .key = .down },
        } });

        std.log.info("Initializing world.\n", .{});

        const world = flecs.init();

        std.log.info("Finished world init.", .{});
        ecs.registerEngineComponents(world);
        ecs.registerComponents(world, .{ Player, Velocity });

        std.log.info("Created components", .{});
        const updateQuery = try ecs.query(world, .{ Sprite, Velocity });
        var outlines = try ecs.DebugOutlines.init(world);
        outlines.enabled = true;
        outlines.lineWidth = 2;

        std.log.info("Created queries.", .{});

        var app = try alloc.create(App);
        app.* = App{
            .alloc = alloc,
            .eng = eng,
            .scrollOffset = .{ .x = 0, .y = 0 },
            .paused = false,
            .fps = FpsCounter.init(),
            .world = world,
            .updateQuery = updateQuery,
            .sprites = try ecs.SpriteSystem.init(world),
            .outlines = outlines,
        };

        std.log.info("Spawning 50 entities...", .{});
        std.log.info("  - Creating prng", .{});
        var prng = std.Random.DefaultPrng.init(0xdeadbeef);
        var random = prng.random();
        for (0..50) |_| {
            try app.spawn(&random, 1, 10, 50, true);
        }

        std.log.info("Done initializing the app.", .{});
        return app;
    }

    pub fn deinit(self: *App) void {
        flecs.query_fini(self.updateQuery);
        self.sprites.deinit();
        self.outlines.deinit();
        _ = flecs.fini(self.world);
        self.alloc.destroy(self);
    }

    pub fn spawn(self: *App, random: *std.Random, which: usize, x: i32, y: i32, val: bool) !void {
        std.log.info("Creating entity", .{});
        const ent = flecs.new_id(self.world);
        _ = which;
        // const srcX: i32 = @intCast(32*@rem(which, 16));
        // const srcY:i32 = @intCast(32*@divTrunc(which, 16));
        std.log.info("  - Creating sprite", .{});
        var spr = Sprite.create(try self.eng.resources.getTexture("guy"));

        spr.setPos(x, y);
        std.log.info("  - Setting sprite", .{});
        flecs.set(self.world, ent, Sprite, spr);

        std.log.info("  - Creating velocity component", .{});
        const vel = Velocity{ .speed = .{ .x = 2 * random.floatNorm(f32), .y = 2 * random.floatNorm(f32) } };

        flecs.set(self.world, ent, Velocity, vel);

        if (val) {
            std.log.info("  - Setting debug outline.", .{});
            flecs.set(self.world, ent, ecs.Outline, .{ .color = Color.from(100, 255, 200, 220) });
        }
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) void {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        // The view moves opposite to the scroll direction.
        const ScrollAmount = 3;
        self.scrollOffset.x -= eng.actions.axis(.scroll_x) * ScrollAmount;
        self.scrollOffset.y -= eng.actions.axis(.scroll_y) * ScrollAmount;
        if (eng.actions.pressed(.pause)) {
            self.paused = !self.paused;
        }
        if (eng.actions.pressed(.outlines)) self.outlines.toggle();
        if (eng.actions.pressed(.quit)) {
            eng.quit();
            return;
        }

        if (!self.paused) {
            var it = flecs.query_iter(self.world, self.updateQuery);
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
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 51, 255);

        self.fps.renderTick();

        eng.renderer.begin(.logical);

        self.sprites.draw(&eng.renderer);
        self.outlines.draw(&eng.renderer);

        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig: Flecs Example.", init.gpa, .{});
    defer appRunner.deinit();

    const app: *App = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
