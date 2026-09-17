const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const RectF = pixzig.RectF;
const RectI = pixzig.RectI;
const ResourceManager = pixzig.resources.ResourceManager;
const ManagedTexture = pixzig.resources.ManagedTexture;
const Texture = pixzig.Texture;
const FrameSequenceManager = pixzig.sprites.FrameSequenceManager;

fn noopFreeTexture(_: Texture) void {}

fn createDummyTextureManager(alloc: std.mem.Allocator) !ResourceManager {
    var tm = ResourceManager.init(alloc);
    var parent = ManagedTexture.init(alloc, 999, noopFreeTexture);
    defer parent.deinit();
    try parent.add(.{
        .texture = 0,
        .size = .{ .x = 128, .y = 128 },
        .src = RectF.fromCoords(0, 0, 128, 128, 128, 128),
    });
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

    // tm must outlive seqMgr: FrameSequence.deinit releases each frame's
    // texture handle back into tm, so tm needs to deinit last.
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

    // tm must outlive seqMgr (see frameSequenceFileLoadTest).
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
    const tex = inner.get().?.val;
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

    var spr = try tm.createSprite("player_right_3");
    defer spr.deinit();
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
    defer spr.deinit();

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

pub fn spriteSetSrcRectIsPixelsWithinFrameTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var tm = try createDummyTextureManager(alloc);
    defer tm.deinit();

    var spr = try tm.createSprite("player_right_3");
    defer spr.deinit();

    // player_right_3 starts at image pixel 16; its (2,0)-(6,8) is image (18,0)-(22,8).
    spr.setSrcRect(RectI.init(2, 0, 4, 8));
    try testz.expectEqual(spr.src_coords.l, 18.0 / 128.0);
    try testz.expectEqual(spr.src_coords.r, 22.0 / 128.0);
    try testz.expectEqual(spr.src_coords.b, 8.0 / 128.0);
}
