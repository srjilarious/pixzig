const std = @import("std");
const Type = @import("std").builtin.Type;

pub fn numEnumFields(comptime T: type) usize {
    const info = @typeInfo(T);
    if (info != .@"enum") {
        @compileError("Only works for enums!");
    }
    return info.@"enum".fields.len;
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
