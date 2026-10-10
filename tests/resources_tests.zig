const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const Resource = pixzig.resources.Resource;
const TextureHandle = pixzig.resources.TextureHandle;
const ResourceManager = pixzig.resources.ResourceManager;
const RectF = pixzig.RectF;
const RectI = pixzig.RectI;

// Track which integer values have been freed so tests can assert the
// underlying resource lifecycle.
var g_freed_buf: [64]i32 = @splat(0);
var g_freed_len: usize = 0;

fn intFree(v: *i32) void {
    g_freed_buf[g_freed_len] = v.*;
    g_freed_len += 1;
}

fn resetFreed() void {
    g_freed_len = 0;
}

fn wasFreed(v: i32) bool {
    for (g_freed_buf[0..g_freed_len]) |x| {
        if (x == v) return true;
    }
    return false;
}

const IntHandle = Resource(i32, intFree);

// --- Resource slot basics ---

pub fn freshSlotStartsAtVersionZeroTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const h = IntHandle{ .val = 100 };
    try testz.expectEqual(h.version, 0);
    try testz.expectEqual(h.val, 100);
}

pub fn replaceFreesOldValueAndBumpsVersionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    resetFreed();
    var h = IntHandle{ .val = 1 };

    h.replace(2);
    try testz.expectTrue(wasFreed(1));
    try testz.expectFalse(wasFreed(2));
    try testz.expectEqual(h.val, 2);
    try testz.expectEqual(h.version, 1);

    h.replace(3);
    try testz.expectEqual(h.version, 2);

    h.free();
    try testz.expectTrue(wasFreed(3));
}

// --- ResourceManager (no GL needed for addSubTexture / getTexture) ---

fn dummyParent() TextureHandle {
    return .{ .val = .{
        .texture = 0,
        .size = .{ .x = 128, .y = 128 },
        .src = RectF.fromCoords(0, 0, 128, 128, 128, 128),
    } };
}

pub fn rmAddSubTextureRegistersAndGetReturnsItTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    const parent = dummyParent();
    const sub = try rm.addSubTexture(&parent, "foo", RectI.init(0, 0, 8, 8));
    try testz.expectEqual(sub.val.size.x, 8);
    try testz.expectEqual(sub.val.size.y, 8);

    const fetched = try rm.getTexture("foo");
    try testz.expectEqual(fetched, sub);
}

pub fn rmGetTextureMissingReturnsErrorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    try testz.expectError(rm.getTexture("not_there"), error.NoTextureWithThatName);
}

pub fn rmReloadReplacesInPlaceTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    const parent = dummyParent();
    const v1 = try rm.addSubTexture(&parent, "foo", RectI.init(0, 0, 8, 8));
    try testz.expectEqual(v1.version, 0);

    // Re-adding the name swaps the value into the same slot.
    const v2 = try rm.addSubTexture(&parent, "foo", RectI.init(8, 0, 16, 16));
    try testz.expectEqual(v1, v2);
    try testz.expectEqual(v1.version, 1);
    try testz.expectEqual(v1.val.size.x, 16);
    try testz.expectEqual(rm.atlas.count(), 1);
}

pub fn rmSpriteFollowsReloadTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    const parent = dummyParent();
    const tex = try rm.addSubTexture(&parent, "frame", RectI.init(0, 0, 8, 8));
    const spr = pixzig.sprites.Sprite.create(tex);

    _ = try rm.addSubTexture(&parent, "frame", RectI.init(0, 0, 12, 12));

    // The sprite holds the slot, so it sees the reloaded value with no
    // re-lookup.
    try testz.expectEqual(spr.texture.val.size.x, 12);
}

pub fn rmNamesAreIndependentTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    const parent = dummyParent();
    const a = try rm.addSubTexture(&parent, "a", RectI.init(0, 0, 8, 8));
    const b = try rm.addSubTexture(&parent, "b", RectI.init(0, 0, 8, 8));
    _ = try rm.addSubTexture(&parent, "b", RectI.init(0, 0, 4, 4));

    try testz.expectTrue(a != b);
    try testz.expectEqual(a.version, 0);
    try testz.expectEqual(a.val.size.x, 8);
    try testz.expectEqual(b.version, 1);
}

pub fn manifestLoadGroupOwnsLoadedKeyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    const json =
        \\{
        \\  "groups": { "game": ["script"] },
        \\  "assets": [
        \\    { "id": "script", "kind": "raw", "path": "script.lua" }
        \\  ]
        \\}
    ;

    var manifest = try pixzig.AssetManifest.loadFromJson(alloc, &rm, json, ".");
    defer manifest.deinit();

    const group_name = try alloc.dupe(u8, "game");
    defer alloc.free(group_name);

    try manifest.loadGroup(group_name);
    @memset(group_name, 'x');

    try testz.expectEqual(manifest.loaded.contains("game"), true);
    manifest.unloadGroup("game");
    try testz.expectEqual(manifest.loaded.count(), 0);
}
