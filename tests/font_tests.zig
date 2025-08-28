const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

pub fn loadFontTest() !void {
    const font_data = try std.fs.cwd().readFileAlloc(
        std.heap.page_allocator,
        "assets/Roboto-Medium.ttf",
        std.math.maxInt(usize),
    );
    defer std.heap.page_allocator.free(font_data);
    var font_info = pixzig.stb_tt.c.stbtt_fontinfo{};
    _ = pixzig.stb_tt.c.stbtt_InitFont(&font_info, font_data.ptr, 0);
    var w: c_int = 0;
    var h: c_int = 0;
    const bitmap = pixzig.stb_tt.c.stbtt_GetCodepointBitmap(&font_info, 0, pixzig.stb_tt.c.stbtt_ScaleForPixelHeight(&font_info, 15.0), 20, &w, &h, 0, 0);
    const wu: usize = @intCast(w);
    const hu: usize = @intCast(h);
    for (0..hu) |j| {
        for (0..wu) |i| {
            std.debug.print("{c}", .{" .:ioVM@"[bitmap[j * wu + i] >> 5]});
        }
        std.debug.print("\n", .{});
    }
}
