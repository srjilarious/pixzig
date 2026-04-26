const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const seq = pixzig.sequencer;
const flecs = pixzig.flecs;
const Sprite = pixzig.sprites.Sprite;
const Actor = pixzig.sprites.Actor;
const RectF = pixzig.RectF;
const ScriptEngine = pixzig.scripting.ScriptEngine;

// Build a minimal flecs world with the given component types registered.
// Caller owns the world and must call `_ = flecs.fini(world)` when done.
fn makeWorld(comptime Components: anytype) *flecs.world_t {
    const world = flecs.init();
    inline for (Components) |C| flecs.COMPONENT(world, C);
    return world;
}

// Fake texture used across all tests. Never rendered or dereferenced by the
// steps under test — it exists only to satisfy the non-optional *Texture field.
var g_fakeTex: pixzig.Texture = .{
    .texture = 0,
    .size = .{ .x = 16, .y = 16 },
    .src = .{ .l = 0, .t = 0, .r = 1, .b = 1 },
};

// Build a Sprite at (x, y) with a 16×16 size backed by the module-level fake
// texture, whose pointer remains valid for the lifetime of the test binary.
fn makeSprite(x: i32, y: i32) Sprite {
    return .{
        .texture = &g_fakeTex,
        .src_coords = .{ .l = 0, .t = 0, .r = 1, .b = 1 },
        .dest = RectF.fromPosSize(x, y, 16, 16),
        .size = .{ .x = 16, .y = 16 },
        .flip = .none,
        .rotate = .none,
    };
}

// A single WaitStep should not be done before its duration elapses.
pub fn waitStepNotDoneBeforeDurationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);

    try sequence.add(alloc, try seq.WaitStep.init(alloc, 100.0));

    try testz.expectFalse(sequence.update(50.0));
    try testz.expectFalse(sequence.done);
}

// A single WaitStep should be done once its full duration has elapsed.
pub fn waitStepDoneAfterDurationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);

    try sequence.add(alloc, try seq.WaitStep.init(alloc, 100.0));

    _ = sequence.update(50.0);
    try testz.expectTrue(sequence.update(50.0));
    try testz.expectTrue(sequence.done);
}

// An empty sequence should complete immediately.
pub fn emptySequenceIsDoneImmediatelyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);

    try testz.expectTrue(sequence.update(16.0));
    try testz.expectTrue(sequence.done);
}

// Two sequential waits should run one after the other.
pub fn twoWaitStepsRunSequentiallyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);

    try sequence.add(alloc, try seq.WaitStep.init(alloc, 100.0));
    try sequence.add(alloc, try seq.WaitStep.init(alloc, 100.0));

    // First step not done yet.
    try testz.expectFalse(sequence.update(50.0));

    // First step finishes; second step starts but isn't done.
    try testz.expectFalse(sequence.update(50.0));

    // Second step not done yet.
    try testz.expectFalse(sequence.update(50.0));

    // Second step finishes; sequence done.
    try testz.expectTrue(sequence.update(50.0));
    try testz.expectTrue(sequence.done);
}

// ---------------------------------------------------------------------------
// MoveToStep tests
// ---------------------------------------------------------------------------

// MoveToStep should not be done before the full duration has elapsed.
pub fn moveToStepNotDoneBeforeDurationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = makeWorld(.{Sprite});
    defer _ = flecs.fini(world);

    const entity = flecs.new_entity(world, "move1");
    flecs.set(world, entity, Sprite, makeSprite(0, 0));

    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);
    try sequence.add(alloc, try seq.MoveToStep.init(alloc, world, entity, .{ .x = 100, .y = 0 }, 100.0));

    try testz.expectFalse(sequence.update(50.0));
    try testz.expectFalse(sequence.done);
}

// MoveToStep should be done once the full duration has elapsed, with the
// entity positioned at the target.
pub fn moveToStepDoneAfterDurationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = makeWorld(.{Sprite});
    defer _ = flecs.fini(world);

    const entity = flecs.new_entity(world, "move2");
    flecs.set(world, entity, Sprite, makeSprite(0, 0));

    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);
    try sequence.add(alloc, try seq.MoveToStep.init(alloc, world, entity, .{ .x = 100, .y = 80 }, 100.0));

    try testz.expectTrue(sequence.update(100.0));
    try testz.expectTrue(sequence.done);

    const spr = flecs.get(world, entity, Sprite).?;
    try testz.expectEqual(spr.dest.l, 100.0);
    try testz.expectEqual(spr.dest.t, 80.0);
}

// At the midpoint of the duration the sprite should be halfway between
// start and target.
pub fn moveToStepInterpolatesAtMidpointTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = makeWorld(.{Sprite});
    defer _ = flecs.fini(world);

    const entity = flecs.new_entity(world, "move3");
    flecs.set(world, entity, Sprite, makeSprite(0, 0));

    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);
    try sequence.add(alloc, try seq.MoveToStep.init(alloc, world, entity, .{ .x = 100, .y = 60 }, 100.0));

    _ = sequence.update(50.0);

    const spr = flecs.get(world, entity, Sprite).?;
    try testz.expectEqual(spr.dest.l, 50.0);
    try testz.expectEqual(spr.dest.t, 30.0);
}

// ---------------------------------------------------------------------------
// SetActorStateStep tests
// ---------------------------------------------------------------------------

// SetActorStateStep should complete in one tick even when the entity has no
// Actor component (graceful skip).
pub fn setActorStateStepCompletesWithNoActorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = makeWorld(.{Actor});
    defer _ = flecs.fini(world);

    // Entity has no Actor component — the step silently skips but still marks done.
    const entity = flecs.new_entity(world, "actor1");

    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);
    try sequence.add(alloc, try seq.SetActorStateStep.init(alloc, world, entity, "idle"));

    try testz.expectTrue(sequence.update(16.0));
    try testz.expectTrue(sequence.done);
}

// SetActorStateStep should complete in one tick when the entity has an Actor
// component, even if the requested state is not registered (setState is a no-op).
pub fn setActorStateStepCompletesWithActorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = makeWorld(.{Actor});
    defer _ = flecs.fini(world);

    const entity = flecs.new_entity(world, "actor2");
    // Actor is heap-backed (StringHashMap); intentionally not deinit'd here
    // so the ECS copy's backing memory stays valid for the test duration.
    const actor = try Actor.init(alloc);
    flecs.set(world, entity, Actor, actor);

    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);
    try sequence.add(alloc, try seq.SetActorStateStep.init(alloc, world, entity, "walk_right"));

    try testz.expectTrue(sequence.update(16.0));
    try testz.expectTrue(sequence.done);
}

// ---------------------------------------------------------------------------
// Lua scripting bridge tests
// ---------------------------------------------------------------------------

// A Lua script that calls seq_new / seq_wait / seq_play should produce a
// sequence in the player that finishes after the declared wait duration.
pub fn luaSeqWaitBuildsAndRunsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = makeWorld(.{Sprite});
    defer _ = flecs.fini(world);

    var player = seq.SequencePlayer.init(alloc);
    defer player.deinit();

    var seqCtx = seq.SeqScriptingContext.init(alloc, world, &player);
    defer seqCtx.deinit();

    var scriptEng = try ScriptEngine.init(alloc);
    defer scriptEng.deinit();

    seqCtx.bindToLua(scriptEng.lua);

    const script: [:0]const u8 =
        \\local h = seq_new()
        \\seq_wait(h, 100)
        \\seq_play(h)
    ;
    try scriptEng.run(script);

    // Sequence submitted to player.
    try testz.expectEqual(player.sequences.items.len, 1);

    // Partial update — not yet done.
    player.update(50.0);
    try testz.expectEqual(player.sequences.items.len, 1);

    // Full duration — sequence completes and is removed.
    player.update(50.0);
    try testz.expectEqual(player.sequences.items.len, 0);
}

// A Lua script using seq_move_to should drive the entity to the target position.
pub fn luaSeqMoveToReachesTargetTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = makeWorld(.{Sprite});
    defer _ = flecs.fini(world);

    const entity = flecs.new_entity(world, "luamove");
    flecs.set(world, entity, Sprite, makeSprite(0, 0));

    var player = seq.SequencePlayer.init(alloc);
    defer player.deinit();

    var seqCtx = seq.SeqScriptingContext.init(alloc, world, &player);
    defer seqCtx.deinit();

    var scriptEng = try ScriptEngine.init(alloc);
    defer scriptEng.deinit();

    seqCtx.bindToLua(scriptEng.lua);

    // Push entity ID as a Lua global so the script can reference it.
    scriptEng.lua.pushInteger(@intCast(entity));
    scriptEng.lua.setGlobal("test_entity");

    const script: [:0]const u8 =
        \\local h = seq_new()
        \\seq_move_to(h, test_entity, 80, 48, 100)
        \\seq_play(h)
    ;
    try scriptEng.run(script);

    try testz.expectEqual(player.sequences.items.len, 1);

    // Single update covers the full duration.
    player.update(100.0);
    try testz.expectEqual(player.sequences.items.len, 0);

    const spr = flecs.get(world, entity, Sprite).?;
    try testz.expectEqual(spr.dest.l, 80.0);
    try testz.expectEqual(spr.dest.t, 48.0);
}

// Multiple steps built from Lua run sequentially in the correct order.
pub fn luaSeqMultipleStepsRunInOrderTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = makeWorld(.{Sprite});
    defer _ = flecs.fini(world);

    const entity = flecs.new_entity(world, "luamulti");
    flecs.set(world, entity, Sprite, makeSprite(0, 0));

    var player = seq.SequencePlayer.init(alloc);
    defer player.deinit();

    var seqCtx = seq.SeqScriptingContext.init(alloc, world, &player);
    defer seqCtx.deinit();

    var scriptEng = try ScriptEngine.init(alloc);
    defer scriptEng.deinit();

    seqCtx.bindToLua(scriptEng.lua);

    scriptEng.lua.pushInteger(@intCast(entity));
    scriptEng.lua.setGlobal("test_entity");

    // Two sequential moves: first to (50, 0), then to (50, 50).
    const script: [:0]const u8 =
        \\local h = seq_new()
        \\seq_move_to(h, test_entity, 50, 0, 100)
        \\seq_move_to(h, test_entity, 50, 50, 100)
        \\seq_play(h)
    ;
    try scriptEng.run(script);

    // After first move duration — entity at (50, 0), second step not yet done.
    player.update(100.0);
    try testz.expectEqual(player.sequences.items.len, 1);
    const spr_mid = flecs.get(world, entity, Sprite).?;
    try testz.expectEqual(spr_mid.dest.l, 50.0);
    try testz.expectEqual(spr_mid.dest.t, 0.0);

    // After second move duration — entity at (50, 50), sequence removed.
    player.update(100.0);
    try testz.expectEqual(player.sequences.items.len, 0);
    const spr_end = flecs.get(world, entity, Sprite).?;
    try testz.expectEqual(spr_end.dest.l, 50.0);
    try testz.expectEqual(spr_end.dest.t, 50.0);
}
