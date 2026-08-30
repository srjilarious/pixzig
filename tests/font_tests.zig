const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const FontAtlas = pixzig.renderer.FontAtlas;

fn sameGlyph(a: pixzig.renderer.Character, b: pixzig.renderer.Character) bool {
    return a.atlas_pos.x == b.atlas_pos.x and a.atlas_pos.y == b.atlas_pos.y and
        a.size.x == b.size.x and a.size.y == b.size.y and a.advance == b.advance;
}

pub fn loadFontTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = alloc;
    const font_data = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "assets/Roboto-Medium.ttf",
        std.heap.page_allocator,
        .unlimited,
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
        std.log.debug("{}: x0={} x1={} y0={} y1={} xoff={} yoff={} xadvance={}", .{
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

// ---------------------------------------------------------------------------
// Dynamic-codepoint FontAtlas (growing texture, on-demand block loading,
// fallback faces, notdef). These need a GL context, which tests/main.zig
// sets up globally before any test runs.
// ---------------------------------------------------------------------------

pub fn atlasPacksAsciiBlockAtInitTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var atlas = try FontAtlas.initFromTtfFile("assets/Roboto-Medium.ttf", 20.0, alloc);
    defer atlas.deinit();

    // 'A' is a visible glyph with a real advance.
    const a = atlas.getChar('A').?;
    try testz.expectTrue(a.size.x > 0);
    try testz.expectTrue(a.size.y > 0);
    try testz.expectTrue(a.advance > 0);

    // Space has an advance but no bitmap.
    const space = atlas.getChar(' ').?;
    try testz.expectEqual(space.size.x, 0);
    try testz.expectTrue(space.advance > 0);
}

pub fn atlasLoadsNonAsciiBlockOnDemandTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var atlas = try FontAtlas.initFromTtfFile("assets/Roboto-Medium.ttf", 20.0, alloc);
    defer atlas.deinit();

    // Cyrillic capital Zhe (U+0416) lives in block 0x04; Roboto has it.
    try testz.expectFalse(atlas.loaded_blocks.contains(0x04));
    const zhe = atlas.getChar(0x0416).?;
    try testz.expectTrue(zhe.size.x > 0);
    try testz.expectTrue(zhe.advance > 0);
    try testz.expectTrue(atlas.loaded_blocks.contains(0x04));

    // Greek capital Gamma (U+0393), block 0x03.
    const gamma = atlas.getChar(0x0393).?;
    try testz.expectTrue(gamma.size.x > 0);
}

pub fn atlasReturnsNotdefForUncoveredCodepointTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var atlas = try FontAtlas.initFromTtfFile("assets/Roboto-Medium.ttf", 20.0, alloc);
    defer atlas.deinit();

    // CJT ideograph U+4E2D: Roboto has no glyph, so it must resolve to the
    // atlas's notdef box rather than null or an empty glyph.
    const got = atlas.getChar(0x4E2D).?;
    try testz.expectTrue(sameGlyph(got, atlas.notdef));
    try testz.expectTrue(atlas.notdef.size.x > 0);
    try testz.expectTrue(atlas.notdef.size.y > 0);
}

pub fn atlasFallbackFaceFillsGapsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // Primary face only has the digits and '.'; it lacks 'A'.
    var atlas = try FontAtlas.initFromTtfFile("assets/RobotoDigits-subset.ttf", 20.0, alloc);
    defer atlas.deinit();

    const five_before = atlas.getChar('5').?;
    try testz.expectTrue(five_before.size.x > 0);

    // 'A' is missing from the primary -> notdef.
    try testz.expectTrue(sameGlyph(atlas.getChar('A').?, atlas.notdef));

    // Add the full Roboto as a fallback; 'A' now resolves from it.
    try atlas.addFallbackFaceFromFile("assets/Roboto-Medium.ttf", 0, alloc);
    const a_after = atlas.getChar('A').?;
    try testz.expectFalse(sameGlyph(a_after, atlas.notdef));
    try testz.expectTrue(a_after.size.x > 0);
    try testz.expectTrue(a_after.advance > 0);

    // The primary's own digits still resolve from the primary.
    try testz.expectTrue(sameGlyph(atlas.getChar('5').?, five_before));
}

pub fn atlasGrowPreservesGlyphPixelPositionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var atlas = try FontAtlas.initFromTtfFile("assets/Roboto-Medium.ttf", 20.0, alloc);
    defer atlas.deinit();

    const before = atlas.getChar('A').?;
    const dim_before = atlas.dim;
    // A packed glyph's normalized UV is its pixel rect over the atlas edge.
    try testz.expectTrue(@abs(before.coords.l - @as(f32, @floatFromInt(before.atlas_pos.x)) / @as(f32, @floatFromInt(dim_before))) < 0.0001);

    try testz.expectTrue(atlas.grow());
    try testz.expectTrue(atlas.grow());
    atlas.commitTexture();

    const after = atlas.getChar('A').?;
    // Pixel position is unchanged; only the normalization changed.
    try testz.expectEqual(after.atlas_pos.x, before.atlas_pos.x);
    try testz.expectEqual(after.atlas_pos.y, before.atlas_pos.y);
    try testz.expectEqual(atlas.dim, dim_before * 4);
    try testz.expectTrue(@abs(after.coords.l - @as(f32, @floatFromInt(after.atlas_pos.x)) / @as(f32, @floatFromInt(atlas.dim))) < 0.0001);

    // The glyph bitmap itself survived the row-by-row copy into the wider buffer.
    var any_ink = false;
    var yy: i32 = 0;
    while (yy < after.size.y) : (yy += 1) {
        var xx: i32 = 0;
        while (xx < after.size.x) : (xx += 1) {
            const idx: usize = @intCast((after.atlas_pos.y + yy) * atlas.dim + (after.atlas_pos.x + xx));
            if (atlas.pixels[idx] != 0) any_ink = true;
        }
    }
    try testz.expectTrue(any_ink);
}

pub fn atlasSetFontSizeRepacksInPlaceTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var atlas = try FontAtlas.initFromTtfFile("assets/Roboto-Medium.ttf", 16.0, alloc);
    defer atlas.deinit();

    const tex_id = atlas.texture.texture;
    const small_h = atlas.getChar('M').?.size.y;
    const small_adv = atlas.getChar('M').?.advance;

    try atlas.setFontSize(48.0);

    try testz.expectEqual(atlas.font_size, @as(f32, 48.0));
    // Same GL texture object -> a batch holding &atlas.texture stays valid.
    try testz.expectEqual(atlas.texture.texture, tex_id);
    // Glyphs are re-rasterized at the larger size.
    try testz.expectTrue(atlas.getChar('M').?.size.y > small_h);
    try testz.expectTrue(atlas.getChar('M').?.advance > small_adv);

    // And back down again.
    try atlas.setFontSize(10.0);
    try testz.expectEqual(atlas.font_size, @as(f32, 10.0));
    try testz.expectTrue(atlas.getChar('M').?.size.y < small_h);
}

pub fn atlasSetFontSizeKeepsFallbackFacesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // Primary face only has digits and '.'; it lacks 'A'.
    var atlas = try FontAtlas.initFromTtfFile("assets/RobotoDigits-subset.ttf", 20.0, alloc);
    defer atlas.deinit();
    try atlas.addFallbackFaceFromFile("assets/Roboto-Medium.ttf", 0, alloc);
    try testz.expectFalse(sameGlyph(atlas.getChar('A').?, atlas.notdef));

    try atlas.setFontSize(30.0);

    // Rebuilding from the primary file alone would drop the fallback and
    // send 'A' back to notdef; an in-place repack keeps every face.
    try testz.expectFalse(sameGlyph(atlas.getChar('A').?, atlas.notdef));
    try testz.expectTrue(atlas.getChar('A').?.size.x > 0);
    try testz.expectTrue(atlas.getChar('5').?.size.x > 0);
}

pub fn atlasSetFontSizeRejectsBitmapFontTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // A bitmap font goes through zstbi to decode its PNG; outside the
    // engine that has to be initialised by hand.
    pixzig.stbi.init(alloc);
    defer pixzig.stbi.deinit();

    var atlas = try FontAtlas.initFromBitmap(
        "assets/font5r.png",
        16,
        19,
        19,
        "abcdefghijklmnopqrstuvwxyz| 0123456789*#!`:.,\\?-+=$&%()'",
        alloc,
    );
    defer atlas.deinit();

    try testz.expectError(atlas.setFontSize(24.0), error.NotAScalableFont);
}

pub fn atlasFindsFaceIndexByNameTest(io: std.Io, alloc: std.mem.Allocator) !void {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, "assets/Roboto-Medium.ttf", alloc, .unlimited);
    defer alloc.free(data);

    // A plain (non-collection) TTF: face 0 matches its own family name.
    try testz.expectEqual(pixzig.renderer.findFaceIndexByName(data, "Roboto").?, @as(i32, 0));
    try testz.expectTrue(pixzig.renderer.findFaceIndexByName(data, "NoSuchFamilyXYZ") == null);
}
