const std = @import("std");
const pixzig = @import("pixzig");
const flecs = pixzig.flecs;
const seq = pixzig.sequencer;
const scripting = pixzig.scripting;

const Frame = pixzig.sprites.Frame;
const FrameSequence = pixzig.sprites.FrameSequence;
const FrameSequenceManager = pixzig.sprites.FrameSequenceManager;
const Sprite = pixzig.sprites.Sprite;
const Actor = pixzig.sprites.Actor;
const FpsCounter = pixzig.utils.FpsCounter;
const Vec2F = pixzig.common.Vec2F;
const AppRunner = pixzig.AppRunner(App, .{});

// Maps a 0-1 color channel to the 0-255 range `renderer.clear` takes.
fn unit8(v: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(v, 0.0, 1.0) * 255.0));
}

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
    eng: *AppRunner.Engine,
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
        app.eng = eng;
        app.fps = FpsCounter.init();
        app.flashState = .{};
        app.seqPlayer = seq.SequencePlayer.init(alloc);
        app.seqMgr = try FrameSequenceManager.init(alloc);
        app.scriptEng = try scripting.ScriptEngine.init(alloc);

        // --- Build frame sequences ---
        var right_seq = try FrameSequence.init(alloc, &[_]Frame{
            .{ .tex = try eng.resources.acquireTexture("player_right_1"), .frameTimeMs = 70, .flip = .none },
            .{ .tex = try eng.resources.acquireTexture("player_right_2"), .frameTimeMs = 70, .flip = .none },
            .{ .tex = try eng.resources.acquireTexture("player_right_3"), .frameTimeMs = 70, .flip = .none },
        });
        right_seq.ownsHandles = true;
        try app.seqMgr.addSeq("player_right", right_seq);

        var down_seq = try FrameSequence.init(alloc, &[_]Frame{
            .{ .tex = try eng.resources.acquireTexture("player_down_1"), .frameTimeMs = 70, .flip = .none },
            .{ .tex = try eng.resources.acquireTexture("player_down_2"), .frameTimeMs = 70, .flip = .none },
            .{ .tex = try eng.resources.acquireTexture("player_down_3"), .frameTimeMs = 70, .flip = .none },
        });
        down_seq.ownsHandles = true;
        try app.seqMgr.addSeq("player_down", down_seq);

        // --- Set up flecs world with an Actor component (which owns its Sprite) ---
        app.world = flecs.init();
        flecs.COMPONENT(app.world, Sprite);
        flecs.COMPONENT(app.world, Actor);

        app.entity = flecs.new_entity(app.world, "player");

        var actor = Actor.init(alloc, Sprite.create(try eng.resources.getTexture("player_right_1")));
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
        self.scriptEng.deinit();
        self.seqCtx.deinit();
        // Free the Actor's states and release its sprite's texture while the
        // ECS component storage (and thus the Actor value) is still alive.
        if (flecs.get_mut(self.world, self.entity, Actor)) |actor| {
            actor.deinit();
        }
        _ = flecs.fini(self.world);
        self.seqPlayer.deinit();
        self.seqMgr.deinit();
        self.alloc.destroy(self);
    }

    fn runCircle(self: *App) !void {
        const actor = flecs.get(self.world, self.entity, Actor) orelse return;
        const pos = actor.sprite.pos();
        self.scriptEng.lua.pushInteger(@intCast(self.entity));
        self.scriptEng.lua.setGlobal("player_entity");
        self.scriptEng.lua.pushNumber(@floatCast(pos.x));
        self.scriptEng.lua.setGlobal("player_x");
        self.scriptEng.lua.pushNumber(@floatCast(pos.y));
        self.scriptEng.lua.setGlobal("player_y");
        try self.scriptEng.runScript("assets/circle_move.lua");
    }

    fn queueMove(self: *App, dir: []const u8, dx: f32, dy: f32) !void {
        const actor = flecs.get(self.world, self.entity, Actor) orelse return;
        const pos = actor.sprite.pos();
        const target = Vec2F{ .x = pos.x + dx, .y = pos.y + dy };

        var sequence = seq.Sequence.init(self.alloc);
        try sequence.add(self.alloc, try seq.SetActorStateStep.init(self.alloc, self.world, self.entity, dir));
        try sequence.add(self.alloc, try seq.MoveToStep.init(self.alloc, self.world, self.entity, target, 300.0));
        try sequence.add(self.alloc, try FlashStep.init(self.alloc, &self.flashState, 400.0, .{ 1, 1, 0, 1 }));
        try self.seqPlayer.add(sequence);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        // Tick flash state.
        if (self.flashState.active) {
            self.flashState.remainingMs -= delta;
            if (self.flashState.remainingMs <= 0) {
                self.flashState.active = false;
            }
        }

        // Advance the actor's animation (it updates its own sprite).
        if (flecs.get_mut(self.world, self.entity, Actor)) |actor| {
            actor.update(delta);
            flecs.modified(self.world, self.entity, Actor);
        }

        // Tick all active sequences.
        self.seqPlayer.update(delta);

        // Only process input if no sequences are running.
        if (self.seqPlayer.sequences.items.len == 0) {
            if (eng.inputs.keyboard.pressed(.right)) {
                self.queueMove("right", 16, 0) catch {};
            } else if (eng.inputs.keyboard.pressed(.left)) {
                self.queueMove("left", -16, 0) catch {};
            } else if (eng.inputs.keyboard.pressed(.down)) {
                self.queueMove("down", 0, 16) catch {};
            } else if (eng.inputs.keyboard.pressed(.up)) {
                self.queueMove("up", 0, -16) catch {};
            } else if (eng.inputs.keyboard.pressed(.c)) {
                self.runCircle() catch |err| {
                    std.log.err("circle_move.lua error: {}", .{err});
                };
            }
        }

        if (eng.inputs.keyboard.pressed(.escape)) return false;
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        // Blend clear color with flash color while flash is active.
        if (self.flashState.active) {
            const a = self.flashState.alpha();
            const c = self.flashState.color;
            eng.renderer.clear(unit8(0.2 + (c[0] - 0.2) * a), unit8(c[1] * a), unit8(0.2 + (c[2] - 0.2) * a), 255);
        } else {
            eng.renderer.clear(51, 0, 51, 255);
        }
        self.fps.renderTick();

        eng.renderer.begin(.logical);
        if (flecs.get_mut(self.world, self.entity, Actor)) |actor| {
            eng.renderer.drawSprite(&actor.sprite);
        }
        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig Sequencer Example", init.gpa, .{
        .logicalSize = .{ .x = 160, .y = 120 },
    });
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
