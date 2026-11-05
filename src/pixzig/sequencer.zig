//! An action sequencer for coordinating timed game events.
//! Sequences are sequential sets of steps, with a ParallelStep for concurrent steps.
//! Steps follow an OO pattern with a VTable in order to allow extension in games.
const std = @import("std");
const common = @import("./common.zig");
const sprites = @import("./renderer/sprites.zig");
const flecs = @import("zflecs");
const ziglua = @import("ziglua");
const scripting = @import("./scripting.zig");
const easing = @import("./easing.zig");
const Lua = ziglua.Lua;
const ScriptEngine = scripting.ScriptEngine;
const Vec2F = common.Vec2F;
const Ease = easing.Ease;
const Color = common.Color;
const Sprite = sprites.Sprite;
const Actor = sprites.Actor;

/// Maximum length for a step or sequence name, used for debugging and Lua
/// bindings.
pub const MAX_NAME_LEN = 64;

/// A single step in a sequence. Steps are heap allocated and owned by the
/// Sequence that contains them.
///
/// A step is a type-erased pointer to the step's own struct plus a vtable.
/// To write a game step, define a struct holding the step's state, give it
/// a `const vtable: Step.VTable` with `update` and `deinit` functions, and
/// an `init` that heap-allocates the struct and returns
/// `.{ .ptr = ptr, .vtable = &vtable }`. See `WaitStep` for the smallest
/// example.
pub const Step = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    /// What a step's `update` reports.
    pub const Status = union(enum) {
        /// The step used all of the delta and needs more time.
        running,
        /// The step is finished. The payload is how much of the delta (in
        /// ms) it didn't need; the sequence hands that to the next step in
        /// the same tick. A zero-time step returns the whole delta.
        finished: f64,
    };

    pub const VTable = struct {
        /// Advances the step by `deltaMs`. Called every tick while the step
        /// is current. When the step before it finished partway through a
        /// tick, the first call gets only what was left of that tick, which
        /// may be 0. Never called again once it has returned `.finished`.
        update: *const fn (step: *Step, deltaMs: f64) Status,
        /// Free any heap memory owned by the step.
        deinit: *const fn (step: *Step, alloc: std.mem.Allocator) void,
    };

    pub fn update(self: *Step, deltaMs: f64) Status {
        return self.vtable.update(self, deltaMs);
    }

    pub fn deinit(self: *Step, alloc: std.mem.Allocator) void {
        self.vtable.deinit(self, alloc);
    }

    /// The status of a step that has run for `elapsedMs` of its
    /// `durationMs`: finished, with the overshoot left over, once elapsed
    /// reaches the duration.
    pub fn timed(elapsedMs: f64, durationMs: f64) Status {
        if (elapsedMs >= durationMs) return .{ .finished = elapsedMs - @max(durationMs, 0) };
        return .running;
    }
};

/// A step that waits for a specified amount of time before finishing.
pub const WaitStep = struct {
    durationMs: f64,
    elapsedMs: f64,
    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(alloc: std.mem.Allocator, durationMs: f64) !Step {
        const ptr = try alloc.create(WaitStep);
        ptr.* = WaitStep{ .durationMs = durationMs, .elapsedMs = 0 };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *WaitStep = @ptrCast(@alignCast(step.ptr));
        self.elapsedMs += deltaMs;
        return Step.timed(self.elapsedMs, self.durationMs);
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *WaitStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }
};

/// A step that contains multiple sub-steps that are updated in parallel. The
/// step finishes when all sub-steps are finished. Sub-steps are added via the
/// add() method, which takes a Step struct and appends it to the list of
/// sub-steps.
pub const ParallelStep = struct {
    tracks: std.ArrayListUnmanaged(Track),

    const Track = struct {
        step: Step,
        finished: bool,
    };

    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(alloc: std.mem.Allocator) !Step {
        const ptr = try alloc.create(ParallelStep);
        ptr.* = ParallelStep{ .tracks = .empty };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    /// Adds `subStep`, which the parallel step then owns.
    pub fn add(step: *Step, alloc: std.mem.Allocator, subStep: Step) !void {
        const self: *ParallelStep = @ptrCast(@alignCast(step.ptr));
        try self.tracks.append(alloc, .{ .step = subStep, .finished = false });
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *ParallelStep = @ptrCast(@alignCast(step.ptr));
        var allFinished = true;
        // The step finishes with the slowest sub-step, so what's left over
        // is the smallest leftover among the ones finishing this tick.
        var leftoverMs = deltaMs;
        for (self.tracks.items) |*track| {
            // A finished sub-step isn't run again, so one-shot steps (like
            // a LuaCallStep) fire once while the others catch up.
            if (track.finished) continue;
            switch (track.step.update(deltaMs)) {
                .running => allFinished = false,
                .finished => |left| {
                    track.finished = true;
                    leftoverMs = @min(leftoverMs, left);
                },
            }
        }
        if (!allFinished) return .running;
        return .{ .finished = leftoverMs };
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *ParallelStep = @ptrCast(@alignCast(step.ptr));
        for (self.tracks.items) |*track| {
            track.step.deinit(alloc);
        }
        self.tracks.deinit(alloc);
        alloc.destroy(self);
    }
};

/// Lerps a sprite's position (its origin, see `Sprite.pos`) from its location
/// on first tick to `target` over `durationMs`. The sprite is the entity's
/// `Sprite` component, or else its `Actor`'s sprite, so the world must have
/// both component types registered. Captures start position lazily on the
/// first update call. `init` moves at a constant speed; `initEased` follows
/// an easing curve instead.
pub const MoveToStep = struct {
    world: *flecs.world_t,
    entityId: flecs.entity_t,
    target: Vec2F,
    durationMs: f64,
    elapsedMs: f64,
    startPos: ?Vec2F,
    ease: Ease,

    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(
        alloc: std.mem.Allocator,
        world: *flecs.world_t,
        entityId: flecs.entity_t,
        target: Vec2F,
        durationMs: f64,
    ) !Step {
        return initEased(alloc, world, entityId, target, durationMs, .linear);
    }

    /// Like `init`, but the position follows `ease` from start to target,
    /// e.g. `.quad_out` to decelerate into place.
    pub fn initEased(
        alloc: std.mem.Allocator,
        world: *flecs.world_t,
        entityId: flecs.entity_t,
        target: Vec2F,
        durationMs: f64,
        ease: Ease,
    ) !Step {
        const ptr = try alloc.create(MoveToStep);
        ptr.* = .{
            .world = world,
            .entityId = entityId,
            .target = target,
            .durationMs = durationMs,
            .elapsedMs = 0,
            .startPos = null,
            .ease = ease,
        };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *MoveToStep = @ptrCast(@alignCast(step.ptr));
        // An entity without a sprite has nothing to move.
        const spr = self.sprite() orelse return .{ .finished = deltaMs };

        // Lazy-capture start position on the first tick.
        if (self.startPos == null) {
            self.startPos = spr.pos();
        }

        self.elapsedMs += deltaMs;
        const t: f32 = progress(self.elapsedMs, self.durationMs);
        const pos = self.startPos.?.lerp(self.target, self.ease.apply(t));
        spr.setPosF(pos.x, pos.y);
        self.markModified();

        return Step.timed(self.elapsedMs, self.durationMs);
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *MoveToStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }

    fn sprite(self: *MoveToStep) ?*Sprite {
        if (flecs.get_mut(self.world, self.entityId, Sprite)) |spr| return spr;
        if (flecs.get_mut(self.world, self.entityId, Actor)) |actor| return &actor.sprite;
        return null;
    }

    fn markModified(self: *MoveToStep) void {
        if (flecs.get_mut(self.world, self.entityId, Sprite) != null) {
            flecs.modified(self.world, self.entityId, Sprite);
        } else {
            flecs.modified(self.world, self.entityId, Actor);
        }
    }
};

/// How far `elapsedMs` is through `durationMs`, from 0 to 1. A zero (or
/// negative) duration is already at the end.
fn progress(elapsedMs: f64, durationMs: f64) f32 {
    if (durationMs <= 0) return 1.0;
    return @floatCast(@min(elapsedMs / durationMs, 1.0));
}

/// Tweens one value from `from` to `to` over `durationMs` along an easing
/// curve, handing each tick's value to a callback. For anything a game can
/// drive from a single f32: a fade's alpha, a camera's zoom, a scale pop.
///
/// ```zig
/// fn setFade(self: *Game, alpha: f32) void { self.fadeAlpha = alpha; }
/// ...
/// try sequence.add(alloc, try seq.TweenStep.init(alloc, Game, self, setFade, 0, 1, 500, .sine_in_out));
/// ```
///
/// `ctx` must outlive the step, so point it at something stable (the game
/// struct), not into a flecs component array that can move.
pub const TweenStep = struct {
    ctx: *anyopaque,
    applyFn: *const fn (ctx: *anyopaque, value: f32) void,
    from: f32,
    to: f32,
    durationMs: f64,
    elapsedMs: f64,
    ease: Ease,

    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(
        alloc: std.mem.Allocator,
        comptime Ctx: type,
        ctx: *Ctx,
        comptime apply: fn (ctx: *Ctx, value: f32) void,
        from: f32,
        to: f32,
        durationMs: f64,
        ease: Ease,
    ) !Step {
        const Erased = struct {
            fn call(p: *anyopaque, value: f32) void {
                apply(@ptrCast(@alignCast(p)), value);
            }
        };

        const ptr = try alloc.create(TweenStep);
        ptr.* = .{
            .ctx = ctx,
            .applyFn = Erased.call,
            .from = from,
            .to = to,
            .durationMs = durationMs,
            .elapsedMs = 0,
            .ease = ease,
        };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *TweenStep = @ptrCast(@alignCast(step.ptr));
        self.elapsedMs += deltaMs;
        const t = progress(self.elapsedMs, self.durationMs);
        self.applyFn(self.ctx, easing.tween(self.ease, self.from, self.to, t));
        return Step.timed(self.elapsedMs, self.durationMs);
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *TweenStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }
};

/// Immediately switches an entity's Actor animation state. Fire-and-forget;
/// completes in zero time. The state name slice is owned and freed by the step.
pub const SetActorStateStep = struct {
    world: *flecs.world_t,
    entityId: flecs.entity_t,
    stateName: []u8,

    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(
        alloc: std.mem.Allocator,
        world: *flecs.world_t,
        entityId: flecs.entity_t,
        stateName: []const u8,
    ) !Step {
        const ptr = try alloc.create(SetActorStateStep);
        errdefer alloc.destroy(ptr);
        ptr.* = .{
            .world = world,
            .entityId = entityId,
            .stateName = try alloc.dupe(u8, stateName),
        };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *SetActorStateStep = @ptrCast(@alignCast(step.ptr));
        if (flecs.get_mut(self.world, self.entityId, Actor)) |actor| {
            actor.setState(self.stateName, .{}) catch |err| {
                std.log.warn("SetActorStateStep: can't set state '{s}': {}", .{ self.stateName, err });
            };
            flecs.modified(self.world, self.entityId, Actor);
        }
        return .{ .finished = deltaMs };
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *SetActorStateStep = @ptrCast(@alignCast(step.ptr));
        alloc.free(self.stateName);
        alloc.destroy(self);
    }
};

/// Tweens an f32 the game owns from whatever it holds when the step starts
/// to `to`, over `durationMs` along an easing curve. Unlike `TweenStep`, the
/// start value is read on the first tick, so a tween can pick up where an
/// earlier (or cancelled) one left the value. `target` must outlive the step.
pub const TweenValueStep = struct {
    target: *f32,
    from: ?f32,
    to: f32,
    durationMs: f64,
    elapsedMs: f64,
    ease: Ease,

    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(alloc: std.mem.Allocator, target: *f32, to: f32, durationMs: f64, ease: Ease) !Step {
        const ptr = try alloc.create(TweenValueStep);
        ptr.* = .{
            .target = target,
            .from = null,
            .to = to,
            .durationMs = durationMs,
            .elapsedMs = 0,
            .ease = ease,
        };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *TweenValueStep = @ptrCast(@alignCast(step.ptr));
        if (self.from == null) self.from = self.target.*;

        self.elapsedMs += deltaMs;
        const t = progress(self.elapsedMs, self.durationMs);
        self.target.* = easing.tween(self.ease, self.from.?, self.to, t);
        return Step.timed(self.elapsedMs, self.durationMs);
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *TweenValueStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }
};

/// Sets an f32 the game owns to `value`. Fire-and-forget; completes in zero
/// time. `target` must outlive the step.
pub const SetValueStep = struct {
    target: *f32,
    value: f32,

    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(alloc: std.mem.Allocator, target: *f32, value: f32) !Step {
        const ptr = try alloc.create(SetValueStep);
        ptr.* = .{ .target = target, .value = value };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *SetValueStep = @ptrCast(@alignCast(step.ptr));
        self.target.* = self.value;
        return .{ .finished = deltaMs };
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *SetValueStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }
};

/// Runs a whole sequence as a single step, finishing when the inner sequence
/// does. Mostly useful inside a `ParallelStep`, to run several multi-step
/// tracks side by side. The step owns the inner sequence.
pub const SubSequenceStep = struct {
    seq: Sequence,

    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(alloc: std.mem.Allocator, seq: Sequence) !Step {
        const ptr = try alloc.create(SubSequenceStep);
        ptr.* = .{ .seq = seq };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *SubSequenceStep = @ptrCast(@alignCast(step.ptr));
        return self.seq.advance(deltaMs);
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *SubSequenceStep = @ptrCast(@alignCast(step.ptr));
        self.seq.deinit(alloc);
        alloc.destroy(self);
    }
};

/// Calls a Lua function when reached. Fire-and-forget; completes in zero
/// time. The function is held in the Lua registry until the step is freed,
/// so the step must be freed before the Lua state is closed. A Lua error in
/// the function is logged and the sequence carries on.
pub const LuaCallStep = struct {
    lua: *Lua,
    funcRef: i32,

    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    /// Takes the function on top of `lua`'s stack (popping it).
    pub fn initFromStack(alloc: std.mem.Allocator, lua: *Lua) !Step {
        const funcRef = try lua.ref(ziglua.registry_index);
        errdefer lua.unref(ziglua.registry_index, funcRef);
        const ptr = try alloc.create(LuaCallStep);
        ptr.* = .{ .lua = lua, .funcRef = funcRef };
        return .{ .ptr = ptr, .vtable = &vtable };
    }

    pub fn update(step: *Step, deltaMs: f64) Step.Status {
        const self: *LuaCallStep = @ptrCast(@alignCast(step.ptr));
        _ = self.lua.rawGetIndex(ziglua.registry_index, self.funcRef);
        self.lua.protectedCall(.{ .args = 0, .results = 0, .msg_handler = 0 }) catch {
            std.log.err("seq_call: {s}", .{self.lua.toString(-1) catch "(non-string error)"});
            self.lua.pop(1);
        };
        return .{ .finished = deltaMs };
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *LuaCallStep = @ptrCast(@alignCast(step.ptr));
        self.lua.unref(ziglua.registry_index, self.funcRef);
        alloc.destroy(self);
    }
};

/// A linear set of steps, finished when it's iterated through all of the steps.
pub const Sequence = struct {
    steps: std.ArrayList(Step),
    alloc: std.mem.Allocator,
    currStep: usize,
    done: bool,
    /// Optional name for finding the sequence once it's playing (see
    /// `SequencePlayer.cancel` and `isRunning`). Empty when untagged.
    tagBuf: [MAX_NAME_LEN]u8 = undefined,
    tagLen: usize = 0,

    pub fn init(alloc: std.mem.Allocator) Sequence {
        return .{
            .steps = .empty,
            .alloc = alloc,
            .currStep = 0,
            .done = false,
        };
    }

    /// Names the sequence. Tags longer than `MAX_NAME_LEN` are rejected.
    pub fn setTag(self: *Sequence, name: []const u8) !void {
        if (name.len > MAX_NAME_LEN) return error.TagTooLong;
        @memcpy(self.tagBuf[0..name.len], name);
        self.tagLen = name.len;
    }

    /// The sequence's tag, empty when it has none.
    pub fn tag(self: *const Sequence) []const u8 {
        return self.tagBuf[0..self.tagLen];
    }

    /// Whether the sequence is tagged `name`. Never true for an empty name.
    pub fn hasTag(self: *const Sequence, name: []const u8) bool {
        return self.tagLen != 0 and std.mem.eql(u8, self.tag(), name);
    }

    pub fn deinit(self: *Sequence, alloc: std.mem.Allocator) void {
        for (self.steps.items) |*step| {
            step.deinit(alloc);
        }

        self.steps.deinit(alloc);
    }

    /// Appends `step`, which the sequence then owns.
    pub fn add(self: *Sequence, alloc: std.mem.Allocator, step: Step) !void {
        try self.steps.append(alloc, step);
    }

    /// Advances the sequence by `deltaMs` and returns whether it's finished.
    /// See `advance`.
    pub fn update(self: *Sequence, deltaMs: f64) bool {
        return switch (self.advance(deltaMs)) {
            .running => false,
            .finished => true,
        };
    }

    /// Advances the sequence by `deltaMs`. A step that finishes partway
    /// through hands what's left of the delta to the next one, so several
    /// steps can run in one call: zero-time steps (setting values, calling
    /// Lua) all run in the tick they're reached, and a wait doesn't round
    /// up to whole ticks. Reports `.finished` with the unused time once the
    /// last step is done (or the sequence was cancelled).
    pub fn advance(self: *Sequence, deltaMs: f64) Step.Status {
        if (self.done) return .{ .finished = deltaMs };

        var remainingMs = deltaMs;
        while (self.currStep < self.steps.items.len) {
            const step = &self.steps.items[self.currStep];
            switch (step.update(remainingMs)) {
                .running => return .running,
                .finished => |left| {
                    self.currStep += 1;
                    remainingMs = left;
                },
            }
            // A step's Lua call may have cancelled this sequence.
            if (self.done) return .{ .finished = remainingMs };
        }

        self.done = true;
        return .{ .finished = remainingMs };
    }
};

/// Manages a list of sequences and handles updating each sequence and cleaning
/// up finished ones. Games should have one global SequencePlayer that they
/// update every tick and add sequences to as needed.
///
/// A step may add, cancel or clear sequences from inside `update` (e.g. a
/// `LuaCallStep` whose script calls `seq_play` or `seq_cancel`). Sequences
/// added then start on the next update; cancelled ones stop right away.
pub const SequencePlayer = struct {
    alloc: std.mem.Allocator,
    sequences: std.ArrayList(Sequence),
    /// Sequences added while `update` was running, moved into `sequences`
    /// once it's done so that list never grows mid-iteration.
    incoming: std.ArrayList(Sequence) = .empty,
    updating: bool = false,

    pub fn init(alloc: std.mem.Allocator) SequencePlayer {
        return .{
            .alloc = alloc,
            .sequences = .empty,
        };
    }

    pub fn deinit(self: *SequencePlayer) void {
        for (self.sequences.items) |*seq| {
            seq.deinit(self.alloc);
        }
        self.sequences.deinit(self.alloc);
        for (self.incoming.items) |*seq| {
            seq.deinit(self.alloc);
        }
        self.incoming.deinit(self.alloc);
    }

    /// Takes ownership of `seq` and starts playing it.
    pub fn add(self: *SequencePlayer, seq: Sequence) !void {
        if (self.updating) {
            try self.incoming.append(self.alloc, seq);
        } else {
            try self.sequences.append(self.alloc, seq);
        }
    }

    /// Like `add`, but tags the sequence first so it can be found with
    /// `isRunning` or stopped with `cancel`. On error the sequence is freed.
    pub fn addTagged(self: *SequencePlayer, seq: Sequence, tag: []const u8) !void {
        var tagged = seq;
        errdefer tagged.deinit(self.alloc);
        try tagged.setTag(tag);
        try self.add(tagged);
    }

    /// Whether any unfinished sequence is tagged `tag`.
    pub fn isRunning(self: *const SequencePlayer, tag: []const u8) bool {
        for (self.sequences.items) |*seq| {
            if (!seq.done and seq.hasTag(tag)) return true;
        }
        for (self.incoming.items) |*seq| {
            if (!seq.done and seq.hasTag(tag)) return true;
        }
        return false;
    }

    /// Stops every sequence tagged `tag` without running its remaining
    /// steps, and returns how many were stopped.
    pub fn cancel(self: *SequencePlayer, tag: []const u8) usize {
        var count: usize = 0;
        for (self.sequences.items) |*seq| {
            if (!seq.done and seq.hasTag(tag)) {
                seq.done = true;
                count += 1;
            }
        }
        for (self.incoming.items) |*seq| {
            if (!seq.done and seq.hasTag(tag)) {
                seq.done = true;
                count += 1;
            }
        }
        if (!self.updating) self.removeFinished();
        return count;
    }

    /// Stops every sequence.
    pub fn clear(self: *SequencePlayer) void {
        for (self.sequences.items) |*seq| seq.done = true;
        for (self.incoming.items) |*seq| seq.done = true;
        if (!self.updating) self.removeFinished();
    }

    /// Update all sequences, and remove any that finished this tick
    /// calling deinit on each finished sequence to free its memory.
    pub fn update(self: *SequencePlayer, deltaMs: f64) void {
        self.updating = true;
        // Indexed rather than iterated by pointer: nothing may resize
        // `sequences` while updating, but this keeps that obvious.
        var i: usize = 0;
        while (i < self.sequences.items.len) : (i += 1) {
            const seq = &self.sequences.items[i];
            if (seq.done) continue;
            if (seq.update(deltaMs)) seq.done = true;
        }
        self.updating = false;

        self.removeFinished();
        self.sequences.appendSlice(self.alloc, self.incoming.items) catch |err| {
            std.log.err("SequencePlayer: dropping {} sequence(s) added during update: {}", .{ self.incoming.items.len, err });
            for (self.incoming.items) |*seq| seq.deinit(self.alloc);
        };
        self.incoming.clearRetainingCapacity();
    }

    /// Frees and drops every finished (or cancelled) sequence.
    fn removeFinished(self: *SequencePlayer) void {
        removeFinishedFrom(self.alloc, &self.sequences);
        removeFinishedFrom(self.alloc, &self.incoming);
    }

    fn removeFinishedFrom(alloc: std.mem.Allocator, list: *std.ArrayList(Sequence)) void {
        var i: usize = 0;
        while (i < list.items.len) {
            if (list.items[i].done) {
                list.items[i].deinit(alloc);
                _ = list.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
};


// ----------------------------------------------------------------------------
// Lua scripting bridge
// ----------------------------------------------------------------------------

/// Bridges Lua scripting with the sequence system. Bind it to a script engine
/// via bindToLua(), then Lua scripts can build sequences step by step
/// (seq_new, seq_wait, seq_move_to, seq_tween, ...), play them, and stop
/// them by tag. Games expose their own state to those scripts as named f32
/// values (see `registerValue`).
///
/// A bad argument (wrong type, a handle that isn't a pending sequence, an
/// unknown value or ease name) raises a Lua error naming the function and
/// argument, like Lua's own library functions do, so the script stops at the
/// mistake and the error is logged with its file and line.
pub const SeqScriptingContext = struct {
    alloc: std.mem.Allocator,
    world: *flecs.world_t,
    player: *SequencePlayer,
    /// In-progress sequences, indexed by the handle `seq_new` returned. A slot
    /// goes back to null once `seq_play` submits it, and is reused.
    pending: std.ArrayList(?Sequence),
    /// Game-owned f32s scripts can read, set and tween by name.
    values: std.StringHashMapUnmanaged(*f32) = .empty,

    pub fn init(
        alloc: std.mem.Allocator,
        world: *flecs.world_t,
        player: *SequencePlayer,
    ) SeqScriptingContext {
        return .{
            .alloc = alloc,
            .world = world,
            .player = player,
            .pending = .empty,
        };
    }

    pub fn deinit(self: *SeqScriptingContext) void {
        for (self.pending.items) |*slot| {
            if (slot.*) |*s| s.deinit(self.alloc);
        }
        self.pending.deinit(self.alloc);
        var it = self.values.keyIterator();
        while (it.next()) |key| self.alloc.free(key.*);
        self.values.deinit(self.alloc);
    }

    /// Register seq_* and value_* globals into the script engine's Lua state.
    /// The context must remain valid while Lua can call the registered
    /// functions.
    pub fn bindToLua(self: *SeqScriptingContext, script: *ScriptEngine) !void {
        try script.registerMethod(SeqScriptingContext, self, "seq_new", luaSeqNew);
        try script.registerMethod(SeqScriptingContext, self, "seq_wait", luaSeqWait);
        try script.registerMethod(SeqScriptingContext, self, "seq_move_to", luaSeqMoveTo);
        try script.registerMethod(SeqScriptingContext, self, "seq_set_actor_state", luaSeqSetActorState);
        try script.registerMethod(SeqScriptingContext, self, "seq_tween", luaSeqTween);
        try script.registerMethod(SeqScriptingContext, self, "seq_set", luaSeqSet);
        try script.registerMethod(SeqScriptingContext, self, "seq_call", luaSeqCall);
        try script.registerMethod(SeqScriptingContext, self, "seq_parallel", luaSeqParallel);
        try script.registerMethod(SeqScriptingContext, self, "seq_play", luaSeqPlay);
        try script.registerMethod(SeqScriptingContext, self, "seq_cancel", luaSeqCancel);
        try script.registerMethod(SeqScriptingContext, self, "seq_running", luaSeqRunning);
        try script.registerMethod(SeqScriptingContext, self, "value_get", luaValueGet);
        try script.registerMethod(SeqScriptingContext, self, "value_set", luaValueSet);
    }

    /// Exposes `ptr` to scripts as the value `name`, for value_get /
    /// value_set / seq_tween / seq_set. `ptr` must outlive the context and
    /// any sequence that tweens it. Registering a name again repoints it.
    pub fn registerValue(self: *SeqScriptingContext, name: []const u8, ptr: *f32) !void {
        if (self.values.getPtr(name)) |existing| {
            existing.* = ptr;
            return;
        }
        const key = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(key);
        try self.values.put(self.alloc, key, ptr);
    }

    /// The pending sequence for a Lua handle, or null if it's out of range or
    /// already played.
    fn pendingSeq(self: *SeqScriptingContext, handle: ziglua.Integer) ?*Sequence {
        if (handle < 0 or handle >= self.pending.items.len) return null;
        const slot = &self.pending.items[@intCast(handle)];
        return if (slot.*) |*s| s else null;
    }

    /// Takes the pending sequence for a Lua handle out of its slot, freeing
    /// the slot. Null if the handle is out of range or already played.
    fn takePending(self: *SeqScriptingContext, handle: ziglua.Integer) ?Sequence {
        const s = self.pendingSeq(handle) orelse return null;
        const taken = s.*;
        self.pending.items[@intCast(handle)] = null;
        return taken;
    }
};

// --- Argument helpers ---------------------------------------------------------
//
// These raise a Lua error on a bad argument. A Lua error longjmps out of the
// binding, skipping any Zig `defer`, so each binding reads and checks all of
// its arguments before it allocates anything, and frees what it holds before
// raising an out-of-memory error.

const not_pending_msg = "not a pending sequence (make one with seq_new; seq_play and seq_parallel use it up)";

/// The handle at stack index `arg`, which must name a pending sequence.
fn pendingHandleArg(ctx: *SeqScriptingContext, lua: *Lua, arg: i32) ziglua.Integer {
    const handle = lua.checkInteger(arg);
    if (ctx.pendingSeq(handle) == null) lua.argError(arg, not_pending_msg);
    return handle;
}

/// The pending sequence named by the handle at stack index `arg`.
fn pendingArg(ctx: *SeqScriptingContext, lua: *Lua, arg: i32) *Sequence {
    return ctx.pendingSeq(pendingHandleArg(ctx, lua, arg)).?;
}

/// The registered value named by the string at stack index `arg`.
fn valueArg(ctx: *SeqScriptingContext, lua: *Lua, arg: i32) *f32 {
    const name = lua.checkString(arg);
    return ctx.values.get(name) orelse
        lua.argError(arg, lua.pushFString("no value named '%s' (see SeqScriptingContext.registerValue)", .{name.ptr}));
}

/// The flecs entity id at stack index `arg`.
fn entityArg(lua: *Lua, arg: i32) flecs.entity_t {
    const id = lua.checkInteger(arg);
    if (id < 0) lua.argError(arg, "entity id can't be negative");
    return @intCast(id);
}

/// The optional `Ease` name at stack index `arg`, linear when absent or nil.
fn easeArg(lua: *Lua, arg: i32) Ease {
    const name = lua.optString(arg) orelse return .linear;
    return std.meta.stringToEnum(Ease, name) orelse
        lua.argError(arg, lua.pushFString("unknown ease '%s'", .{name.ptr}));
}

/// Raises a Lua error for an allocation (or other non-argument) failure.
fn raiseFailure(lua: *Lua, comptime func: [:0]const u8, err: anyerror) noreturn {
    lua.raiseErrorStr(func ++ ": %s", .{@errorName(err).ptr});
}

/// Appends a freshly made step to `s`, freeing it and raising a Lua error if
/// making or appending it failed.
fn appendStep(
    ctx: *SeqScriptingContext,
    lua: *Lua,
    s: *Sequence,
    comptime func: [:0]const u8,
    made: anyerror!Step,
) void {
    var step = made catch |err| raiseFailure(lua, func, err);
    s.add(ctx.alloc, step) catch |err| {
        step.deinit(ctx.alloc);
        raiseFailure(lua, func, err);
    };
}

// --- Lua function implementations --------------------------------------------

/// seq_new() -> handle: allocate a new pending sequence slot.
fn luaSeqNew(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    for (ctx.pending.items, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = Sequence.init(ctx.alloc);
            lua.pushInteger(@intCast(i));
            return 1;
        }
    }
    ctx.pending.append(ctx.alloc, Sequence.init(ctx.alloc)) catch |err| raiseFailure(lua, "seq_new", err);
    lua.pushInteger(@intCast(ctx.pending.items.len - 1));
    return 1;
}

/// seq_wait(handle, ms): append a WaitStep to the pending sequence.
fn luaSeqWait(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const s = pendingArg(ctx, lua, 1);
    const ms = lua.checkNumber(2);
    appendStep(ctx, lua, s, "seq_wait", WaitStep.init(ctx.alloc, ms));
    return 0;
}

/// seq_move_to(handle, entity_id, x, y, ms [, ease]): append a MoveToStep.
/// `ease` is an `Ease` name such as "quad_out"; omitted, the move is linear.
fn luaSeqMoveTo(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const s = pendingArg(ctx, lua, 1);
    const entityId = entityArg(lua, 2);
    const x: f32 = @floatCast(lua.checkNumber(3));
    const y: f32 = @floatCast(lua.checkNumber(4));
    const ms = lua.checkNumber(5);
    const ease = easeArg(lua, 6);
    appendStep(ctx, lua, s, "seq_move_to", MoveToStep.initEased(ctx.alloc, ctx.world, entityId, .{ .x = x, .y = y }, ms, ease));
    return 0;
}

/// seq_tween(handle, name, to, ms [, ease]): append a TweenValueStep that
/// eases the value `name` from wherever it is when the step starts to `to`.
fn luaSeqTween(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const s = pendingArg(ctx, lua, 1);
    const target = valueArg(ctx, lua, 2);
    const to: f32 = @floatCast(lua.checkNumber(3));
    const ms = lua.checkNumber(4);
    const ease = easeArg(lua, 5);
    appendStep(ctx, lua, s, "seq_tween", TweenValueStep.init(ctx.alloc, target, to, ms, ease));
    return 0;
}

/// seq_set(handle, name, value): append a SetValueStep.
fn luaSeqSet(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const s = pendingArg(ctx, lua, 1);
    const target = valueArg(ctx, lua, 2);
    const value: f32 = @floatCast(lua.checkNumber(3));
    appendStep(ctx, lua, s, "seq_set", SetValueStep.init(ctx.alloc, target, value));
    return 0;
}

/// seq_call(handle, fn): append a LuaCallStep that calls `fn` (no
/// arguments) when the sequence reaches it.
fn luaSeqCall(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const s = pendingArg(ctx, lua, 1);
    lua.checkType(2, .function);
    lua.pushValue(2);
    appendStep(ctx, lua, s, "seq_call", LuaCallStep.initFromStack(ctx.alloc, lua));
    return 0;
}

/// seq_set_actor_state(handle, entity_id, state_name): append a
/// SetActorStateStep.
fn luaSeqSetActorState(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const s = pendingArg(ctx, lua, 1);
    const entityId = entityArg(lua, 2);
    const stateName = lua.checkString(3);
    appendStep(ctx, lua, s, "seq_set_actor_state", SetActorStateStep.init(ctx.alloc, ctx.world, entityId, stateName));
    return 0;
}

/// seq_parallel(handle, h1, h2, ...): append a ParallelStep that runs the
/// pending sequences h1, h2, ... side by side, finishing when all of them
/// have. Those handles are used up, like seq_play.
fn luaSeqParallel(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const handle = pendingHandleArg(ctx, lua, 1);
    const top = lua.getTop();

    // Check every track before taking any, so a bad one leaves them all
    // pending.
    var arg: i32 = 2;
    while (arg <= top) : (arg += 1) {
        const sub = pendingHandleArg(ctx, lua, arg);
        if (sub == handle) lua.argError(arg, "a sequence can't run inside itself");
        var earlier: i32 = 2;
        while (earlier < arg) : (earlier += 1) {
            if (lua.checkInteger(earlier) == sub) lua.argError(arg, "the same sequence is passed twice");
        }
    }

    var par = ParallelStep.init(ctx.alloc) catch |err| raiseFailure(lua, "seq_parallel", err);
    arg = 2;
    while (arg <= top) : (arg += 1) {
        var track = ctx.takePending(lua.checkInteger(arg)).?;
        var step = SubSequenceStep.init(ctx.alloc, track) catch |err| {
            track.deinit(ctx.alloc);
            par.deinit(ctx.alloc);
            raiseFailure(lua, "seq_parallel", err);
        };
        ParallelStep.add(&par, ctx.alloc, step) catch |err| {
            step.deinit(ctx.alloc);
            par.deinit(ctx.alloc);
            raiseFailure(lua, "seq_parallel", err);
        };
    }

    appendStep(ctx, lua, ctx.pendingSeq(handle).?, "seq_parallel", par);
    return 0;
}

/// seq_play(handle [, tag]): submit the sequence to the SequencePlayer and
/// free the slot. A `tag` lets seq_running / seq_cancel find it later.
fn luaSeqPlay(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const handle = pendingHandleArg(ctx, lua, 1);
    const tag = lua.optString(2);
    if (tag) |t| {
        if (t.len > MAX_NAME_LEN) {
            lua.argError(2, std.fmt.comptimePrint("tag is longer than {d} bytes", .{MAX_NAME_LEN}));
        }
    }

    var s = ctx.takePending(handle).?;
    if (tag) |t| {
        // addTagged frees the sequence when it fails.
        ctx.player.addTagged(s, t) catch |err| raiseFailure(lua, "seq_play", err);
    } else {
        ctx.player.add(s) catch |err| {
            s.deinit(ctx.alloc);
            raiseFailure(lua, "seq_play", err);
        };
    }
    return 0;
}

/// seq_cancel(tag) -> count: stop every playing sequence tagged `tag`.
fn luaSeqCancel(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const tag = lua.checkString(1);
    lua.pushInteger(@intCast(ctx.player.cancel(tag)));
    return 1;
}

/// seq_running(tag) -> boolean: whether a sequence tagged `tag` is playing.
fn luaSeqRunning(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const tag = lua.checkString(1);
    lua.pushBoolean(ctx.player.isRunning(tag));
    return 1;
}

/// value_get(name) -> number: the current value `name`.
fn luaValueGet(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    lua.pushNumber(valueArg(ctx, lua, 1).*);
    return 1;
}

/// value_set(name, value): set the value `name` right away.
fn luaValueSet(ctx: *SeqScriptingContext, lua: *Lua) i32 {
    const target = valueArg(ctx, lua, 1);
    target.* = @floatCast(lua.checkNumber(2));
    return 0;
}
