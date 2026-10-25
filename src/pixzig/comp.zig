//! Comptime helper functions.
const std = @import("std");
const Type = @import("std").builtin.Type;

/// Get the number of fields in an enum type.
pub fn numEnumFields(comptime T: type) usize {
    const info = @typeInfo(T);
    if (info != .@"enum") {
        @compileError("Only works for enums!");
    }
    return info.@"enum".field_names.len;
}

/// Fails compilation unless `T.update` returns `void` or `!void`. Apps used
/// to return `bool` to keep running; that now has to be `eng.quit()`.
pub fn checkUpdateReturn(comptime T: type, comptime what: []const u8) void {
    if (!@hasDecl(T, "update")) return;
    const ret = @typeInfo(@TypeOf(T.update)).@"fn".return_type orelse return;
    const ok = ret == void or switch (@typeInfo(ret)) {
        .error_union => |eu| eu.payload == void,
        else => false,
    };
    if (!ok) {
        @compileError(what ++ " must return void or !void, not " ++ @typeName(ret) ++
            "; call eng.quit() to stop instead of returning false");
    }
}

/// Calls `target.update(eng, deltaMs)`, which returns `void` or `!void`
/// (see `checkUpdateReturn`). An error is logged and quits the engine.
pub fn callUpdate(target: anytype, eng: anytype, deltaMs: f64, comptime what: []const u8) void {
    const T = @typeInfo(@TypeOf(target)).pointer.child;
    const ret = @typeInfo(@TypeOf(T.update)).@"fn".return_type.?;
    if (ret == void) {
        target.update(eng, deltaMs);
    } else if (@typeInfo(ret) == .error_union) {
        target.update(eng, deltaMs) catch |err| {
            std.log.err("{s} failed: {}; quitting", .{ what, err });
            eng.quit();
        };
    } else {
        // Unreachable in a build that compiles: callers run
        // `checkUpdateReturn` up front, which reports the bad return type
        // once. Discarding here keeps that the only error.
        _ = target.update(eng, deltaMs);
    }
}

// Taken from zimpl for testing
// https://github.com/permutationlock/zimpl/blob/8b98b8587846037b5a1037c303603c0d55b6f349/src/zimpl.zig
// pub fn Impl(comptime Ifc: fn (type) type, comptime T: type) type {
//     const U = switch (@typeInfo(T)) {
//         .pointer => |info| if (info.size == .One) info.child else T,
//         else => T,
//     };
//     switch (@typeInfo(U)) {
//         .struct, .union, .enum, .opaque => {},
//         else => return Ifc(T),
//     }
//     var fields = @typeInfo(Ifc(T)).Struct.fields[0..].*;
//     for (&fields) |*field| {
//         if (@hasDecl(U, field.name)) {
//             field.*.default_value = &@as(field.type, @field(U, field.name));
//         }
//     }
//     return @Type(@import("std").builtin.Type{ .Struct = .{
//         .layout = .Auto,
//         .fields = &fields,
//         .decls = &.{},
//         .is_tuple = false,
//     } });
// }
