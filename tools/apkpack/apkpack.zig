//! Adds files to an APK with the alignment Android expects. The Android
//! build (`build/android.zig`) runs it between `aapt2 link` and `apksigner`:
//!
//!     apkpack <in.apk> <out.apk> <entry>=<file>...
//!
//! e.g. `classes.dex=/path/classes.dex lib/arm64-v8a/libmain.so=/path/libmain.so`.
//!
//! Every entry already in `in.apk` is copied over unchanged except for its
//! alignment, and each added file is stored uncompressed. Stored entries
//! start on a 4-byte boundary (what `zipalign 4` does, and what Android 11+
//! insists on for `resources.arsc`), and `.so` files on a 16 KiB one, so
//! the loader can map them straight out of the APK
//! (`extractNativeLibs="false"`) on 4 KiB- and 16 KiB-page devices alike.
//! Doing it here keeps the build off `zip` and `zipalign`.
//!
//! Only what `aapt2` writes is handled: no zip64, no encryption, no
//! multi-disk archives.

const std = @import("std");

const local_sig: u32 = 0x04034b50;
const central_sig: u32 = 0x02014b50;
const end_sig: u32 = 0x06054b50;
const local_header_len = 30;
const central_header_len = 46;
const end_record_len = 22;
/// General purpose flag bit 3: sizes and CRC follow the data in a data
/// descriptor rather than sitting in the local header.
const flag_data_descriptor: u16 = 1 << 3;

const store_alignment = 4;
const so_alignment = 16 * 1024;

/// One entry of the output archive, enough to write its central directory
/// record once all the data is laid out.
const Entry = struct {
    name: []const u8,
    version_made: u16,
    version_needed: u16,
    flags: u16,
    method: u16,
    time: u16,
    date: u16,
    crc: u32,
    compressed_size: u32,
    size: u32,
    external_attrs: u32,
    offset: u32,
};

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer args.deinit();
    _ = args.next();
    const in_path = args.next() orelse return usage();
    const out_path = args.next() orelse return usage();

    const cwd = std.Io.Dir.cwd();
    const input = try cwd.readFileAlloc(io, in_path, alloc, .unlimited);
    defer alloc.free(input);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(alloc);

    try copyEntries(alloc, input, &out, &entries);

    var added: std.ArrayList([]u8) = .empty;
    defer {
        for (added.items) |data| alloc.free(data);
        added.deinit(alloc);
    }
    while (args.next()) |arg| {
        const eq = std.mem.indexOfScalar(u8, arg, '=') orelse return usage();
        const name = arg[0..eq];
        for (entries.items) |e| {
            if (std.mem.eql(u8, e.name, name)) {
                std.log.err("{s} is already in {s}", .{ name, in_path });
                return error.DuplicateEntry;
            }
        }
        const data = try cwd.readFileAlloc(io, arg[eq + 1 ..], alloc, .unlimited);
        try added.append(alloc, data);
        try addStored(alloc, &out, &entries, name, data);
    }

    try writeCentralDirectory(alloc, &out, entries.items);
    try cwd.writeFile(io, .{ .sub_path = out_path, .data = out.items });
}

fn usage() error{Usage} {
    std.log.err("usage: apkpack <in.apk> <out.apk> <entry>=<file>...", .{});
    return error.Usage;
}

fn readInt(comptime T: type, bytes: []const u8, at: usize) !T {
    if (at + @sizeOf(T) > bytes.len) return error.TruncatedZip;
    return std.mem.readInt(T, bytes[at..][0..@sizeOf(T)], .little);
}

/// The alignment an entry's data should start on.
fn alignmentFor(name: []const u8, method: u16) usize {
    if (method != 0) return 1;
    if (std.mem.endsWith(u8, name, ".so")) return so_alignment;
    return store_alignment;
}

/// Copies every entry of `input` into `out`, realigned. Walks the central
/// directory rather than the local headers, since an entry written with a
/// data descriptor has no sizes in its local header.
fn copyEntries(alloc: std.mem.Allocator, input: []const u8, out: *std.ArrayList(u8), entries: *std.ArrayList(Entry)) !void {
    if (input.len < end_record_len) return error.NotAZip;
    // The end record is the last thing in the file, followed only by a
    // comment of up to 64 KiB.
    var end_at: usize = input.len - end_record_len;
    while (try readInt(u32, input, end_at) != end_sig) {
        if (end_at == 0 or input.len - end_at > end_record_len + 0xffff) return error.NotAZip;
        end_at -= 1;
    }
    const count = try readInt(u16, input, end_at + 10);
    var at: usize = try readInt(u32, input, end_at + 16);

    for (0..count) |_| {
        if (try readInt(u32, input, at) != central_sig) return error.BadCentralDirectory;
        const name_len = try readInt(u16, input, at + 28);
        const extra_len = try readInt(u16, input, at + 30);
        const comment_len = try readInt(u16, input, at + 32);
        if (at + central_header_len + name_len > input.len) return error.TruncatedZip;
        var e: Entry = .{
            .name = input[at + central_header_len ..][0..name_len],
            .version_made = try readInt(u16, input, at + 4),
            .version_needed = try readInt(u16, input, at + 6),
            .flags = try readInt(u16, input, at + 8) & ~flag_data_descriptor,
            .method = try readInt(u16, input, at + 10),
            .time = try readInt(u16, input, at + 12),
            .date = try readInt(u16, input, at + 14),
            .crc = try readInt(u32, input, at + 16),
            .compressed_size = try readInt(u32, input, at + 20),
            .size = try readInt(u32, input, at + 24),
            .external_attrs = try readInt(u32, input, at + 38),
            .offset = 0,
        };
        const local_at: usize = try readInt(u32, input, at + 42);
        at += central_header_len + name_len + extra_len + comment_len;

        if (try readInt(u32, input, local_at) != local_sig) return error.BadLocalHeader;
        const local_name_len = try readInt(u16, input, local_at + 26);
        const local_extra_len = try readInt(u16, input, local_at + 28);
        const data_at = local_at + local_header_len + local_name_len + local_extra_len;
        if (data_at + e.compressed_size > input.len) return error.TruncatedZip;

        try writeLocal(alloc, out, &e);
        try out.appendSlice(alloc, input[data_at..][0..e.compressed_size]);
        try entries.append(alloc, e);
    }
}

/// Appends `data` as a new stored entry.
fn addStored(alloc: std.mem.Allocator, out: *std.ArrayList(u8), entries: *std.ArrayList(Entry), name: []const u8, data: []const u8) !void {
    if (data.len > std.math.maxInt(u32)) return error.FileTooLarge;
    var e: Entry = .{
        .name = name,
        .version_made = 20,
        .version_needed = 10,
        .flags = 0,
        .method = 0,
        // 1980-01-01 00:00, zip's epoch: a fixed stamp keeps the APK's
        // bytes the same from one build to the next.
        .time = 0,
        .date = (1 << 5) | 1,
        .crc = std.hash.Crc32.hash(data),
        .compressed_size = @intCast(data.len),
        .size = @intCast(data.len),
        .external_attrs = 0,
        .offset = 0,
    };
    try writeLocal(alloc, out, &e);
    try out.appendSlice(alloc, data);
    try entries.append(alloc, e);
}

/// Writes `e`'s local header at the end of `out`, padding its extra field
/// so the data that follows starts on the entry's alignment, and records
/// where the header went.
fn writeLocal(alloc: std.mem.Allocator, out: *std.ArrayList(u8), e: *Entry) !void {
    if (out.items.len > std.math.maxInt(u32)) return error.ArchiveTooLarge;
    e.offset = @intCast(out.items.len);
    const data_at = out.items.len + local_header_len + e.name.len;
    const alignment = alignmentFor(e.name, e.method);
    const pad = std.mem.alignForward(usize, data_at, alignment) - data_at;

    var header: [local_header_len]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], local_sig, .little);
    std.mem.writeInt(u16, header[4..6], e.version_needed, .little);
    std.mem.writeInt(u16, header[6..8], e.flags, .little);
    std.mem.writeInt(u16, header[8..10], e.method, .little);
    std.mem.writeInt(u16, header[10..12], e.time, .little);
    std.mem.writeInt(u16, header[12..14], e.date, .little);
    std.mem.writeInt(u32, header[14..18], e.crc, .little);
    std.mem.writeInt(u32, header[18..22], e.compressed_size, .little);
    std.mem.writeInt(u32, header[22..26], e.size, .little);
    std.mem.writeInt(u16, header[26..28], @intCast(e.name.len), .little);
    std.mem.writeInt(u16, header[28..30], @intCast(pad), .little);
    try out.appendSlice(alloc, &header);
    try out.appendSlice(alloc, e.name);
    try out.appendNTimes(alloc, 0, pad);
}

fn writeCentralDirectory(alloc: std.mem.Allocator, out: *std.ArrayList(u8), entries: []const Entry) !void {
    const cd_start = out.items.len;
    for (entries) |e| {
        var header: [central_header_len]u8 = @splat(0);
        std.mem.writeInt(u32, header[0..4], central_sig, .little);
        std.mem.writeInt(u16, header[4..6], e.version_made, .little);
        std.mem.writeInt(u16, header[6..8], e.version_needed, .little);
        std.mem.writeInt(u16, header[8..10], e.flags, .little);
        std.mem.writeInt(u16, header[10..12], e.method, .little);
        std.mem.writeInt(u16, header[12..14], e.time, .little);
        std.mem.writeInt(u16, header[14..16], e.date, .little);
        std.mem.writeInt(u32, header[16..20], e.crc, .little);
        std.mem.writeInt(u32, header[20..24], e.compressed_size, .little);
        std.mem.writeInt(u32, header[24..28], e.size, .little);
        std.mem.writeInt(u16, header[28..30], @intCast(e.name.len), .little);
        // Extra field, comment, disk number and internal attributes stay 0.
        std.mem.writeInt(u32, header[38..42], e.external_attrs, .little);
        std.mem.writeInt(u32, header[42..46], e.offset, .little);
        try out.appendSlice(alloc, &header);
        try out.appendSlice(alloc, e.name);
    }
    const cd_len = out.items.len - cd_start;
    if (entries.len > std.math.maxInt(u16) or out.items.len > std.math.maxInt(u32)) return error.ArchiveTooLarge;

    var end: [end_record_len]u8 = @splat(0);
    std.mem.writeInt(u32, end[0..4], end_sig, .little);
    std.mem.writeInt(u16, end[8..10], @intCast(entries.len), .little);
    std.mem.writeInt(u16, end[10..12], @intCast(entries.len), .little);
    std.mem.writeInt(u32, end[12..16], @intCast(cd_len), .little);
    std.mem.writeInt(u32, end[16..20], @intCast(cd_start), .little);
    try out.appendSlice(alloc, &end);
}
