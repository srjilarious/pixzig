const std = @import("std");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const flecs = pixzig.flecs;
const seq = pixzig.sequencer;
const scripting = pixzig.scripting;

const Frame = pixzig.sprites.Frame;
const FrameSequence = pixzig.sprites.FrameSequence;
const FrameSequenceManager = pixzig.sprites.FrameSequenceManager;
const ActorState = pixzig.sprites.ActorState;
const Sprite = pixzig.sprites.Sprite;
const Actor = pixzig.sprites.Actor;
const FpsCounter = pixzig.utils.FpsCounter;
const Vec2F = pixzig.common.Vec2F;

pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{ .gameScale = 8.0 });

// Game-specific flash state. Owned by App; shared with FlashStep via pointer.
pub const FlashState = struct {
    active: bool = false,
    remainingMs: f64 = 0,
    totalMs: f64 = 0,
    color: [4]f32 = .{ 1, 1, 0, 1 },

    pub fn alpha(self: *const FlashState) f32 {
        if (!self.active or self.totalMs <= 0) return 0;
        return @floatCast(self.remainingMs / self.totalMs);
    }
};

// Game-side custom step: fire-and-forget, activates the shared FlashState.
pub const FlashStep = struct {
    flash: *FlashState,
    durationMs: f64,
    color: [4]f32,

    const vtable: seq.Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(
        alloc: std.mem.Allocator,
        flash: *FlashState,
        durationMs: f64,
        color: [4]f32,
    ) !seq.Step {
        const ptr = try alloc.create(FlashStep);
        ptr.* = .{ .flash = flash, .durationMs = durationMs, .color = color };
        return .{ .ptr = ptr, .vtable = &vtable, .done = false };
    }

    pub fn update(step: *seq.Step, deltaMs: f64) f64 {
        _ = deltaMs;
        const self: *FlashStep = @ptrCast(@alignCast(step.ptr));
        self.flash.* = .{
            .active = true,
            .remainingMs = self.durationMs,
            .totalMs = self.durationMs,
            .color = self.color,
        };
        step.done = true;
        return -1.0;
    }

    pub fn deinit(step: *seq.Step, alloc: std.mem.Allocator) void {
        const self: *FlashStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }
};

pub const App = struct {
    alloc: std.mem.Allocator,
    world: *flecs.world_t,
    entity: flecs.entity_t,
    seqMgr: FrameSequenceManager,
    seqPlayer: seq.SequencePlayer,
    seqCtx: seq.SeqScriptingContext,
    scriptEng: scripting.ScriptEngine,
    flashState: FlashState,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        _ = try eng.resources.loadAtlas("assets/pac-tiles");

        var app = try alloc.create(App);
        app.alloc = alloc;
        app.fps = FpsCounter.init();
        app.flashState = .{};
        app.seqPlayer = seq.SequencePlayer.init(alloc);
        app.seqMgr = try FrameSequenceManager.init(alloc);
        app.scriptEng = try scripting.ScriptEngine.init(alloc);

        // --- Build frame sequences ---
        const right_seq = try FrameSequence.init(alloc, &[_]Frame{
            .{ .tex = try eng.resources.getTexture("player_right_1"), .frameTimeMs = 70, .flip = .none },
            .{ .tex = try eng.resources.getTexture("player_right_2"), .frameTimeMs = 70, .flip = .none },
            .{ .tex = try eng.resources.getTexture("player_right_3"), .frameTimeMs = 70, .flip = .none },
        });
        try app.seqMgr.addSeq("player_right", right_seq);

        const down_seq = try FrameSequence.init(alloc, &[_]Frame{
            .{ .tex = try eng.resources.getTexture("player_down_1"), .frameTimeMs = 70, .flip = .none },
            .{ .tex = try eng.resources.getTexture("player_down_2"), .frameTimeMs = 70, .flip = .none },
            .{ .tex = try eng.resources.getTexture("player_down_3"), .frameTimeMs = 70, .flip = .none },
        });
        try app.seqMgr.addSeq("player_down", down_seq);

        // --- Set up flecs world with Sprite and Actor components ---
        app.world = flecs.init();
        flecs.COMPONENT(app.world, Sprite);
        flecs.COMPONENT(app.world, Actor);

        app.entity = flecs.new_entity(app.world, "player");

        const spr = Sprite.create(
            try eng.resources.getTexture("player_right_1"),
            .{ .x = 16, .y = 16 },
        );
        flecs.set(app.world, app.entity, Sprite, spr);

        var actor = try Actor.init(alloc);
        _ = try actor.addState(&.{ .name = "right", .sequence = app.seqMgr.getSeq("player_right").?, .flip = .none }, .{});
        _ = try actor.addState(&.{ .name = "left", .sequence = app.seqMgr.getSeq("player_right").?, .flip = .horz }, .{});
        _ = try actor.addState(&.{ .name = "down", .sequence = app.seqMgr.getSeq("player_down").?, .flip = .none }, .{});
        _ = try actor.addState(&.{ .name = "up", .sequence = app.seqMgr.getSeq("player_down").?, .flip = .vert }, .{});
        actor.setState("right");
        flecs.set(app.world, app.entity, Actor, actor);

        // --- Set up scripting context and bind Lua functions ---
        app.seqCtx = seq.SeqScriptingContext.init(alloc, app.world, &app.seqPlayer);
        app.seqCtx.bindToLua(app.scriptEng.lua);

        return app;
    }

    pub fn deinit(self: *App) void {
        self.seqCtx.deinit();
        self.scriptEng.deinit();
        // Free the Actor's StringHashMap before destroying the world.
        if (flecs.get_mut(self.world, self.entity, Actor)) |actor| {
            actor.deinit();
        }
        _ = flecs.fini(self.world);
        self.seqPlayer.deinit();
        self.seqMgr.deinit();
        self.alloc.destroy(self);
    }

    fn runCircle(self: *App) !void {
        const spr = flecs.get(self.world, self.entity, Sprite) orelse return;
        self.scriptEng.lua.pushInteger(@intCast(self.entity));
        self.scriptEng.lua.setGlobal("player_entity");
        self.scriptEng.lua.pushNumber(@floatCast(spr.dest.l));
        self.scriptEng.lua.setGlobal("player_x");
        self.scriptEng.lua.pushNumber(@floatCast(spr.dest.t));
        self.scriptEng.lua.setGlobal("player_y");
        try self.scriptEng.runScript("assets/circle_move.lua");
    }

    fn queueMove(self: *App, dir: []const u8, dx: f32, dy: f32) !void {
        const spr = flecs.get(self.world, self.entity, Sprite) orelse return;
        const target = Vec2F{ .x = spr.dest.l + dx, .y = spr.dest.t + dy };

        var sequence = seq.Sequence.init(self.alloc);
        try sequence.add(self.alloc, try seq.SetActorStateStep.init(self.alloc, self.world, self.entity, dir));
        try sequence.add(self.alloc, try seq.MoveToStep.init(self.alloc, self.world, self.entity, target, 300.0));
        try sequence.add(self.alloc, try FlashStep.init(self.alloc, &self.flashState, 400.0, .{ 1, 1, 0, 1 }));
        try self.seqPlayer.add(sequence);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        // Tick flash state.
        if (self.flashState.active) {
            self.flashState.remainingMs -= delta;
            if (self.flashState.remainingMs <= 0) {
                self.flashState.active = false;
            }
        }

        // Update actor animation on the ECS sprite.
        if (flecs.get_mut(self.world, self.entity, Actor)) |actor| {
            if (flecs.get_mut(self.world, self.entity, Sprite)) |spr| {
                actor.update(delta, spr);
                flecs.modified(self.world, self.entity, Sprite);
                flecs.modified(self.world, self.entity, Actor);
            }
        }

        // Tick all active sequences.
        self.seqPlayer.update(delta);

        // Only process input if no sequences are running.
        if (self.seqPlayer.sequences.items.len == 0) {
            if (eng.keyboard.pressed(.right)) {
                self.queueMove("right", 16, 0) catch {};
            } else if (eng.keyboard.pressed(.left)) {
                self.queueMove("left", -16, 0) catch {};
            } else if (eng.keyboard.pressed(.down)) {
                self.queueMove("down", 0, 16) catch {};
            } else if (eng.keyboard.pressed(.up)) {
                self.queueMove("up", 0, -16) catch {};
            } else if (eng.keyboard.pressed(.c)) {
                self.runCircle() catch |err| {
                    std.log.err("circle_move.lua error: {}", .{err});
                };
            }
        }

        if (eng.keyboard.pressed(.escape)) return false;
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        // Blend clear color with flash color while flash is active.
        if (self.flashState.active) {
            const a = self.flashState.alpha();
            const c = self.flashState.color;
            eng.renderer.clear(0.2 + (c[0] - 0.2) * a, c[1] * a, 0.2 + (c[2] - 0.2) * a, 1);
        } else {
            eng.renderer.clear(0.2, 0, 0.2, 1);
        }
        self.fps.renderTick();

        eng.renderer.begin(eng.projMat);
        if (flecs.get_mut(self.world, self.entity, Sprite)) |spr| {
            eng.renderer.drawSprite(spr);
        }
        eng.renderer.end();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Sequencer Example", .{});
    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig Sequencer Example", alloc, .{});
    const app = try App.init(alloc, appRunner.engine);
    glfw.swapInterval(0);
    appRunner.run(app);
}
