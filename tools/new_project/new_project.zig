//! Copies `template/`, or a game such as `games/hopper`, into a new game
//! project. Run it through the build:
//!
//!     zig build new -Dname=my_cool_game -Ddest=../my_cool_game
//!     zig build new -Dfrom=games/hopper -Dname=my_platformer
//!
//! The source's package name (`.name` in its `build.zig.zon`: `my_game`
//! for the template) becomes the new name everywhere: in the text of every
//! file and in file and directory names, so `assets/hopper.png` becomes
//! `assets/my_platformer.png` along with every reference to it. Binary
//! files are copied as they are. The `build.zig.zon` gets a fresh
//! fingerprint for the name, and its pixzig dependency path is rewritten to
//! point back at this checkout. Build output and caches (`.zig-cache`,
//! `zig-out`, `zig-pkg`, `__pycache__`) are skipped. It refuses to write
//! into a directory that already exists.
//!
//! Arguments: <source dir> <dest dir> <name> <pixzig root>, all absolute.

const std = @import("std");

const skipped_dirs = [_][]const u8{ ".zig-cache", "zig-out", "zig-pkg", "__pycache__" };

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer args.deinit();
    _ = args.next();
    const template_arg = args.next() orelse return usage();
    const dest_arg = args.next() orelse return usage();
    const name = args.next() orelse return usage();
    const root_arg = args.next() orelse return usage();

    const cwd = std.Io.Dir.cwd();
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_path = cwd_buf[0..try cwd.realPath(io, &cwd_buf)];
    const template_path = try std.fs.path.resolve(alloc, &.{ cwd_path, template_arg });
    defer alloc.free(template_path);
    const dest_path = try std.fs.path.resolve(alloc, &.{ cwd_path, dest_arg });
    defer alloc.free(dest_path);
    const pixzig_root = try std.fs.path.resolve(alloc, &.{ cwd_path, root_arg });
    defer alloc.free(pixzig_root);

    if (!isValidName(name)) {
        std.log.err("'{s}' isn't a valid project name: use letters, digits and '_', not starting with a digit.", .{name});
        return error.InvalidName;
    }

    if (cwd.access(io, dest_path, .{})) |_| {
        std.log.err("{s} already exists; pick a new -Ddest.", .{dest_path});
        return error.DestinationExists;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    // Relative, so the new project keeps building if both trees move together.
    const dep_path = try std.fs.path.relativeAlloc(alloc, dest_path, null, dest_path, pixzig_root);
    defer alloc.free(dep_path);

    var template_dir = try cwd.openDir(io, template_path, .{ .iterate = true });
    defer template_dir.close(io);

    const template_zon = try template_dir.readFileAlloc(io, "build.zig.zon", alloc, .limited(1024 * 1024));
    defer alloc.free(template_zon);
    const template_name = packageName(template_zon) orelse {
        std.log.err("{s}/build.zig.zon has no `.name = .something` line.", .{template_path});
        return error.NoPackageName;
    };
    try cwd.createDirPath(io, dest_path);
    var dest_dir = try cwd.openDir(io, dest_path, .{});
    defer dest_dir.close(io);

    var walker = try template_dir.walkSelectively(alloc);
    defer walker.deinit();
    var file_count: usize = 0;
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                if (isSkipped(entry.basename)) continue;
                const dir_path = try std.mem.replaceOwned(u8, alloc, entry.path, template_name, name);
                defer alloc.free(dir_path);
                try dest_dir.createDirPath(io, dir_path);
                try walker.enter(io, entry);
            },
            .file => {
                const contents = try template_dir.readFileAlloc(io, entry.path, alloc, .limited(16 * 1024 * 1024));
                defer alloc.free(contents);

                // Images and other binary files are copied as they are.
                const is_binary = std.mem.indexOfScalar(u8, contents, 0) != null;
                const out = if (std.mem.eql(u8, entry.path, "build.zig.zon"))
                    try rewriteZon(alloc, io, contents, name, dep_path)
                else if (is_binary)
                    try alloc.dupe(u8, contents)
                else
                    try std.mem.replaceOwned(u8, alloc, contents, template_name, name);
                defer alloc.free(out);

                const out_path = try std.mem.replaceOwned(u8, alloc, entry.path, template_name, name);
                defer alloc.free(out_path);
                try dest_dir.writeFile(io, .{ .sub_path = out_path, .data = out });
                file_count += 1;
            },
            else => {},
        }
    }

    std.log.info("Created {s} ({d} files). Build and run it with:", .{ dest_path, file_count });
    std.log.info("    cd {s} && zig build {s}", .{ dest_path, name });
}

fn usage() error{BadArgs} {
    std.log.err("usage: new_project <source dir> <dest dir> <name> <pixzig root>", .{});
    return error.BadArgs;
}

fn isSkipped(basename: []const u8) bool {
    for (skipped_dirs) |dir| {
        if (std.mem.eql(u8, basename, dir)) return true;
    }
    return false;
}

/// A name usable both as the `.name = .x` enum literal in `build.zig.zon`
/// and as an executable name.
fn isValidName(name: []const u8) bool {
    if (name.len == 0 or std.ascii.isDigit(name[0])) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }
    return true;
}

/// The `x` in a `build.zig.zon`'s `.name = .x,` line.
fn packageName(zon: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, zon, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        const prefix = ".name = .";
        if (!std.mem.startsWith(u8, trimmed, prefix)) continue;
        const rest = trimmed[prefix.len..];
        const end = std.mem.indexOfAny(u8, rest, ", ") orelse rest.len;
        if (end == 0) return null;
        return rest[0..end];
    }
    return null;
}

/// Renames the package, gives it a fingerprint that matches the new name,
/// and points its pixzig dependency at `dep_path`.
fn rewriteZon(alloc: std.mem.Allocator, io: std.Io, contents: []const u8, name: []const u8, dep_path: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(alloc, '\n');
        first = false;

        const trimmed = std.mem.trimStart(u8, line, " ");
        const indent = line[0 .. line.len - trimmed.len];
        if (std.mem.startsWith(u8, trimmed, ".name = .")) {
            try out.print(alloc, "{s}.name = .{s},", .{ indent, name });
        } else if (std.mem.startsWith(u8, trimmed, ".fingerprint = ")) {
            try out.print(alloc, "{s}.fingerprint = 0x{x},", .{ indent, fingerprint(io, name) });
        } else if (std.mem.startsWith(u8, trimmed, ".path = \"")) {
            // The source's only path dependency is pixzig.
            try out.print(alloc, "{s}.path = \"{f}\",", .{ indent, std.zig.fmtString(dep_path) });
        } else {
            try out.appendSlice(alloc, line);
        }
    }
    return out.toOwnedSlice(alloc);
}

/// A package fingerprint: a random id in the low 32 bits and the CRC32 of the
/// package name in the high 32, which is what zig checks it against.
fn fingerprint(io: std.Io, name: []const u8) u64 {
    var id: u32 = 0;
    while (id == 0 or id == std.math.maxInt(u32)) {
        var bytes: [4]u8 = undefined;
        io.random(&bytes);
        id = std.mem.readInt(u32, &bytes, .little);
    }
    return (@as(u64, std.hash.Crc32.hash(name)) << 32) | id;
}
