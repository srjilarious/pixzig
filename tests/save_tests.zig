const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const save = pixzig.save;

const Settings = struct {
    volume: f32 = 0.8,
    name: []const u8 = "player",
    level: u32 = 1,
    keys: []const u8 = "wasd",
};

/// Scratch directories live under the build cache.
const ScratchRoot = ".zig-cache/pixzig-save-tests/";

/// Empties a scratch directory left by an earlier run.
fn clearDir(dir: []const u8) void {
    const io = std.Io.Threaded.global_single_threaded.io();
    std.Io.Dir.cwd().deleteTree(io, dir) catch {};
}

pub fn saveZonRoundTripTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const dir = ScratchRoot ++ "roundtrip";
    clearDir(dir);
    // The parent directories don't exist yet; saveZon creates them.
    const path = dir ++ "/nested/settings.zon";

    try save.saveZon(alloc, path, Settings{ .volume = 0.25, .name = "nate", .level = 7 });

    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();
    const loaded = try save.loadZon(Settings, arena.allocator(), path);
    try testz.expectEqual(loaded.volume, 0.25);
    try testz.expectEqual(loaded.level, 7);
    try testz.expectTrue(std.mem.eql(u8, loaded.name, "nate"));

    // Nothing is left behind from the atomic write.
    const sio = std.Io.Threaded.global_single_threaded.io();
    try testz.expectError(std.Io.Dir.cwd().access(sio, path ++ ".tmp", .{}), error.FileNotFound);
}

pub fn loadZonKeepsDefaultsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const dir = ScratchRoot ++ "defaults";
    clearDir(dir);
    const path = dir ++ "/old.zon";
    // An older save: one known field, plus one this build no longer has.
    try save.writeFileAtomic(alloc, path, ".{ .level = 3, .retired = true }\n");

    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();
    const loaded = try save.loadZon(Settings, arena.allocator(), path);
    try testz.expectEqual(loaded.level, 3);
    try testz.expectEqual(loaded.volume, 0.8);
    try testz.expectTrue(std.mem.eql(u8, loaded.keys, "wasd"));
}

pub fn loadZonMissingFileTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const dir = ScratchRoot ++ "missing";
    clearDir(dir);
    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();
    try testz.expectError(save.loadZon(Settings, arena.allocator(), dir ++ "/none.zon"), error.FileNotFound);
}
