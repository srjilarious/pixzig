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
    // const scale = pixzig.stb_tt.c.stbtt_ScaleForPixelHeight(&font_info, 48.0);
    var w: c_int = 0;
    var h: c_int = 0;
    const bitmap = pixzig.stb_tt.c.stbtt_GetCodepointBitmap(&font_info, 0, pixzig.stb_tt.c.stbtt_ScaleForPixelHeight(&font_info, 32.0), 65, &w, &h, 0, 0);
    const wu: usize = @intCast(w);
    const hu: usize = @intCast(h);
    std.debug.print("\n", .{});
    for (0..hu) |j| {
        for (0..wu) |i| {
            std.debug.print("{c}", .{" .:ioVM@"[bitmap[j * wu + i] >> 5]});
        }
        std.debug.print("\n", .{});
    }

    // Try packing a range into a bitmap
    var pack_context = pixzig.stb_tt.c.stbtt_pack_context{};
    var bitmap_data: [512 * 512]u8 = undefined;
    var packed_chars = [_]pixzig.stb_tt.c.stbtt_packedchar{undefined} ** 95;
    _ = pixzig.stb_tt.c.stbtt_PackBegin(&pack_context, &bitmap_data, 512, 512, 0, 1, null);
    _ = pixzig.stb_tt.c.stbtt_PackFontRange(&pack_context, font_data.ptr, 0, 32.0, 32, 126 - 32, &packed_chars);
    pixzig.stb_tt.c.stbtt_PackEnd(&pack_context);

    for (0..16) |idx| {
        std.debug.print("{}: x0={} x1={} y0={} y1={} xoff={} yoff={} xadvance={}\n", .{
            idx + 32,
            packed_chars[idx].x0,
            packed_chars[idx].x1,
            packed_chars[idx].y0,
            packed_chars[idx].y1,
            packed_chars[idx].xoff,
            packed_chars[idx].yoff,
            packed_chars[idx].xadvance,
        });
    }
}
