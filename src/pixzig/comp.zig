const std = @import("std");

pub fn numEnumFields(comptime T: type) usize {
    const info = @typeInfo(T);
    if (info != .Enum) {
        @compileError("Only works for enums!");
    }
    return info.Enum.fields.len;
}
