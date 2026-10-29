//! Reading asset files. Every file the engine loads (textures, atlases,
//! fonts, tilemaps, sequences, manifests, Lua scripts, sounds) is read
//! through here rather than straight off the filesystem, because on
//! Android the assets live inside the APK. SDL's file IO reads a relative
//! path from the APK there and from disk everywhere else, so going through
//! SDL makes one code path serve every platform.
//!
//! Paths are taken as given: resolve a game's relative path with
//! `paths.resolve` first, as the loaders do. Writes (saves, screenshots)
//! still go through `std.Io`, since they target a real directory
//! (`platform.prefPath`) on every platform.
//!
//! `vfs` adapts the same IO to miniaudio, whose resource manager otherwise
//! opens sound files itself.

const std = @import("std");
const sdl = @import("sdl3");
const zaudio = @import("zaudio");

/// Reads the whole file at `path` into a buffer the caller owns. Fails with
/// `error.FileNotFound` when SDL can't open it (its reason is logged at
/// debug level, since a caller probing for an optional file expects this).
pub fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return readFileSentinel(alloc, path, null);
}

/// `readFile` with a terminating zero after the data, for parsers that want
/// a C string.
pub fn readFileZ(alloc: std.mem.Allocator, path: []const u8) ![:0]u8 {
    return readFileSentinel(alloc, path, 0);
}

fn readFileSentinel(alloc: std.mem.Allocator, path: []const u8, comptime sentinel: ?u8) !(if (sentinel) |s| [:s]u8 else []u8) {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path_z = std.fmt.bufPrintSentinel(&path_buf, "{s}", .{path}, 0) catch return error.NameTooLong;

    var size: usize = 0;
    const data = sdl.SDL_LoadFile(path_z.ptr, &size) orelse {
        std.log.debug("SDL_LoadFile({s}): {s}", .{ path, sdl.SDL_GetError() });
        return error.FileNotFound;
    };
    defer sdl.SDL_free(data);

    const bytes = @as([*]const u8, @ptrCast(data))[0..size];
    if (sentinel) |s| return alloc.dupeSentinel(u8, bytes, s);
    return alloc.dupe(u8, bytes);
}

/// Whether `path` can be opened for reading.
pub fn exists(path: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path_z = std.fmt.bufPrintSentinel(&path_buf, "{s}", .{path}, 0) catch return false;
    const stream = sdl.SDL_IOFromFile(path_z.ptr, "rb") orelse return false;
    _ = sdl.SDL_CloseIO(stream);
    return true;
}

// ---------------------------------------------------------------------------
// miniaudio VFS
// ---------------------------------------------------------------------------

/// A miniaudio VFS over SDL's file IO, for `Engine.Config.resource_manager_vfs`,
/// so sounds and streamed music load from the APK on Android like every
/// other asset. Read-only: miniaudio never writes through the resource
/// manager's VFS.
pub var vfs: zaudio.Vfs = .{
    .on_open = vfsOpen,
    .on_openw = null,
    .on_close = vfsClose,
    .on_read = vfsRead,
    .on_write = null,
    .on_seek = vfsSeek,
    .on_tell = vfsTell,
    .on_info = vfsInfo,
};

fn streamOf(handle: zaudio.Vfs.FileHandle) *sdl.SDL_IOStream {
    return @ptrCast(@alignCast(handle));
}

fn vfsOpen(_: *zaudio.Vfs, file_path: [*:0]const u8, mode: zaudio.Vfs.OpenMode, handle: *zaudio.Vfs.FileHandle) callconv(.c) zaudio.Result {
    if (mode == .write) return .invalid_operation;
    const stream = sdl.SDL_IOFromFile(file_path, "rb") orelse {
        std.log.debug("SDL_IOFromFile({s}): {s}", .{ file_path, sdl.SDL_GetError() });
        return .does_not_exist;
    };
    handle.* = @ptrCast(stream);
    return .success;
}

fn vfsClose(_: *zaudio.Vfs, handle: zaudio.Vfs.FileHandle) callconv(.c) zaudio.Result {
    return if (sdl.SDL_CloseIO(streamOf(handle))) .success else .io_error;
}

fn vfsRead(_: *zaudio.Vfs, handle: zaudio.Vfs.FileHandle, dst: [*]u8, size: usize, bytes_read: *usize) callconv(.c) zaudio.Result {
    const stream = streamOf(handle);
    const n = sdl.SDL_ReadIO(stream, dst, size);
    bytes_read.* = n;
    if (n == size) return .success;
    // A short read is how the end of the file shows up; miniaudio wants
    // `at_end` for that, and an error only when SDL says one happened.
    return if (sdl.SDL_GetIOStatus(stream) == sdl.SDL_IO_STATUS_EOF or n > 0) .at_end else .io_error;
}

fn vfsSeek(_: *zaudio.Vfs, handle: zaudio.Vfs.FileHandle, offset: i64, origin: zaudio.Vfs.SeekOrigin) callconv(.c) zaudio.Result {
    const whence: sdl.SDL_IOWhence = switch (origin) {
        .start => sdl.SDL_IO_SEEK_SET,
        .current => sdl.SDL_IO_SEEK_CUR,
        .end => sdl.SDL_IO_SEEK_END,
    };
    return if (sdl.SDL_SeekIO(streamOf(handle), offset, whence) >= 0) .success else .io_error;
}

fn vfsTell(_: *zaudio.Vfs, handle: zaudio.Vfs.FileHandle, offset: *i64) callconv(.c) zaudio.Result {
    const pos = sdl.SDL_TellIO(streamOf(handle));
    if (pos < 0) return .io_error;
    offset.* = pos;
    return .success;
}

fn vfsInfo(_: *zaudio.Vfs, handle: zaudio.Vfs.FileHandle, info: *zaudio.Vfs.FileInfo) callconv(.c) zaudio.Result {
    const size = sdl.SDL_GetIOSize(streamOf(handle));
    if (size < 0) return .io_error;
    info.size_in_bytes = @intCast(size);
    return .success;
}
