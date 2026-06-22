const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const ManagedResource = pixzig.resources.ManagedResource;
const AssetHandle = pixzig.resources.AssetHandle;

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

const IntPool = ManagedResource("IntPool", i32);

// --- add / get / acquire basics ---

pub fn addCreatesFreshHandleTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 7, intFree);
    defer pool.deinit();

    try pool.add(100);
    const h = pool.get().?;
    try testz.expectEqual(h.id, 7);
    try testz.expectEqual(h.generation, 1);
    try testz.expectEqual(h.refCount, 0);
    try testz.expectEqual(h.dirty, false);
    try testz.expectEqual(h.val, 100);
}

pub fn addBumpsGenerationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 1, intFree);
    defer pool.deinit();

    try pool.add(10);
    try testz.expectEqual(pool.get().?.generation, 1);
    try pool.add(20);
    try testz.expectEqual(pool.get().?.generation, 2);
}

pub fn getReturnsNullBeforeAnyAddTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 1, intFree);
    defer pool.deinit();
    try testz.expectEqual(pool.get(), null);
    try testz.expectEqual(pool.acquire(), null);
}

pub fn getReturnsLatestGenerationTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 9, intFree);
    defer pool.deinit();

    try pool.add(100);
    // Hold a ref to v1 so the next add doesn't immediately reclaim it.
    const v1 = pool.acquire().?;
    try pool.add(200);

    const latest = pool.get().?;
    try testz.expectEqual(latest.val, 200);
    try testz.expectEqual(latest.generation, 2);

    pool.release(v1);
}

pub fn acquireBumpsRefCountTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 1, intFree);
    defer pool.deinit();

    try pool.add(42);
    const h = pool.acquire().?;
    try testz.expectEqual(h.refCount, 1);
    const h2 = pool.acquire().?;
    try testz.expectEqual(h2.refCount, 2);
    pool.release(h2);
    pool.release(h);
}

// --- refcount governs lifetime ---

pub fn refCountKeepsHandleAliveAfterUpdateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 5, intFree);
    defer pool.deinit();

    try pool.add(111);
    const old = pool.acquire().?;

    // Add a new version. The old handle is still referenced, so it must
    // NOT be freed; it should only be marked dirty.
    try pool.add(222);

    try testz.expectEqual(wasFreed(111), false);
    try testz.expectEqual(old.dirty, true);
    try testz.expectEqual(old.val, 111);

    // Releasing the last reference on the dirty old handle frees it.
    pool.release(old);
    try testz.expectEqual(wasFreed(111), true);
}

pub fn cleanHandleAtZeroRefCountIsRetainedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 3, intFree);
    defer pool.deinit();

    try pool.add(77);
    const ref = pool.acquire().?;
    pool.release(ref);

    // refCount is now zero but no newer version exists, so the handle
    // remains in the pool and is still discoverable.
    try testz.expectEqual(wasFreed(77), false);
    try testz.expectEqual(pool.get().?.val, 77);
}

pub fn addReclaimsUnreferencedOldVersionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 8, intFree);
    defer pool.deinit();

    try pool.add(1);
    // No one acquired v1; adding v2 should free v1 immediately since
    // nothing references it.
    try pool.add(2);

    try testz.expectEqual(wasFreed(1), true);
    try testz.expectEqual(wasFreed(2), false);
    try testz.expectEqual(pool.get().?.val, 2);
}

// --- dirty propagation ---

pub fn updateMarksOldHandleDirtyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 4, intFree);
    defer pool.deinit();

    try pool.add(10);
    const holder = pool.acquire().?;
    try testz.expectEqual(holder.dirty, false);

    try pool.add(20);
    try testz.expectEqual(holder.dirty, true);

    pool.release(holder);
}

pub fn freshHandleIsNotDirtyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 1, intFree);
    defer pool.deinit();

    try pool.add(100);
    const old = pool.acquire().?;
    try pool.add(200);
    const fresh = pool.get().?;

    try testz.expectEqual(fresh.dirty, false);
    try testz.expectEqual(old.dirty, true);

    pool.release(old);
}

// --- typical hot-reload flow ---

pub fn hotReloadFlowTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 42, intFree);
    defer pool.deinit();

    try pool.add(1);
    var holder = pool.acquire().?;

    // simulated reload
    try pool.add(2);
    try testz.expectEqual(holder.dirty, true);

    // consumer notices, swaps to the new version
    pool.release(holder);
    try testz.expectEqual(wasFreed(1), true);
    holder = pool.acquire().?;
    try testz.expectEqual(holder.val, 2);
    try testz.expectEqual(holder.dirty, false);

    pool.release(holder);
}

// --- slot reuse and pool isolation ---

pub fn freedSlotIsReusedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool = IntPool.init(alloc, 1, intFree);
    defer pool.deinit();

    try pool.add(10);
    try pool.add(11); // reclaims the v1 slot immediately
    try testz.expectEqual(pool.res.items.len, 1);
}

pub fn separatePoolsAreIndependentTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    resetFreed();
    var pool_a = IntPool.init(alloc, 1, intFree);
    defer pool_a.deinit();
    var pool_b = IntPool.init(alloc, 2, intFree);
    defer pool_b.deinit();

    try pool_a.add(100);
    const a = pool_a.acquire().?;

    // An update to pool_b must not mark pool_a's handle dirty or free its
    // value.
    try pool_b.add(200);
    try pool_b.add(201); // forces a reclaim inside pool_b

    try testz.expectEqual(a.dirty, false);
    try testz.expectEqual(wasFreed(100), false);
    try testz.expectEqual(pool_a.get().?.id, 1);
    try testz.expectEqual(pool_b.get().?.id, 2);

    pool_a.release(a);
}
