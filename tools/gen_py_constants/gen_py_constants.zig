//! Regenerates `python/pixzig/constants.py` from the engine's own input
//! enums.
//!
//! The Python bindings pass key and button codes across the C ABI as plain
//! ints, so the two sides have to agree on the numbering. These are pixzig's
//! own dense enum values, and this generator is what keeps the copy honest.
//! Run it after adding, removing or reordering anything in
//! `src/pixzig/input/keys.zig`:
//!
//!     zig build py-constants
//!
//! It rewrites the file in place; commit the result.

const std = @import("std");
const pixzig = @import("pixzig");

const keys = pixzig.input.keys;
const MouseAxis = pixzig.input.action.MouseAxis;

const header =
    \\"""Key, mouse, and gamepad codes.
    \\
    \\GENERATED FILE -- do not edit by hand. Regenerate with `zig build
    \\py-constants`, which reads the enums in `src/pixzig/input/keys.zig`.
    \\
    \\The values are pixzig's own dense indices into the engine's
    \\Key/MouseButton/Gamepad enums. They are plain ints under the hood, but
    \\code should always use these names rather than the numbers.
    \\"""
    \\
;

/// Emits one Python class whose members are `Enum`'s fields, uppercased,
/// with their integer values.
fn writeEnum(out: *std.ArrayList(u8), alloc: std.mem.Allocator, comptime name: []const u8, comptime Enum: type) !void {
    try out.appendSlice(alloc, "\n\nclass " ++ name ++ ":\n");
    inline for (@typeInfo(Enum).@"enum".fields) |field| {
        var buf: [64]u8 = undefined;
        const upper = std.ascii.upperString(buf[0..field.name.len], field.name);
        try out.print(alloc, "    {s} = {d}\n", .{ upper, field.value });
    }
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer args.deinit();
    _ = args.next();
    const out_path = args.next() orelse "python/pixzig/constants.py";

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    try out.appendSlice(alloc, header);
    try writeEnum(&out, alloc, "Key", keys.Key);
    try writeEnum(&out, alloc, "MouseButton", keys.MouseButton);
    try writeEnum(&out, alloc, "GamepadButton", keys.GamepadButton);
    try writeEnum(&out, alloc, "GamepadAxis", keys.GamepadAxis);
    try writeEnum(&out, alloc, "MouseAxis", MouseAxis);

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = out.items });
    std.log.info("Wrote {s} ({d} bytes).", .{ out_path, out.items.len });
}
