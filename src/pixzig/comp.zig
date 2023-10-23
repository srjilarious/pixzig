const std = @import("std");

pub fn numEnumFields(comptime T: type) usize {
    comptime var info = @typeInfo(T);
    // if (info.Enum == null) {
    //     @compileError("Only works for enums!");
    // }
    return info.Enum.fields.len;
}
