const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const RectF = pixzig.RectF;
const RectI = pixzig.RectI;
const ResourceManager = pixzig.resources.ResourceManager;
const TextureHandle = pixzig.resources.TextureHandle;
const FrameSequenceManager = pixzig.sprites.FrameSequenceManager;
const FrameSequence = pixzig.sprites.FrameSequence;
const Frame = pixzig.sprites.Frame;
const ActorState = pixzig.sprites.ActorState;
const Actor = pixzig.sprites.Actor;
const Sprite = pixzig.sprites.Sprite;

fn createDummyTextureManager(alloc: std.mem.Allocator) !ResourceManager {
    var tm = ResourceManager.init(alloc);
    const parent = TextureHandle{ .val = .{
        .texture = 0,
        .size = .{ .x = 128, .y = 128 },
        .src = RectF.fromCoords(0, 0, 128, 128, 128, 128),
    } };
    _ = try tm.addSubTexture(&parent, "player_right_1", RectI.init(0, 0, 8, 8));
    _ = try tm.addSubTexture(&parent, "player_right_2", RectI.init(8, 0, 8, 8));
    _ = try tm.addSubTexture(&parent, "player_right_3", RectI.init(16, 0, 8, 8));
    return tm;
}

pub fn frameSequenceFileLoadTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const jsonStr =
        \\ {
        \\     "sequences": [
        \\         {
        \\             "mode": "loop",
        \\             "name": "player_right",
        \\             "frames": [
        \\                 {"name": "player_right_1", "ms": 300, "flip": "none"},
        \\                 {"name": "player_right_2", "ms": 300, "flip": "none"},
        \\                 {"name": "player_right_3", "ms": 300, "flip": "none"}
        \\             ]
        \\         }
        \\     ],
        \\    "states": []
        \\ }
    ;

    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var seqMgr = try FrameSequenceManager.init(alloc);
    defer seqMgr.deinit();
    try seqMgr.loadSequence(jsonStr, &tm);
    try testz.expectEqual(seqMgr.sequences.count(), 1);
    const seq = seqMgr.getSeq("player_right");
    try testz.expectTrue(seq != null);
    try testz.expectEqual(seq.?.mode, pixzig.sprites.AnimPlayMode.loop);
    try testz.expectEqual(seq.?.frames.items.len, 3);
}

pub fn actorSequenceFileLoadTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const jsonStr =
        \\ {
        \\     "sequences": [
        \\         {
        \\             "mode": "loop",
        \\             "name": "player_right",
        \\             "frames": [
        \\                 {"name": "player_right_1", "ms": 300, "flip": "none"}
        \\             ]
        \\         }
        \\     ],
        \\     "states": [
        \\        {
        \\          "name": "right",
        \\          "nextStateName": null,
        \\          "frameSeqName": "player_right",
        \\          "flip": "none"
        \\        }
        \\     ]
        \\ }
    ;

    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var seqMgr = try FrameSequenceManager.init(alloc);
    defer seqMgr.deinit();
    try seqMgr.loadSequence(jsonStr, &tm);
    try testz.expectEqual(seqMgr.sequences.count(), 1);
    const seq = seqMgr.getSeq("player_right");
    try testz.expectTrue(seq != null);
    try testz.expectEqual(seq.?.mode, pixzig.sprites.AnimPlayMode.loop);
    try testz.expectEqual(seq.?.frames.items.len, 1);

    try testz.expectEqual(seqMgr.actorStates.count(), 1);
    const st = seqMgr.getState("right");
    try testz.expectTrue(st != null);
    try testz.expectEqual(st.?.sequence, seq.?);
}

// --- Pixel-space subtextures and the Sprite convenience API ---

pub fn subTextureNestedPixelsMapToImageUvTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    // player_right_2 is pixels (8,0)-(16,8) of the 128x128 image. A 4x4
    // subtexture at (4,4) inside it is image pixels (12,4)-(16,8).
    const frame = try tm.getTexture("player_right_2");
    const inner = try tm.addSubTexture(frame, "inner", RectI.init(4, 4, 4, 4));
    const tex = inner.val;
    try testz.expectEqual(tex.size.x, 4);
    try testz.expectEqual(tex.size.y, 4);
    try testz.expectEqual(tex.src.l, 12.0 / 128.0);
    try testz.expectEqual(tex.src.t, 4.0 / 128.0);
    try testz.expectEqual(tex.src.r, 16.0 / 128.0);
    try testz.expectEqual(tex.src.b, 8.0 / 128.0);
}

pub fn createSpriteByNameUsesFrameSizeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    const spr = try tm.createSprite("player_right_3");
    try testz.expectEqual(spr.size.x, 8.0);
    try testz.expectEqual(spr.size.y, 8.0);
    try testz.expectEqual(spr.dest.r, 8.0);
    try testz.expectTrue(spr.tint == null);

    try testz.expectError(tm.createSprite("missing"), error.NoTextureWithThatName);
}

pub fn spriteFloatPosAndScaleStayInSyncTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var spr = try tm.createSprite("player_right_1");

    spr.setPosF(10.5, 20.25);
    spr.setScale(2, 3);
    try testz.expectEqual(spr.dest.l, 10.5);
    try testz.expectEqual(spr.dest.t, 20.25);
    try testz.expectEqual(spr.dest.r, 26.5);
    try testz.expectEqual(spr.dest.b, 44.25);
    try testz.expectEqual(spr.scale().x, 2.0);
    try testz.expectEqual(spr.scale().y, 3.0);

    // Moving keeps the scaled size.
    spr.setPos(1, 2);
    try testz.expectEqual(spr.dest.r, 17.0);
    try testz.expectEqual(spr.dest.b, 26.0);
    try testz.expectEqual(spr.pos().x, 1.0);
}

pub fn spriteOriginPlacesPivotAtPosTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var spr = try tm.createSprite("player_right_1"); // 8x8 frame

    // Bottom-center pivot: the frame's (4, 8) lands on (100, 50).
    spr.setOriginNormalized(0.5, 1);
    spr.setPos(100, 50);
    try testz.expectEqual(spr.dest.l, 96.0);
    try testz.expectEqual(spr.dest.t, 42.0);
    try testz.expectEqual(spr.dest.r, 104.0);
    try testz.expectEqual(spr.dest.b, 50.0);
    try testz.expectEqual(spr.pos().x, 100.0);
    try testz.expectEqual(spr.pos().y, 50.0);

    // Scaling grows around the pivot, which stays at (100, 50).
    spr.setScale(2, 2);
    try testz.expectEqual(spr.dest.l, 92.0);
    try testz.expectEqual(spr.dest.t, 34.0);
    try testz.expectEqual(spr.dest.b, 50.0);
    try testz.expectEqual(spr.pos().x, 100.0);
}

pub fn spriteSetOriginKeepsPositionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var spr = try tm.createSprite("player_right_1");

    spr.setPos(10, 10);
    spr.setOrigin(2, 3);
    // pos() is unchanged; the image shifts so (2, 3) sits on it.
    try testz.expectEqual(spr.pos().x, 10.0);
    try testz.expectEqual(spr.pos().y, 10.0);
    try testz.expectEqual(spr.dest.l, 8.0);
    try testz.expectEqual(spr.dest.t, 7.0);
}

fn makeWalkSeq(alloc: std.mem.Allocator, tm: *ResourceManager) !FrameSequence {
    return FrameSequence.init(alloc, &[_]Frame{
        .{ .tex = try tm.getTexture("player_right_2"), .frameTimeMs = 100 },
        .{ .tex = try tm.getTexture("player_right_3"), .frameTimeMs = 100 },
    });
}

pub fn frameApplyCombinesFlipsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    const tex = try tm.getTexture("player_right_2");
    const src = tex.val.src;
    var spr = Sprite.create(tex);

    // Frame flipped on x, state flipped on both: x cancels, y remains.
    const frame: Frame = .{ .tex = tex, .frameTimeMs = 100, .flipX = true };
    frame.apply(&spr, true, true);
    try testz.expectEqual(spr.srcCoords.l, src.l);
    try testz.expectEqual(spr.srcCoords.r, src.r);
    try testz.expectEqual(spr.srcCoords.t, src.b);
    try testz.expectEqual(spr.srcCoords.b, src.t);

    frame.apply(&spr, false, false);
    try testz.expectEqual(spr.srcCoords.l, src.r);
    try testz.expectEqual(spr.srcCoords.r, src.l);
    try testz.expectEqual(spr.srcCoords.t, src.t);
}

pub fn actorAppliesFramesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var seq = try makeWalkSeq(alloc, &tm);
    defer seq.deinit();
    const walk: ActorState = .{ .name = "walk", .sequence = &seq };

    const f2 = try tm.getTexture("player_right_2");
    const f3 = try tm.getTexture("player_right_3");

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();

    // Adding the first state applies its first frame right away.
    _ = try actor.addState(&walk, .{});
    try testz.expectEqual(actor.sprite.texture, f2);
    try testz.expectEqual(actor.sprite.srcCoords.l, f2.val.src.l);

    actor.update(150);
    try testz.expectEqual(actor.sprite.texture, f3);
    try testz.expectEqual(actor.sprite.srcCoords.l, f3.val.src.l);
}

pub fn actorSetStateAppliesFirstFrameTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var seq = try makeWalkSeq(alloc, &tm);
    defer seq.deinit();
    const right: ActorState = .{ .name = "right", .sequence = &seq };
    const left: ActorState = .{ .name = "left", .sequence = &seq, .flipX = true };

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();
    _ = try actor.addState(&right, .{});
    _ = try actor.addState(&left, .{});

    actor.update(150); // now on the second frame of "right"
    try actor.setState("left", .{});
    const f2 = try tm.getTexture("player_right_2");
    try testz.expectEqual(actor.sprite.texture, f2);
    // Horizontal flip swaps l and r.
    try testz.expectEqual(actor.sprite.srcCoords.l, f2.val.src.r);
    try testz.expectEqual(actor.sprite.srcCoords.r, f2.val.src.l);
}

pub fn actorAliasedStateNamesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var seq = try makeWalkSeq(alloc, &tm);
    defer seq.deinit();
    const redLeft: ActorState = .{ .name = "red_left", .sequence = &seq };
    const redRight: ActorState = .{ .name = "red_right", .sequence = &seq, .flipX = true };

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();

    // The alias is copied, so a temporary buffer is fine.
    var buf: [8]u8 = undefined;
    _ = try actor.addState(&redLeft, .{ .name = try std.fmt.bufPrint(&buf, "left", .{}) });
    @memset(&buf, 'x');
    _ = try actor.addState(&redRight, .{ .name = "right" });

    try testz.expectEqualStr(actor.currName, "left");
    try testz.expectEqual(actor.currState.?, &redLeft);

    try actor.setState("right", .{});
    try testz.expectEqualStr(actor.currName, "right");
    try testz.expectEqual(actor.currState.?, &redRight);
    try testz.expectError(actor.setState("red_right", .{}), error.UnknownActorState);

    // Already in "right": a no-op that doesn't restart the animation.
    actor.update(150);
    try actor.setState("right", .{});
    try testz.expectEqual(actor.currFrame, 1);
}

pub fn actorsShareManagerStatesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var seqMgr = try FrameSequenceManager.init(alloc);
    defer seqMgr.deinit();
    try seqMgr.addSeq("walk", try makeWalkSeq(alloc, &tm));
    try seqMgr.addState(.{ .name = "walk", .sequence = seqMgr.getSeq("walk").? });
    const state = seqMgr.getState("walk").?;

    var a = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer a.deinit();
    var b = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer b.deinit();
    _ = try a.addState(state, .{});
    _ = try b.addState(state, .{});
    try testz.expectEqual(a.currState.?, b.currState.?);

    // Re-adding a state or sequence updates it in place, so the actors'
    // pointers stay valid and see the change.
    try seqMgr.addState(.{ .name = "walk", .sequence = seqMgr.getSeq("walk").?, .flipY = true });
    try testz.expectEqual(seqMgr.getState("walk").?, state);
    try testz.expectTrue(a.currState.?.flipY);

    const seqPtr = seqMgr.getSeq("walk").?;
    try seqMgr.addSeq("walk", try FrameSequence.init(alloc, &[_]Frame{
        .{ .tex = try tm.getTexture("player_right_1"), .frameTimeMs = 50 },
    }));
    try testz.expectEqual(seqMgr.getSeq("walk").?, seqPtr);
    try testz.expectEqual(state.sequence.frames.items.len, 1);
}

// A two-frame play-once sequence (player_right_1, then _3), for "attack" states.
fn makeOnceSeq(alloc: std.mem.Allocator, tm: *ResourceManager) !FrameSequence {
    var seq = try FrameSequence.init(alloc, &[_]Frame{
        .{ .tex = try tm.getTexture("player_right_1"), .frameTimeMs = 100 },
        .{ .tex = try tm.getTexture("player_right_3"), .frameTimeMs = 100 },
    });
    seq.mode = .once;
    return seq;
}

pub fn actorOnceHoldsLastFrameTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var seq = try makeOnceSeq(alloc, &tm);
    defer seq.deinit();
    const attack: ActorState = .{ .name = "attack", .sequence = &seq };

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();
    _ = try actor.addState(&attack, .{});

    const f3 = try tm.getTexture("player_right_3");
    actor.update(150); // second (last) frame
    try testz.expectEqual(actor.sprite.texture, f3);
    try testz.expectFalse(actor.finished());

    actor.update(150); // past the end: holds the last frame
    try testz.expectEqual(actor.sprite.texture, f3);
    try testz.expectTrue(actor.finished());
    try testz.expectEqual(actor.currFrame, 1);

    actor.update(1000);
    try testz.expectEqual(actor.sprite.texture, f3);
    try testz.expectTrue(actor.finished());

    // setState on the finished state stays a no-op.
    try actor.setState("attack", .{});
    try testz.expectTrue(actor.finished());

    // ...unless asked to reset, which replays it from the first frame.
    try actor.setState("attack", .{ .reset = true });
    try testz.expectFalse(actor.finished());
    try testz.expectEqual(actor.currFrame, 0);
}

pub fn actorOnceFollowsNextStateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var walk = try makeWalkSeq(alloc, &tm);
    defer walk.deinit();
    var attack = try makeOnceSeq(alloc, &tm);
    defer attack.deinit();
    const idleState: ActorState = .{ .name = "idle", .sequence = &walk };
    const attackState: ActorState = .{ .name = "attack", .nextState = "idle", .sequence = &attack };

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();
    _ = try actor.addState(&idleState, .{});
    _ = try actor.addState(&attackState, .{});

    try actor.setState("attack", .{});
    try testz.expectEqual(actor.sprite.texture, try tm.getTexture("player_right_1"));
    actor.update(150);
    actor.update(150);

    // Back on idle's first frame, which is applied right away.
    try testz.expectEqualStr(actor.currName, "idle");
    try testz.expectEqual(actor.currFrame, 0);
    try testz.expectEqual(actor.sprite.texture, try tm.getTexture("player_right_2"));
    try testz.expectFalse(actor.finished());
}

pub fn actorOnceUnknownNextStateHoldsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var attack = try makeOnceSeq(alloc, &tm);
    defer attack.deinit();
    const attackState: ActorState = .{ .name = "attack", .nextState = "missing", .sequence = &attack };

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();
    _ = try actor.addState(&attackState, .{});

    actor.update(150);
    actor.update(150);
    try testz.expectEqualStr(actor.currName, "attack");
    try testz.expectTrue(actor.finished());
}

pub fn actorLoopIgnoresNextStateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var walk = try makeWalkSeq(alloc, &tm);
    defer walk.deinit();
    const walkState: ActorState = .{ .name = "walk", .nextState = "other", .sequence = &walk };
    const otherState: ActorState = .{ .name = "other", .sequence = &walk };

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();
    _ = try actor.addState(&walkState, .{});
    _ = try actor.addState(&otherState, .{});

    actor.update(150);
    actor.update(150); // wraps
    try testz.expectEqualStr(actor.currName, "walk");
    try testz.expectEqual(actor.currFrame, 0);
    try testz.expectFalse(actor.finished());
}

pub fn actorSetStateUnknownErrorsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var walk = try makeWalkSeq(alloc, &tm);
    defer walk.deinit();
    const walkState: ActorState = .{ .name = "walk", .sequence = &walk };

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();
    _ = try actor.addState(&walkState, .{});

    try testz.expectError(actor.setState("nope", .{}), error.UnknownActorState);
    try testz.expectEqualStr(actor.currName, "walk");
}

pub fn spriteSetSrcRectIsPixelsWithinFrameTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var spr = try tm.createSprite("player_right_3");

    // player_right_3 starts at image pixel 16; its (2,0)-(6,8) is image (18,0)-(22,8).
    spr.setSrcRect(RectI.init(2, 0, 4, 8));
    try testz.expectEqual(spr.srcCoords.l, 18.0 / 128.0);
    try testz.expectEqual(spr.srcCoords.r, 22.0 / 128.0);
    try testz.expectEqual(spr.srcCoords.b, 8.0 / 128.0);
}

pub fn sequenceUnknownFrameSeqErrorsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const jsonStr =
        \\ {
        \\     "sequences": [],
        \\     "states": [
        \\        { "name": "right", "nextStateName": null, "frameSeqName": "missing", "flip": "none" }
        \\     ]
        \\ }
    ;

    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var seqMgr = try FrameSequenceManager.init(alloc);
    defer seqMgr.deinit();
    try testz.expectError(seqMgr.loadSequence(jsonStr, &tm), error.UnknownFrameSequence);
    try testz.expectEqual(seqMgr.actorStates.count(), 0);
}

pub fn actorCurrEmptySequenceIsNullTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var empty = try FrameSequence.initEmpty(alloc);
    defer empty.deinit();
    const idle: ActorState = .{ .name = "idle", .sequence = &empty };

    var actor = Actor.init(alloc, try tm.createSprite("player_right_1"));
    defer actor.deinit();
    _ = try actor.addState(&idle, .{});

    try testz.expectTrue(actor.curr() == null);
}
