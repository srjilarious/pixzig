const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const ManagedResource = pixzig.resources.ManagedResource;
const ManagedTexture = pixzig.resources.ManagedTexture;
const ResourceManager = pixzig.resources.ResourceManager;
const Texture = pixzig.Texture;
const RectF = pixzig.RectF;

// Track which integer values have been freed so tests can assert the
// underlying resource lifecycle.
var g_freed_buf = [_]i32{0} ** 64;
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
    var res = ManagedInt.init(alloc, 7, intFree);
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
    var res = ManagedInt.init(alloc, 1, intFree);
    defer res.deinit();

    try res.add(10);
    try testz.expectEqual(res.get().?.generation, 1);
    try res.add(20);
    try testz.expectEqual(res.get().?.generation, 2);
}

pub fn getReturnsNullBeforeAnyAddTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 1, intFree);
    defer res.deinit();
    try testz.expectEqual(res.get(), null);
    try testz.expectEqual(res.acquire(), null);
}

pub fn getReturnsLatestGenerationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 9, intFree);
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
    var res = ManagedInt.init(alloc, 1, intFree);
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
    var res = ManagedInt.init(alloc, 5, intFree);
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
    var res = ManagedInt.init(alloc, 3, intFree);
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
    var res = ManagedInt.init(alloc, 8, intFree);
    defer res.deinit();

    try res.add(1);
    // No one acquired v1; adding v2 should free v1 immediately since
    // nothing references it.
    try res.add(2);

    try testz.expectEqual(wasFreed(1), true);
    try testz.expectEqual(wasFreed(2), false);
    try testz.expectEqual(res.get().?.val, 2);
}

// --- dirty propagation ---

pub fn updateMarksOldHandleDirtyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res = ManagedInt.init(alloc, 4, intFree);
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
    var res = ManagedInt.init(alloc, 1, intFree);
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
    var res = ManagedInt.init(alloc, 42, intFree);
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
    var res = ManagedInt.init(alloc, 1, intFree);
    defer res.deinit();

    try res.add(10);
    try res.add(11); // reclaims the v1 slot immediately
    try testz.expectEqual(res.res.items.len, 1);
}

pub fn separateressAreIndependentTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var res_a = ManagedInt.init(alloc, 1, intFree);
    defer res_a.deinit();
    var res_b = ManagedInt.init(alloc, 2, intFree);
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
    var m = ManagedTexture.init(alloc, 999, noopFreeTexture);
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
    const sub = try rm.addSubTexture(&parent, "foo", RectF.fromCoords(0, 0, 8, 8, 128, 128));
    try testz.expectEqual(sub.get().?.val.size.x, 8);
    try testz.expectEqual(sub.get().?.val.size.y, 8);

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

    _ = try rm.addSubTexture(&parent, "foo", RectF.fromCoords(0, 0, 8, 8, 128, 128));
    try testz.expectEqual(rm.gid, 1);

    _ = try rm.addSubTexture(&parent, "bar", RectF.fromCoords(0, 0, 8, 8, 128, 128));
    try testz.expectEqual(rm.gid, 2);

    // Reload "foo" reuses the existing res, so gid must not change.
    _ = try rm.addSubTexture(&parent, "foo", RectF.fromCoords(8, 0, 8, 8, 128, 128));
    try testz.expectEqual(rm.gid, 2);
}

pub fn rmAddSubTextureReloadMarksOldHandleDirtyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var rm = ResourceManager.init(alloc);
    defer rm.deinit();

    var parent = try makeDummyParent(alloc);
    defer parent.deinit();
    _ = try rm.addSubTexture(&parent, "foo", RectF.fromCoords(0, 0, 8, 8, 128, 128));

    const res = rm.atlas.get("foo").?;
    const old_handle = res.acquire().?;
    try testz.expectEqual(old_handle.dirty, false);

    _ = try rm.addSubTexture(&parent, "foo", RectF.fromCoords(8, 0, 8, 8, 128, 128));
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
    _ = try rm.addSubTexture(&parent, "foo", RectF.fromCoords(0, 0, 8, 8, 128, 128));

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
    _ = try rm.addSubTexture(&parent, "foo", RectF.fromCoords(0, 0, 8, 8, 128, 128));

    const holder = try rm.acquireTexture("foo");
    try testz.expectEqual(holder.dirty, false);

    _ = try rm.addSubTexture(&parent, "foo", RectF.fromCoords(8, 0, 8, 8, 128, 128));
    try testz.expectEqual(holder.dirty, true);

    // The fresh handle reachable through the helper is the v2 generation.
    const fresh = try rm.acquireTexture("foo");
    try testz.expectEqual(fresh.generation, 2);
    try testz.expectEqual(fresh.dirty, false);

    holder.release();
    fresh.release();
}
