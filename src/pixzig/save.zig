//! Save files and settings.
//!
//! Asset paths resolve against the executable (see `paths.zig`), which may
//! be read-only once a game is installed. Saves go in the per-user
//! preference directory instead: `~/.local/share/<app>/` on Linux,
//! `%APPDATA%\<org>\<app>\` on Windows, `~/Library/Application Support/<app>/`
//! on macOS.
//!
//! ```zig
//! const dir = try pixzig.save.prefPath(alloc, "jeffdw", "digcraft");
//! defer alloc.free(dir);
//! const path = try std.fs.path.join(alloc, &.{ dir, "settings.zon" });
//! defer alloc.free(path);
//! try pixzig.save.saveZon(alloc, path, settings);
//! ```

const std = @import("std");
const platform = @import("./platform.zig");

/// The per-user writable directory for `org`/`app`, created if missing and
/// ending in a path separator. Caller owns the returned buffer.
pub fn prefPath(alloc: std.mem.Allocator, org: [:0]const u8, app: [:0]const u8) ![]u8 {
    return platform.prefPath(alloc, org, app);
}

/// Writes `value` as ZON to `path`, creating parent directories. The data
/// goes to `<path>.tmp` first and is then renamed over `path`, so a crash
/// mid-save leaves the previous save intact.
pub fn saveZon(alloc: std.mem.Allocator, path: []const u8, value: anytype) !void {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    try std.zon.stringify.serialize(value, .{}, &out.writer);
    try out.writer.writeByte('\n');
    try writeFileAtomic(alloc, path, out.written());
}

/// Writes `data` to `path` via `<path>.tmp` and a rename, creating parent
/// directories. For save formats that aren't ZON.
pub fn writeFileAtomic(alloc: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(path)) |dir| try cwd.createDirPath(io, dir);

    const tmp = try std.mem.concat(alloc, u8, &.{ path, ".tmp" });
    defer alloc.free(tmp);
    try cwd.writeFile(io, .{ .sub_path = tmp, .data = data });
    try cwd.rename(tmp, cwd, path, io);
}

/// Reads `path` as ZON into a `T`. Fields missing from the file keep their
/// defaults, so a newer build can add settings without breaking old saves;
/// unknown fields are ignored. Slices and strings in the result are
/// allocated in `arena`. Returns `error.FileNotFound` when there is no
/// save yet, and `error.ParseZon` (after logging where) for a bad file.
pub fn loadZon(comptime T: type, arena: std.mem.Allocator, path: []const u8) !T {
    const io = std.Io.Threaded.global_single_threaded.io();
    const source = try std.Io.Dir.cwd().readFileAllocOptions(io, path, arena, .unlimited, .of(u8), 0);

    var diagnostics: std.zon.parse.Diagnostics = undefined;
    return std.zon.parse.fromSlice(T, .{
        .gpa = arena,
        .arena = arena,
        .source = source,
        .diagnostics = &diagnostics,
        .ignore_unknown_fields = true,
    }) catch |err| {
        if (err == error.ParseZon) diagnostics.log(path);
        return err;
    };
}
