const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const ManagedResource = pixzig.resources.ManagedResource;
const ManagedTexture = pixzig.resources.ManagedTexture;
const ResourceManager = pixzig.resources.ResourceManager;
const Texture = pixzig.Texture;
const RectF = pixzig.RectF;
const RectI = pixzig.RectI;

// Track which integer values have been freed so tests can assert the
// underlying resource lifecycle.
var g_freed_buf: [64]i32 = @splat(0);
var g_freed_len: usize = 0;

fn intFree(v: i32) void {
    g_freed_buf[g_freed_len] = v;
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

const ManagedInt = ManagedResource("Int", i32);

// --- add / get / acquire basics ---

pub fn addCreatesFreshHandleTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 7, "test", intFree);
    defer res.deinit();

    try res.add(100);
    const h = res.get().?;
    try testz.expectEqual(h.id, 7);
    try testz.expectEqual(h.generation, 1);
    try testz.expectEqual(h.refCount, 0);
    try testz.expectEqual(h.dirty, false);
    try testz.expectEqual(h.val, 100);
}

pub fn addBumpsGenerationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 1, "test", intFree);
    defer res.deinit();

    try res.add(10);
    try testz.expectEqual(res.get().?.generation, 1);
    try res.add(20);
    try testz.expectEqual(res.get().?.generation, 2);
}

pub fn getReturnsNullBeforeAnyAddTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 1, "test", intFree);
    defer res.deinit();
    try testz.expectEqual(res.get(), null);
    try testz.expectEqual(res.acquire(), null);
}

pub fn getReturnsLatestGenerationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 9, "test", intFree);
    defer res.deinit();

    try res.add(100);
    // Hold a ref to v1 so the next add doesn't immediately reclaim it.
    const v1 = res.acquire().?;
    try res.add(200);

    const latest = res.get().?;
    try testz.expectEqual(latest.val, 200);
    try testz.expectEqual(latest.generation, 2);

    res.release(v1);
}

pub fn acquireBumpsRefCountTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 1, "test", intFree);
    defer res.deinit();

    try res.add(42);
    const h = res.acquire().?;
    try testz.expectEqual(h.refCount, 1);
    const h2 = res.acquire().?;
    try testz.expectEqual(h2.refCount, 2);
    res.release(h2);
    res.release(h);
}

// --- refcount governs lifetime ---

pub fn refCountKeepsHandleAliveAfterUpdateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 5, "test", intFree);
    defer res.deinit();

    try res.add(111);
    const old = res.acquire().?;

    // Add a new version. The old handle is still referenced, so it must
    // NOT be freed; it should only be marked dirty.
    try res.add(222);

    try testz.expectEqual(wasFreed(111), false);
    try testz.expectEqual(old.dirty, true);
    try testz.expectEqual(old.val, 111);

    // Releasing the last reference on the dirty old handle frees it.
    res.release(old);
    try testz.expectEqual(wasFreed(111), true);
}

pub fn cleanHandleAtZeroRefCountIsRetainedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 3, "test", intFree);
    defer res.deinit();

    try res.add(77);
    const ref = res.acquire().?;
    res.release(ref);

    // refCount is now zero but no newer version exists, so the handle
    // remains in the res and is still discoverable.
    try testz.expectEqual(wasFreed(77), false);
    try testz.expectEqual(res.get().?.val, 77);
}

pub fn addReclaimsUnreferencedOldVersionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 8, "test", intFree);
    defer res.deinit();

    try res.add(1);
    // No one acquired v1; adding v2 should free v1 immediately since
    // nothing references it.
    try res.add(2);

    try testz.expectEqual(wasFreed(1), true);
    try testz.expectEqual(wasFreed(2), false);
    try testz.expectEqual(res.get().?.val, 2);
}

pub fn rollbackAddRestoresPreviousGenerationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 8, "test", intFree);
    defer res.deinit();

    try res.add(1);
    const old = res.acquire().?;
    try res.add(2);
    try testz.expectEqual(old.dirty, true);

    try testz.expectEqual(res.rollbackAdd(2), true);
    try testz.expectEqual(wasFreed(2), true);
    try testz.expectEqual(old.dirty, false);
    try testz.expectEqual(res.get().?.val, 1);

    res.release(old);
}

pub fn rollbackAddRefusesAcquiredGenerationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 8, "test", intFree);
    defer res.deinit();

    try res.add(1);
    const held = res.acquire().?;
    defer res.release(held);

    try testz.expectEqual(res.rollbackAdd(1), false);
    try testz.expectEqual(wasFreed(1), false);
    try testz.expectEqual(res.get().?.val, 1);
}

// --- dirty propagation ---

pub fn updateMarksOldHandleDirtyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 4, "test", intFree);
    defer res.deinit();

    try res.add(10);
    const holder = res.acquire().?;
    try testz.expectEqual(holder.dirty, false);

    try res.add(20);
    try testz.expectEqual(holder.dirty, true);

    res.release(holder);
}

pub fn freshHandleIsNotDirtyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 1, "test", intFree);
    defer res.deinit();

    try res.add(100);
    const old = res.acquire().?;
    try res.add(200);
    const fresh = res.get().?;

    try testz.expectEqual(fresh.dirty, false);
    try testz.expectEqual(old.dirty, true);

    res.release(old);
}

// --- typical hot-reload flow ---

pub fn hotReloadFlowTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 42, "test", intFree);
    defer res.deinit();

    try res.add(1);
    var holder = res.acquire().?;

    // simulated reload
    try res.add(2);
    try testz.expectEqual(holder.dirty, true);

    // consumer notices, swaps to the new version
    res.release(holder);
    try testz.expectEqual(wasFreed(1), true);
    holder = res.acquire().?;
    try testz.expectEqual(holder.val, 2);
    try testz.expectEqual(holder.dirty, false);

    res.release(holder);
}

// --- slot reuse and res isolation ---

pub fn freedSlotIsReusedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 1, "test", intFree);
    defer res.deinit();

    try res.add(10);
    try res.add(11); // reclaims the v1 slot immediately
    try testz.expectEqual(res.res.items.len, 1);
}

pub fn separateressAreIndependentTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res_a = ManagedInt.init(alloc, 1, "test", intFree);
    defer res_a.deinit();
    var res_b = ManagedInt.init(alloc, 2, "test", intFree);
    defer res_b.deinit();

    try res_a.add(100);
    const a = res_a.acquire().?;

    // An update to res_b must not mark res_a's handle dirty or free its
    // value.
    try res_b.add(200);
    try res_b.add(201); // forces a reclaim inside res_b

    try testz.expectEqual(a.dirty, false);
    try testz.expectEqual(wasFreed(100), false);
    try testz.expectEqual(res_a.get().?.id, 1);
    try testz.expectEqual(res_b.get().?.id, 2);

    res_a.release(a);
}

// --- ResourceManager atlas (no GL needed for addSubTexture / getTexture) ---

fn noopFreeTexture(_: Texture) void {}

fn makeDummyParent(alloc: std.mem.Allocator) !ManagedTexture {
    var m = ManagedTexture.init(alloc, 999, "test", noopFreeTexture);
    try m.add(.{
        .texture = 0,
        .size = .{ .x = 128, .y = 128 },
        .src = RectF.fromCoords(0, 0, 128, 128, 128, 128),
    });
    return m;
}

pub fn rmAddSubTextureRegistersAndGetReturnsItTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    const sub = try rm.addSubTexture(parent.get().?, "foo", RectI.init(0, 0, 8, 8));
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

pub fn rmGidIncrementsOncePerDistinctNameTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    try testz.expectEqual(rm.gid, 0);

    _ = try rm.addSubTexture(parent.get().?, "foo", RectI.init(0, 0, 8, 8));
    try testz.expectEqual(rm.gid, 1);

    _ = try rm.addSubTexture(parent.get().?, "bar", RectI.init(0, 0, 8, 8));
    try testz.expectEqual(rm.gid, 2);

    // Reload "foo" reuses the existing res, so gid must not change.
    _ = try rm.addSubTexture(parent.get().?, "foo", RectI.init(8, 0, 8, 8));
    try testz.expectEqual(rm.gid, 2);
}

pub fn rmAddSubTextureReloadMarksOldHandleDirtyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    _ = try rm.addSubTexture(parent.get().?, "foo", RectI.init(0, 0, 8, 8));

    const res = rm.atlas.get("foo").?;
    const old_handle = res.acquire().?;
    try testz.expectEqual(old_handle.dirty, false);

    _ = try rm.addSubTexture(parent.get().?, "foo", RectI.init(8, 0, 8, 8));
    try testz.expectEqual(old_handle.dirty, true);
    try testz.expectEqual(res.get().?.generation, 2);

    old_handle.release();
}

// --- acquireTexture / releaseTexture helpers ---

pub fn rmAcquireTextureBumpsRefCountTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    _ = try rm.addSubTexture(parent.get().?, "foo", RectI.init(0, 0, 8, 8));

    const h1 = try rm.acquireTexture("foo");
    try testz.expectEqual(h1.refCount, 1);
    const h2 = try rm.acquireTexture("foo");
    try testz.expectEqual(h2.refCount, 2);
    try testz.expectEqual(h1, h2);

    h2.release();
    h1.release();
    try testz.expectEqual(rm.atlas.get("foo").?.get().?.refCount, 0);
}

pub fn rmAcquireTextureMissingReturnsErrorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    try testz.expectError(rm.acquireTexture("not_there"), error.NoTextureWithThatName);
}

pub fn rmReloadVisibleAsDirtyThroughHelperTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    _ = try rm.addSubTexture(parent.get().?, "foo", RectI.init(0, 0, 8, 8));

    const holder = try rm.acquireTexture("foo");
    try testz.expectEqual(holder.dirty, false);

    _ = try rm.addSubTexture(parent.get().?, "foo", RectI.init(8, 0, 8, 8));
    try testz.expectEqual(holder.dirty, true);

    // The fresh handle reachable through the helper is the v2 generation.
    const fresh = try rm.acquireTexture("foo");
    try testz.expectEqual(fresh.generation, 2);
    try testz.expectEqual(fresh.dirty, false);

    holder.release();
    fresh.release();
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

// --- texture views keep their image generation alive ---

var g_freed_images_buf: [16]c_uint = @splat(0);
var g_freed_images_len: usize = 0;

fn recordFreedImage(img: pixzig.textures.TextureImage) void {
    g_freed_images_buf[g_freed_images_len] = img.texture;
    g_freed_images_len += 1;
}

fn imageWasFreed(texture: c_uint) bool {
    for (g_freed_images_buf[0..g_freed_images_len]) |t| {
        if (t == texture) return true;
    }
    return false;
}

pub fn rmViewHoldsImageAcrossReloadTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    g_freed_images_len = 0;

    // Stand-in for a loaded atlas image; the free func records the GL name
    // instead of calling into GL.
    var images = pixzig.resources.ManagedTextureImage.init(alloc, 500, "test", recordFreedImage);
    defer images.deinit();
    try images.add(.{ .texture = 1, .size = .{ .x = 128, .y = 128 } });
    const image1 = images.get().?;

    var parent = ManagedTexture.init(alloc, 999, "test", noopFreeTexture);
    defer parent.deinit();
    try parent.add(.{
        .texture = 1,
        .size = .{ .x = 128, .y = 128 },
        .src = RectF.fromCoords(0, 0, 128, 128, 128, 128),
        .image = image1,
    });

    // Declared last so its views release their image refs before the
    // image pool is torn down.
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    _ = try rm.addSubTexture(parent.get().?, "frame", RectI.init(0, 0, 8, 8));
    try testz.expectEqual(image1.refCount, 1);

    // A sprite holds the v1 frame.
    const sprite_handle = try rm.acquireTexture("frame");

    // Reload the image. The v1 frame still references image1, so it must
    // survive (previously it was freed here, deleting the GL texture).
    try images.add(.{ .texture = 2, .size = .{ .x = 128, .y = 128 } });
    try testz.expectFalse(imageWasFreed(1));
    try testz.expectTrue(image1.dirty);

    const image2 = images.get().?;
    try parent.add(.{
        .texture = 2,
        .size = .{ .x = 128, .y = 128 },
        .src = RectF.fromCoords(0, 0, 128, 128, 128, 128),
        .image = image2,
    });
    _ = try rm.addSubTexture(parent.get().?, "frame", RectI.init(0, 0, 8, 8));
    try testz.expectFalse(imageWasFreed(1));
    try testz.expectEqual(image2.refCount, 1);
    try testz.expectEqual(sprite_handle.val.texture, 1);

    // Releasing the last stale frame frees the old image, unless stale
    // texture generations are kept for borrowed handles (debug builds), in
    // which case it waits for rm.deinit().
    sprite_handle.release();
    try testz.expectEqual(imageWasFreed(1), !pixzig.resources.keepStaleTextures);
    try testz.expectFalse(imageWasFreed(2));
}

// --- borrowed handles (getTexture / load* / addSubTexture return values) ---

pub fn rmGetTextureIsBorrowedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    const added = try rm.addSubTexture(parent.get().?, "foo", RectI.init(0, 0, 8, 8));
    const borrowed = try rm.getTexture("foo");

    // Neither the add nor the lookup takes a reference.
    try testz.expectEqual(added, borrowed);
    try testz.expectEqual(borrowed.refCount, 0);
}

pub fn rmBorrowedHandleSurvivesReloadInDebugTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    if (!pixzig.resources.keepStaleTextures) return;

    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    const v1 = try rm.addSubTexture(parent.get().?, "foo", RectI.init(0, 0, 8, 8));

    // A sprite retains v1, then the texture reloads and the sprite lets go.
    var spr = pixzig.sprites.Sprite.create(v1);
    const v2 = try rm.addSubTexture(parent.get().?, "foo", RectI.init(8, 0, 8, 8));
    spr.deinit();

    // The borrowed v1 pointer must still be readable (not freed), just stale.
    try testz.expectTrue(v1 != v2);
    try testz.expectTrue(v1.dirty);
    try testz.expectEqual(v1.refCount, 0);
    try testz.expectEqual(v1.val.size.x, 8);
    try testz.expectEqual(try rm.getTexture("foo"), v2);
}

// --- resource names in leak logs ---

pub fn managedResourceCarriesNameTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    const h = try rm.addSubTexture(parent.get().?, "hero_idle", RectI.init(0, 0, 8, 8));
    try testz.expectEqualStr(h.parent.name, "hero_idle");
}
