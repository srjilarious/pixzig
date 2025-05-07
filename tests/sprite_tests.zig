const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const RectF = pixzig.RectF;
const TextureManager = pixzig.textures.TextureManager;
const FrameSequenceManager = pixzig.sprites.FrameSequenceManager;

fn createDummyTextureManager(alloc: std.mem.Allocator) !TextureManager {
    var tm = TextureManager.init(alloc);
    try tm.atlas.put("player_right_1", .{ .texture = 0, .size = .{ .x = 8, .y = 8 }, .src = RectF.fromCoords(0, 0, 8, 8, 128, 128) });
    try tm.atlas.put("player_right_2", .{ .texture = 0, .size = .{ .x = 8, .y = 8 }, .src = RectF.fromCoords(8, 0, 8, 8, 128, 128) });
    try tm.atlas.put("player_right_3", .{ .texture = 0, .size = .{ .x = 8, .y = 8 }, .src = RectF.fromCoords(16, 0, 8, 8, 128, 128) });
    return tm;
}

pub fn frameSequenceFileLoadTest() !void {
    const alloc = std.heap.page_allocator;
    const jsonStr =
        \\ {
        \\     "sequences": [
        \\         {
        \\             "mode": "loop",
        \\             "name": "player_right",
        \\             "frames": [
        \\                 {"name": "player_right_1", "us": 300, "flip": "none"},
        \\                 {"name": "player_right_2", "us": 300, "flip": "none"},
        \\                 {"name": "player_right_3", "us": 300, "flip": "none"}
        \\             ]
        \\         }
        \\     ],
        \\    "states": [] 
        \\ }
    ;
    // Create a fixed buffer stream from the string
    var buffer_stream = std.io.fixedBufferStream(jsonStr);

    // Get a reader from the stream
    const reader = buffer_stream.reader();

    var seqMgr = try FrameSequenceManager.init(alloc);
    var tm = try createDummyTextureManager(alloc);
    try seqMgr.loadSequence(reader, &tm);
    try testz.expectEqual(seqMgr.sequences.count(), 1);
    const seq = seqMgr.getSeq("player_right");
    try testz.expectTrue(seq != null);
    try testz.expectEqual(seq.?.mode, pixzig.sprites.AnimPlayMode.loop);
    try testz.expectEqual(seq.?.frames.items.len, 3);
}

pub fn actorSequenceFileLoadTest() !void {
    const alloc = std.heap.page_allocator;
    const jsonStr =
        \\ {
        \\     "sequences": [
        \\         {
        \\             "mode": "loop",
        \\             "name": "player_right",
        \\             "frames": [
        \\                 {"name": "player_right_1", "us": 300, "flip": "none"}
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
    // Create a fixed buffer stream from the string
    var buffer_stream = std.io.fixedBufferStream(jsonStr);

    // Get a reader from the stream
    const reader = buffer_stream.reader();

    var seqMgr = try FrameSequenceManager.init(alloc);
    var tm = try createDummyTextureManager(alloc);
    try seqMgr.loadSequence(reader, &tm);
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
