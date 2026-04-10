// A simple action sequencer for coordinating timed game events.
// sequencer.zig — Action sequencer for coordinating timed game events.
//
// A Sequence is a root Track. A Track is a sequential list of Steps. A Step
// can be a timed wait, a fire-and-forget screen flash, an actor-state change,
// a move-to, a spawn-effect, or a Parallel that holds multiple sub-Tracks
// running concurrently.

const std = @import("std");
const common = @import("./common.zig");
const sprites = @import("./renderer/sprites.zig");
const flecs = @import("zflecs");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Vec2F = common.Vec2F;
const Color = common.Color;
const Sprite = sprites.Sprite;
const Actor = sprites.Actor;

pub const MAX_NAME_LEN = 64;

pub const Step = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    done: bool = false,

    pub const VTable = struct {
        /// Return time left, and a negative when the step is finished.
        update: *const fn (step: *Step, deltaMs: f64) f64,
        /// Free any heap memory owned by the step.
        deinit: *const fn (step: *Step, alloc: std.mem.Allocator) void,
    };
};

pub const WaitStep = struct {
    timeLeft: f64,
    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(alloc: std.mem.Allocator, durationMs: f64) !Step {
        const ptr = try alloc.create(WaitStep);
        ptr.* = WaitStep{ .timeLeft = durationMs };
        return .{
            .ptr = ptr,
            .vtable = &vtable,
            .done = false,
        };
    }

    pub fn update(step: *Step, deltaMs: f64) f64 {
        const self: *WaitStep = @ptrCast(@alignCast(step.ptr));
        self.timeLeft -= deltaMs;
        step.done = self.timeLeft <= 0;
        return self.timeLeft;
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *WaitStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }
};

pub const ParallelStep = struct {
    subSteps: std.ArrayList(Step),
    const vtable: Step.VTable = .{
        .update = update,
        .deinit = deinit,
    };

    pub fn init(alloc: std.mem.Allocator) !Step {
        const ptr = try alloc.create(ParallelStep);
        ptr.* = ParallelStep{
            .subSteps = std.ArrayList(Step).init(alloc),
        };
        return .{
            .ptr = ptr,
            .vtable = &vtable,
            .done = false,
        };
    }

    pub fn add(step: *Step, alloc: std.mem.Allocator, subStep: Step) !void {
        const self: *ParallelStep = @ptrCast(@alignCast(step.ptr));
        try self.subSteps.append(alloc, subStep);
    }

    pub fn update(step: *Step, deltaMs: f64) f64 {
        if (step.done) return 0.0;

        var minTimeLeft: f64 = std.math.floatMax(f64);
        var maxTimeLeft: f64 = 0.0;
        const self: *ParallelStep = @ptrCast(@alignCast(step.ptr));
        for (self.subSteps.items) |*subStep| {
            const currStepTimeLeft = subStep.vtable.update(subStep, deltaMs);
            if (currStepTimeLeft < minTimeLeft) {
                minTimeLeft = currStepTimeLeft;
            }
            if (currStepTimeLeft > maxTimeLeft) {
                maxTimeLeft = currStepTimeLeft;
            }
        }

        for (self.subSteps.items) |subStep| {
            if (!subStep.done) return maxTimeLeft;
        }

        step.done = true;
        return minTimeLeft;
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *ParallelStep = @ptrCast(@alignCast(step.ptr));
        for (self.subSteps.items) |*subStep| {
            subStep.vtable.deinit(subStep, alloc);
        }
        self.subSteps.deinit(alloc);
        alloc.destroy(self);
    }
};

// ----------------------------------------------------------------------------
/// Lerps a Sprite's position from its location on first tick to `target`
/// over `durationMs`. Captures start position lazily on the first update call.
pub const MoveToStep = struct {
    world: *flecs.world_t,
    entityId: flecs.entity_t,
    target: Vec2F,
    durationMs: f64,
    elapsedMs: f64,
    startPos: ?Vec2F,

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
        const ptr = try alloc.create(MoveToStep);
        ptr.* = .{
            .world = world,
            .entityId = entityId,
            .target = target,
            .durationMs = durationMs,
            .elapsedMs = 0,
            .startPos = null,
        };
        return .{ .ptr = ptr, .vtable = &vtable, .done = false };
    }

    pub fn update(step: *Step, deltaMs: f64) f64 {
        const self: *MoveToStep = @ptrCast(@alignCast(step.ptr));
        const spr = flecs.get_mut(self.world, self.entityId, Sprite) orelse {
            step.done = true;
            return -1.0;
        };

        // Lazy-capture start position on the first tick.
        if (self.startPos == null) {
            self.startPos = .{ .x = spr.dest.l, .y = spr.dest.t };
        }

        self.elapsedMs += deltaMs;
        const t: f32 = @floatCast(@min(self.elapsedMs / self.durationMs, 1.0));
        const start = self.startPos.?;
        const x = start.x + t * (self.target.x - start.x);
        const y = start.y + t * (self.target.y - start.y);
        spr.setPos(@intFromFloat(x), @intFromFloat(y));
        flecs.modified(self.world, self.entityId, Sprite);

        const timeLeft = self.durationMs - self.elapsedMs;
        step.done = timeLeft <= 0;
        return timeLeft;
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *MoveToStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }
};

// ----------------------------------------------------------------------------
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
        ptr.* = .{
            .world = world,
            .entityId = entityId,
            .stateName = try alloc.dupe(u8, stateName),
        };
        return .{ .ptr = ptr, .vtable = &vtable, .done = false };
    }

    pub fn update(step: *Step, deltaMs: f64) f64 {
        _ = deltaMs;
        const self: *SetActorStateStep = @ptrCast(@alignCast(step.ptr));
        if (flecs.get_mut(self.world, self.entityId, Actor)) |actor| {
            actor.setState(self.stateName);
            flecs.modified(self.world, self.entityId, Actor);
        }
        step.done = true;
        return -1.0;
    }

    pub fn deinit(step: *Step, alloc: std.mem.Allocator) void {
        const self: *SetActorStateStep = @ptrCast(@alignCast(step.ptr));
        alloc.free(self.stateName);
        alloc.destroy(self);
    }
};

//     pub fn deinitResources(self: *Step, alloc: std.mem.Allocator) void {
//         switch (self.*) {
//             .parallel => |*p| p.deinit(alloc),
//             else => {},
//         }
//     }

//     pub const WaitStep = struct {
//         durationMs: f64,
//     };

//     pub const ScreenFlashStep = struct {
//         color: Color,
//         durationMs: f64,
//     };

//     pub const SetActorStateStep = struct {
//         entityId: u64,
//         stateName: [MAX_NAME_LEN]u8,
//         stateNameLen: usize,
//     };

//     pub const MoveToStep = struct {
//         entityId: u64,
//         target: Vec2F,
//         durationMs: f64,
//     };

//     pub const SpawnEffectStep = struct {
//         pos: Vec2F,
//         spriteName: [MAX_NAME_LEN]u8,
//         spriteNameLen: usize,
//         durationMs: f64,
//     };

//     /// ParallelStep holds heap-allocated sub-Tracks it owns completely.
//     /// The pointer indirection (*Track) breaks the Step→Track→Step size cycle.
//     pub const ParallelStep = struct {
//         tracks: std.ArrayList(*Track),

//         pub fn deinit(self: *ParallelStep, alloc: std.mem.Allocator) void {
//             for (self.tracks.items) |track| {
//                 track.deinit(alloc);
//                 alloc.destroy(track);
//             }
//             self.tracks.deinit(alloc);
//         }
//     };
// };

// ----------------------------------------------------------------------------
// A linear set of steps, finished when it's iterated through all of the steps.
pub const Sequence = struct {
    steps: std.ArrayList(Step),
    alloc: std.mem.Allocator,
    currStep: usize,
    done: bool,

    pub fn init(alloc: std.mem.Allocator) Sequence {
        return .{
            .steps = .{},
            .alloc = alloc,
            .currStep = 0,
            .done = false,
        };
    }

    pub fn deinit(self: *Sequence, alloc: std.mem.Allocator) void {
        for (self.steps.items) |*step| {
            step.vtable.deinit(step, alloc);
        }

        self.steps.deinit(alloc);
    }

    pub fn add(self: *Sequence, alloc: std.mem.Allocator, step: Step) !void {
        try self.steps.append(alloc, step);
    }

    pub fn update(self: *Sequence, deltaMs: f64) bool {
        if (self.done) return true;

        if (self.steps.items.len == 0) {
            self.done = true;
            return true;
        }

        // TODO: change to a while loop that advances through multiple steps if deltaMs is large enough.
        const step = &self.steps.items[self.currStep];
        const timeLeft = step.vtable.update(step, deltaMs);
        if (timeLeft <= 0) {
            self.currStep += 1;
        }

        if (self.currStep >= self.steps.items.len) {
            self.done = true;
            return true;
        }
        return false;
    }
};

// ----------------------------------------------------------------------------
/// Returned from SequencePlayer.getFlashState() so ffme.zig can render it.
// pub const FlashState = struct {
//     color: Color,
//     active: bool,
// };

// ----------------------------------------------------------------------------
pub const SequencePlayer = struct {
    alloc: std.mem.Allocator,
    sequences: std.ArrayList(Sequence),

    pub fn init(alloc: std.mem.Allocator) SequencePlayer {
        return .{
            .alloc = alloc,
            .sequences = .{},
        };
    }

    pub fn deinit(self: *SequencePlayer) void {
        for (self.sequences.items) |*seq| {
            seq.deinit(self.alloc);
        }
        self.sequences.deinit(self.alloc);
    }

    /// Create a new sequence and return its handle.
    pub fn add(self: *SequencePlayer, seq: Sequence) !void {
        try self.sequences.append(self.alloc, seq);
    }

    pub fn update(self: *SequencePlayer, deltaMs: f64) void {
        var seqFinished = false;
        for (self.sequences.items) |*seq| {
            //if (!seq.active or seq.done) continue;
            const done = seq.update(deltaMs);
            if (done) {
                seqFinished = true;
                seq.done = true;
            }
        }

        // If a sequence finished this tick, do a cleanup pass.
        if (seqFinished) {
            var i: usize = 0;
            while (i < self.sequences.items.len) {
                if (self.sequences.items[i].done) {
                    self.sequences.items[i].deinit(self.alloc);
                    _ = self.sequences.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    // fn seqTrack(self: *SequencePlayer, handle: SeqHandle) *Track {

    //     return &self.sequences.items[handle].track;
    // }

    // pub fn addWait(self: *SequencePlayer, handle: SeqHandle, ms: f64) !void {
    //     try self.seqTrack(handle).addStep(self.alloc, .{ .wait = .{ .durationMs = ms } });
    // }

    // pub fn addScreenFlash(self: *SequencePlayer, handle: SeqHandle, color: Color, durationMs: f64) !void {
    //     try self.seqTrack(handle).addStep(self.alloc, .{
    //         .screen_flash = .{ .color = color, .durationMs = durationMs },
    //     });
    // }

    // pub fn addSetActorState(self: *SequencePlayer, handle: SeqHandle, entityId: u64, stateName: []const u8) !void {
    //     var nameArr = [_]u8{0} ** MAX_NAME_LEN;
    //     const copyLen = @min(stateName.len, MAX_NAME_LEN);
    //     @memcpy(nameArr[0..copyLen], stateName[0..copyLen]);
    //     try self.seqTrack(handle).addStep(self.alloc, .{ .set_actor_state = .{
    //         .entityId = entityId,
    //         .stateName = nameArr,
    //         .stateNameLen = copyLen,
    //     } });
    // }

    // pub fn addMoveTo(self: *SequencePlayer, handle: SeqHandle, entityId: u64, target: Vec2F, durationMs: f64) !void {
    //     try self.seqTrack(handle).addStep(self.alloc, .{ .move_to = .{
    //         .entityId = entityId,
    //         .target = target,
    //         .durationMs = durationMs,
    //     } });
    // }

    // pub fn addSpawnEffect(self: *SequencePlayer, handle: SeqHandle, spriteName: []const u8, pos: Vec2F, durationMs: f64) !void {
    //     var nameArr = [_]u8{0} ** MAX_NAME_LEN;
    //     const copyLen = @min(spriteName.len, MAX_NAME_LEN);
    //     @memcpy(nameArr[0..copyLen], spriteName[0..copyLen]);
    //     try self.seqTrack(handle).addStep(self.alloc, .{ .spawn_effect = .{
    //         .pos = pos,
    //         .spriteName = nameArr,
    //         .spriteNameLen = copyLen,
    //         .durationMs = durationMs,
    //     } });
    // }

    // /// Add a parallel step that runs trackPtrs concurrently.
    // /// Ownership of the Track objects transfers to the parallel step.
    // pub fn addParallel(self: *SequencePlayer, handle: SeqHandle, trackPtrs: []*Track) !void {
    //     var par: Step.ParallelStep = .{ .tracks = .{} };
    //     for (trackPtrs) |t| {
    //         try par.tracks.append(self.alloc, t);
    //     }
    //     try self.seqTrack(handle).addStep(self.alloc, .{ .parallel = par });
    // }

    // /// Start playback of a sequence. Resets done flag so it can be replayed.
    // pub fn playSequence(self: *SequencePlayer, handle: SeqHandle) void {
    //     self.sequences.items[handle].active = true;
    //     self.sequences.items[handle].done = false;
    // }

    // pub fn update(self: *SequencePlayer, deltaMs: f64) void {
    //     // Tick the screen flash independently of sequences.
    //     if (self.flashActive) {
    //         self.flashRemainingMs -= deltaMs;
    //         if (self.flashRemainingMs <= 0) {
    //             self.flashActive = false;
    //         }
    //     }

    //     for (self.sequences.items) |*seq| {
    //         if (!seq.active or seq.done) continue;
    //         updateTrack(self, &seq.track, deltaMs);
    //         if (seq.track.done) {
    //             seq.active = false;
    //             seq.done = true;
    //         }
    //     }
    // }

    // /// Returns a FlashState for rendering. Alpha fades linearly over the flash duration.
    // pub fn getFlashState(self: *const SequencePlayer) FlashState {
    //     if (!self.flashActive) {
    //         return .{ .color = .{ .r = 0, .g = 0, .b = 0, .a = 0 }, .active = false };
    //     }
    //     const progress: f32 = @floatCast(self.flashRemainingMs / self.flashTotalMs);
    //     var color = self.flashColor;
    //     color.a *= progress;
    //     return .{ .color = color, .active = true };
    // }
};

// ----------------------------------------------------------------------------
// Lua scripting bridge
// ----------------------------------------------------------------------------

/// Maximum number of in-progress sequences buildable from Lua at once.
const MAX_PENDING_SEQS: usize = 16;

/// Active scripting context. Set by SeqScriptingContext.bindToLua().
var g_seqCtx: ?*SeqScriptingContext = null;

/// Bridges Lua scripting with the sequence system. Bind it to a Lua state via
/// bindToLua(), then Lua scripts can call seq_new / seq_wait / seq_move_to /
/// seq_set_actor_state / seq_play to build and queue sequences.
pub const SeqScriptingContext = struct {
    alloc: std.mem.Allocator,
    world: *flecs.world_t,
    player: *SequencePlayer,
    pending: [MAX_PENDING_SEQS]?Sequence,

    pub fn init(
        alloc: std.mem.Allocator,
        world: *flecs.world_t,
        player: *SequencePlayer,
    ) SeqScriptingContext {
        return .{
            .alloc = alloc,
            .world = world,
            .player = player,
            .pending = [_]?Sequence{null} ** MAX_PENDING_SEQS,
        };
    }

    pub fn deinit(self: *SeqScriptingContext) void {
        for (&self.pending) |*slot| {
            if (slot.*) |*s| s.deinit(self.alloc);
            slot.* = null;
        }
        if (g_seqCtx == self) g_seqCtx = null;
    }

    /// Register seq_* globals into the Lua state and set this as active context.
    pub fn bindToLua(self: *SeqScriptingContext, lua: *Lua) void {
        g_seqCtx = self;
        lua.pushFunction(ziglua.wrap(luaSeqNew));
        lua.setGlobal("seq_new");
        lua.pushFunction(ziglua.wrap(luaSeqWait));
        lua.setGlobal("seq_wait");
        lua.pushFunction(ziglua.wrap(luaSeqMoveTo));
        lua.setGlobal("seq_move_to");
        lua.pushFunction(ziglua.wrap(luaSeqSetActorState));
        lua.setGlobal("seq_set_actor_state");
        lua.pushFunction(ziglua.wrap(luaSeqPlay));
        lua.setGlobal("seq_play");
    }
};

// --- Lua C function implementations -----------------------------------------

/// seq_new() -> handle:integer  — allocate a new pending sequence slot.
fn luaSeqNew(lua: *Lua) i32 {
    const ctx = g_seqCtx orelse {
        lua.pushInteger(-1);
        return 1;
    };
    for (&ctx.pending, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = Sequence.init(ctx.alloc);
            lua.pushInteger(@intCast(i));
            return 1;
        }
    }
    lua.pushInteger(-1); // no free slot
    return 1;
}

/// seq_wait(handle, ms) — append a WaitStep to the pending sequence.
fn luaSeqWait(lua: *Lua) i32 {
    const ctx = g_seqCtx orelse return 0;
    const handle = lua.toInteger(1) catch return 0;
    const ms = lua.toNumber(2) catch return 0;
    if (handle < 0 or handle >= @as(ziglua.Integer, MAX_PENDING_SEQS)) return 0;
    const uhandle: usize = @intCast(handle);
    if (ctx.pending[uhandle] != null) {
        const s = &ctx.pending[uhandle].?;
        s.add(ctx.alloc, WaitStep.init(ctx.alloc, ms) catch return 0) catch {};
    }
    return 0;
}

/// seq_move_to(handle, entity_id, x, y, ms) — append a MoveToStep.
fn luaSeqMoveTo(lua: *Lua) i32 {
    const ctx = g_seqCtx orelse return 0;
    const handle = lua.toInteger(1) catch return 0;
    const entityId: flecs.entity_t = @intCast(lua.toInteger(2) catch return 0);
    const x: f32 = @floatCast(lua.toNumber(3) catch return 0);
    const y: f32 = @floatCast(lua.toNumber(4) catch return 0);
    const ms = lua.toNumber(5) catch return 0;
    if (handle < 0 or handle >= @as(ziglua.Integer, MAX_PENDING_SEQS)) return 0;
    const uhandle: usize = @intCast(handle);
    if (ctx.pending[uhandle] != null) {
        const s = &ctx.pending[uhandle].?;
        s.add(ctx.alloc, MoveToStep.init(ctx.alloc, ctx.world, entityId, .{ .x = x, .y = y }, ms) catch return 0) catch {};
    }
    return 0;
}

/// seq_set_actor_state(handle, entity_id, state_name) — append a SetActorStateStep.
fn luaSeqSetActorState(lua: *Lua) i32 {
    const ctx = g_seqCtx orelse return 0;
    const handle = lua.toInteger(1) catch return 0;
    const entityId: flecs.entity_t = @intCast(lua.toInteger(2) catch return 0);
    const stateName = lua.toString(3) catch return 0;
    if (handle < 0 or handle >= @as(ziglua.Integer, MAX_PENDING_SEQS)) return 0;
    const uhandle: usize = @intCast(handle);
    if (ctx.pending[uhandle] != null) {
        const s = &ctx.pending[uhandle].?;
        s.add(ctx.alloc, SetActorStateStep.init(ctx.alloc, ctx.world, entityId, stateName) catch return 0) catch {};
    }
    return 0;
}

/// seq_play(handle) — submit the sequence to the SequencePlayer and free the slot.
fn luaSeqPlay(lua: *Lua) i32 {
    const ctx = g_seqCtx orelse return 0;
    const handle = lua.toInteger(1) catch return 0;
    if (handle < 0 or handle >= @as(ziglua.Integer, MAX_PENDING_SEQS)) return 0;
    const uhandle: usize = @intCast(handle);
    if (ctx.pending[uhandle]) |seq_val| {
        ctx.player.add(seq_val) catch {};
        ctx.pending[uhandle] = null;
    }
    return 0;
}

// // ----------------------------------------------------------------------------
// fn updateTrack(player: *SequencePlayer, track: *Track, deltaMs: f64) void {
//     if (track.done) return;

//     track.stepElapsedMs += deltaMs;

//     while (track.currStep < track.steps.items.len) {
//         const step = &track.steps.items[track.currStep];
//         const completed = updateStep(player, step, track.stepElapsedMs, deltaMs);
//         if (completed) {
//             track.currStep += 1;
//             track.stepElapsedMs = 0;
//         } else {
//             break;
//         }
//     }

//     if (track.currStep >= track.steps.items.len) {
//         track.done = true;
//     }
// }

// // ----------------------------------------------------------------------------
// /// Returns true when the step is finished and the track should advance.
// fn updateStep(player: *SequencePlayer, step: *Step, elapsed: f64, deltaMs: f64) bool {
//     switch (step.*) {
//         .wait => |w| {
//             return elapsed >= w.durationMs;
//         },
//         .screen_flash => |sf| {
//             // Fire-and-forget: set the flash state and advance immediately.
//             player.flashActive = true;
//             player.flashColor = sf.color;
//             player.flashRemainingMs = sf.durationMs;
//             player.flashTotalMs = sf.durationMs;
//             return true;
//         },
//         .set_actor_state => {
//             // TODO: look up entity by entityId and switch animation state.
//             return true;
//         },
//         .move_to => |mv| {
//             // TODO: interpolate entity position towards mv.target over mv.durationMs.
//             return elapsed >= mv.durationMs;
//         },
//         .spawn_effect => |se| {
//             // TODO: spawn effect sprite se.spriteName at se.pos.
//             return elapsed >= se.durationMs;
//         },
//         .parallel => |*par| {
//             for (par.tracks.items) |subTrack| {
//                 updateTrack(player, subTrack, deltaMs);
//             }
//             for (par.tracks.items) |subTrack| {
//                 if (!subTrack.done) return false;
//             }
//             return true;
//         },
//     }
// }
