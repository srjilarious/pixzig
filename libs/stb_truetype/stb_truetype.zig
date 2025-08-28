const std = @import("std");

pub const c = @cImport({
    @cInclude("stb_truetype.h");
});
