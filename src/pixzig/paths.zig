//! Asset path resolution.
//!
//! Every relative path a game hands the engine -- textures, atlases, fonts,
//! tilemaps, sounds, scripts, manifests -- is resolved against the directory
//! the executable lives in (`SDL_GetBasePath`), not the process's current
//! working directory. That way a packaged game finds its assets no matter
//! which directory it was launched from, and `cd` in a shell never changes
//! which files a build loads.
//!
//! Absolute paths are passed through untouched, so a game that computes its
//! own paths (a mod directory, a save folder, a path from a config file)
//! keeps full control.

const std = @import("std");
const platform = @import("./platform.zig");

/// The build's asset base directory, or null to use the executable's own
/// directory. `buildEngine`/`buildGame` generate this module: a dev build
/// points it at the source tree so hot-reload watches the real files, a
/// packaged build leaves it null.
const asset_base: ?[]const u8 = @import("pixzig_asset_base").dir;

/// The directory relative asset paths resolve against: the build's
/// `pixzig_asset_base` when it set one, otherwise the directory holding the
/// running executable (`SDL_GetBasePath`, with a trailing path separator,
/// borrowed from SDL for the life of the process).
///
/// Null under Emscripten, where the virtual filesystem is rooted at `/` and
/// a relative path is already correct as written.
pub fn baseDir() ?[]const u8 {
    return asset_base orelse platform.basePath();
}

/// Resolves `path` to the file the engine should actually open. Caller owns
/// the returned buffer.
pub fn resolve(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return alloc.dupe(u8, path);
    const base = baseDir() orelse return alloc.dupe(u8, path);
    return std.fs.path.join(alloc, &.{ base, path });
}

/// `resolve`, null-terminated for the C libraries the engine hands paths to
/// (stbi, miniaudio, Lua). Caller owns the returned buffer.
pub fn resolveZ(alloc: std.mem.Allocator, path: []const u8) ![:0]u8 {
    if (std.fs.path.isAbsolute(path)) {
        return std.mem.concatWithSentinel(alloc, u8, &.{path}, 0);
    }
    const base = baseDir() orelse return std.mem.concatWithSentinel(alloc, u8, &.{path}, 0);
    return std.fs.path.joinZ(alloc, &.{ base, path });
}
