const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const zmath = pixzig.zmath;

const tile = pixzig.tile;
const TileMap = tile.TileMap;
const TileLayer = tile.TileLayer;
const TileSet = tile.TileSet;
const TileMapRenderer = tile.TileMapRenderer;
const RectF = pixzig.RectF;
const GlTestContext = pixzig.internal.GlTestContext;

fn glCtx() *GlTestContext {
    return GlTestContext.get();
}

/// An 800x480 logical screen on a same-size framebuffer.
const test_viewport = pixzig.Viewport.init(.{ .x = 800, .y = 480 }, .{ .x = 800, .y = 480 }, .fit);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn makeLayer(alloc: std.mem.Allocator) !TileLayer {
    return TileLayer.initEmpty(alloc, .{ .x = 4, .y = 4 }, .{ .x = 8, .y = 8 });
}

fn addZProp(alloc: std.mem.Allocator, layer: *TileLayer, z: f32) !void {
    var buf: [32]u8 = undefined;
    const z_str = try std.fmt.bufPrint(&buf, "{d}", .{z});
    const name = try alloc.dupe(u8, "z");
    errdefer alloc.free(name);
    const val = try alloc.dupe(u8, z_str);
    errdefer alloc.free(val);
    try layer.properties.append(alloc, .{ .name = name, .value = val });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

pub fn glContextInitTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    _ = glCtx();
}

pub fn rendererDefaultFontAtlasResizeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{ .textRendering = true });
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();

    var r = try Rndr.init(alloc, &rm, &test_viewport, .{
        .font = .{ .path = .{ .face = "assets/Roboto-Medium.ttf", .size = 18.0 } },
    });
    defer r.deinit();

    const fa = r.defaultFontAtlas() orelse return error.NoDefaultFont;
    try testz.expectEqual(fa.fontSize, @as(f32, 18.0));

    try fa.setFontSize(36.0);
    // Same atlas object the renderer draws from picks up the new size.
    try testz.expectEqual(r.defaultFontAtlas().?.fontSize, @as(f32, 36.0));
}

pub fn rendererDefaultFontAtlasNullWithoutFontTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{ .textRendering = true });
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();

    var r = try Rndr.init(alloc, &rm, &test_viewport, .{ .font = .none });
    defer r.deinit();

    try testz.expectTrue(r.defaultFontAtlas() == null);
}

pub fn rendererWarnsOnceWithNoFontTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{ .textRendering = true });
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();

    var r = try Rndr.init(alloc, &rm, &test_viewport, .{ .font = .none });
    defer r.deinit();

    try testz.expectTrue(!r.testingNoFontWarningIssued());

    // Every text call with no font draws nothing, but only the first one
    // logs -- otherwise a game missing its font floods the log every frame.
    r.begin(.logical);
    const drawn = r.drawString("hello", .{ .x = 0, .y = 0 });
    try testz.expectEqual(drawn.x, 0);
    try testz.expectEqual(drawn.y, 0);
    try testz.expectTrue(r.testingNoFontWarningIssued());
    _ = r.drawText("hello", .{ .x = 0, .y = 0 }, .{ .scale = 2.0 });
    _ = r.drawText("hello", .{ .x = 0, .y = 0 }, .{ .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } });
    _ = r.drawText("hello", .{ .x = 0, .y = 0 }, .{ .clip = .{ .l = 0, .t = 0, .r = 10, .b = 10 } });
    r.end();

    // Measuring with no font reports nothing rather than panicking -- it's
    // reachable from Python (`app.text.measure`), where a panic would take
    // the whole interpreter down.
    const measured = r.measureText("hello", .{});
    try testz.expectEqual(measured.x, 0);
    try testz.expectEqual(measured.y, 0);
    try testz.expectTrue(r.testingNoFontWarningIssued());

    // Setting a font arms the warning again for the next font-less stretch.
    try r.setDefaultFont(&rm, blk: {
        _ = try rm.loadFontFromTtfFile("late", "assets/Roboto-Medium.ttf", 16.0);
        break :blk "late";
    });
    try testz.expectTrue(!r.testingNoFontWarningIssued());
}

pub fn rendererMeasureTextMatchesDrawingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{ .textRendering = true });
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();

    var r = try Rndr.init(alloc, &rm, &test_viewport, .{
        .font = .{ .path = .{ .face = "assets/Roboto-Medium.ttf", .size = 20.0 } },
    });
    defer r.deinit();
    const fa = r.defaultFontAtlas().?;

    // The height is the line box the glyphs are drawn in, not the tallest
    // glyph, so it is the same for "a" and "Ag".
    const small = r.measureText("a", .{});
    const tall = r.measureText("Ag", .{});
    try testz.expectEqual(small.y, @as(f32, @floatFromInt(fa.ascent + fa.descent)));
    try testz.expectEqual(small.y, tall.y);
    try testz.expectTrue(fa.descent > 0);
    try testz.expectEqual(r.lineHeight().?, @as(f32, @floatFromInt(fa.ascent + fa.descent + fa.lineGap)));

    // Scale applies to both axes, and drawing reports what measuring does,
    // whatever the alignment, clip or shadow.
    const doubled = r.measureText("Hello", .{ .scale = 2 });
    const plain = r.measureText("Hello", .{});
    try testz.expectTrue(doubled.x >= plain.x * 2 - 5 and doubled.x <= plain.x * 2);
    r.begin(.logical);
    const drawn = r.drawText("Hello", .{ .x = 400, .y = 10 }, .{
        .scale = 2,
        .@"align" = .center,
        .shadow = .black,
        .clip = RectF.fromPosSize(0, 0, 410, 480),
    });
    r.end();
    try testz.expectEqual(drawn.x, doubled.x);
    try testz.expectEqual(drawn.y, doubled.y);

    // A style can name another font without touching the default.
    const big = try rm.loadFontFromTtfFile("big", "assets/Roboto-Medium.ttf", 40.0);
    const bigSize = r.measureText("Hello", .{ .font = big });
    try testz.expectTrue(bigSize.y > plain.y and bigSize.x > plain.x);
    try testz.expectEqual(r.measureText("Hello", .{}).x, plain.x);
}

pub fn rendererLoadsEmbeddedFontByDefaultTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{});
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();

    // No font option at all: the build-embedded Karla loads at 20px.
    var r = try Rndr.init(alloc, &rm, &test_viewport, .{});
    defer r.deinit();

    const fa = r.defaultFontAtlas() orelse return error.NoDefaultFont;
    try testz.expectEqual(fa.fontSize, @as(f32, 20.0));
    try testz.expectTrue(fa.getChar('A') != null);
}

pub fn rendererLoadsFontFromDataTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{});
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();

    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "assets/Roboto-Medium.ttf", alloc, .unlimited);
    var r = blk: {
        // The atlas copies the bytes, so they can go before the renderer does.
        defer alloc.free(bytes);
        break :blk try Rndr.init(alloc, &rm, &test_viewport, .{ .font = .{ .data = .{ .bytes = bytes, .size = 24.0 } } });
    };
    defer r.deinit();

    const fa = r.defaultFontAtlas() orelse return error.NoDefaultFont;
    try testz.expectEqual(fa.fontSize, @as(f32, 24.0));
    try testz.expectTrue(fa.getChar('A') != null);
}

pub fn spriteBatchSmokeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var shader = try ctx.makeSpriteShaderHandle();
    defer shader.free();

    var batch = try pixzig.renderer.SpriteBatch.init(alloc, &shader);
    defer batch.deinit();

    const mvp = zmath.identity();
    batch.begin(mvp);
    batch.end();
}

pub fn spriteBatchSnapsSpriteToWholePixelsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var shader = try ctx.makeSpriteShaderHandle();
    defer shader.free();
    var tex = ctx.makeDummyTextureHandle();

    var batch = try pixzig.renderer.SpriteBatch.init(alloc, &shader);
    defer batch.deinit();

    var spr = pixzig.sprites.Sprite.create(&tex);
    spr.setSize(10, 10);
    spr.setPosF(3.4, 7.6);

    batch.begin(zmath.identity());
    batch.drawSprite(&spr);

    // Corners are (l,b) (l,t) (r,t) (r,b): top-left rounds to (3, 8) and
    // the 10px size is kept. The sprite's own position stays fractional.
    const v = batch.vertices;
    try testz.expectEqual(v[0].pos[0], @as(f32, 3));
    try testz.expectEqual(v[0].pos[1], @as(f32, 18));
    try testz.expectEqual(v[1].pos[0], @as(f32, 3));
    try testz.expectEqual(v[1].pos[1], @as(f32, 8));
    try testz.expectEqual(v[2].pos[0], @as(f32, 13));
    try testz.expectEqual(spr.pos().x, @as(f32, 3.4));
    batch.end();
}

pub fn spriteBatchQueuesKindsTogetherTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var shader = try ctx.makeSpriteShaderHandle();
    defer shader.free();
    var tex = ctx.makeDummyTextureHandle();
    tex.val.texture = 42;

    var batch = try pixzig.renderer.SpriteBatch.init(alloc, &shader);
    defer batch.deinit();

    var spr = pixzig.sprites.Sprite.create(&tex);
    const red: pixzig.Color = .{ .r = 1, .g = 0, .b = 0, .a = 1 };

    batch.begin(zmath.identity());
    // A plain, a tinted and a filled sprite on one texture share one draw
    // call; only the per-vertex color and mode differ.
    batch.drawSprite(&spr);
    spr.tint = red;
    batch.drawSprite(&spr);
    spr.fill = red;
    batch.drawSprite(&spr);
    try testz.expectEqual(batch.numQuads, 3);
    try testz.expectTrue(std.mem.eql(u8, &batch.vertices[0].color, &.{ 255, 255, 255, 255 }));
    try testz.expectEqual(batch.vertices[0].mode[0], @backingInt(pixzig.renderer.DrawMode.texture));
    try testz.expectTrue(std.mem.eql(u8, &batch.vertices[4].color, &.{ 255, 0, 0, 255 }));
    try testz.expectEqual(batch.vertices[8].mode[0], @backingInt(pixzig.renderer.DrawMode.fill));

    // A shape switches to the white texture, which flushes the sprites
    // first, and later shapes queue behind it.
    batch.drawFilledRect(RectF.fromPosSize(0, 0, 4, 4), red);
    batch.drawRect(RectF.fromPosSize(0, 0, 8, 8), red, 1);
    try testz.expectEqual(batch.texture, batch.whiteTexture);
    try testz.expectEqual(batch.numQuads, 5);
    batch.end();
    try testz.expectEqual(batch.numQuads, 0);
}

pub fn rendererPassesInEveryProjectionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{});
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();

    var r = try Rndr.init(alloc, &rm, &test_viewport, .{});
    defer r.deinit();

    const cam = pixzig.Camera2D.init();
    const projections = [_]pixzig.renderer.Projection{
        .logical,
        .screen,
        .{ .camera = &cam },
        .{ .matrix = zmath.identity() },
    };

    r.clear(0, 0, 51, 255);
    for (projections) |p| {
        r.begin(p);
        r.drawFilledRect(RectF.fromPosSize(10, 10, 20, 20), pixzig.Color.from(255, 0, 0, 255));
        r.setClip(RectF.fromPosSize(0, 0, 100, 100));
        _ = r.drawText("clip", .{ .x = 10, .y = 10 }, .{ .clip = RectF.fromPosSize(0, 0, 100, 100) });
        r.setClip(null);
        r.end();
    }

    try testz.expectTrue(r.lineHeight().? > 0);
}

pub fn tiledReloadAddsLayerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var res = try ctx.makeResourceManager(alloc);
    defer res.deinit();

    // Start with one layer.
    var map1 = try TileMap.init(alloc);
    errdefer map1.deinit();
    try map1.layers.append(alloc, try makeLayer(alloc));
    _ = try res.addTileMap("level", map1);

    var renderer = try TileMapRenderer.init(alloc, &res, "level");
    defer renderer.deinit();

    try testz.expectEqual(renderer.entries.len, 1);

    // Re-registering the same name is what a hot-reload of the .tmx does.
    var map2 = try TileMap.init(alloc);
    errdefer map2.deinit();
    try map2.layers.append(alloc, try makeLayer(alloc));
    try map2.layers.append(alloc, try makeLayer(alloc));
    _ = try res.addTileMap("level", map2);

    try testz.expectTrue(renderer.sync());
    try testz.expectEqual(renderer.entries.len, 2);
}

pub fn tiledReloadRemovesLayerTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var res = try ctx.makeResourceManager(alloc);
    defer res.deinit();

    // Start with two layers.
    var map1 = try TileMap.init(alloc);
    errdefer map1.deinit();
    try map1.layers.append(alloc, try makeLayer(alloc));
    try map1.layers.append(alloc, try makeLayer(alloc));
    _ = try res.addTileMap("level", map1);

    var renderer = try TileMapRenderer.init(alloc, &res, "level");
    defer renderer.deinit();

    try testz.expectEqual(renderer.entries.len, 2);

    // Reload with one layer.
    var map2 = try TileMap.init(alloc);
    errdefer map2.deinit();
    try map2.layers.append(alloc, try makeLayer(alloc));
    _ = try res.addTileMap("level", map2);

    try testz.expectTrue(renderer.sync());
    try testz.expectEqual(renderer.entries.len, 1);
}

pub fn tiledReloadZOrderTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var res = try ctx.makeResourceManager(alloc);
    defer res.deinit();

    // Initial map: both layers at z=0, order by layerIndex.
    var map1 = try TileMap.init(alloc);
    errdefer map1.deinit();
    try map1.layers.append(alloc, try makeLayer(alloc));
    try map1.layers.append(alloc, try makeLayer(alloc));
    _ = try res.addTileMap("level", map1);

    var renderer = try TileMapRenderer.init(alloc, &res, "level");
    defer renderer.deinit();

    // Reload: layer 0 gets z=1, layer 1 stays z=0.
    // After sort, layer 1 (z=0) should be first, layer 0 (z=1) second.
    var map2 = try TileMap.init(alloc);
    errdefer map2.deinit();
    var la = try makeLayer(alloc);
    try addZProp(alloc, &la, 1.0);
    var lb = try makeLayer(alloc);
    try addZProp(alloc, &lb, 0.0);
    try map2.layers.append(alloc, la);
    try map2.layers.append(alloc, lb);
    _ = try res.addTileMap("level", map2);

    try testz.expectTrue(renderer.sync());

    try testz.expectEqual(renderer.entries.len, 2);
    // entries are sorted ascending by z; entry[0] should have z=0, entry[1] z=1.
    try testz.expectEqual(renderer.entries[0].z, @as(f32, 0.0));
    try testz.expectEqual(renderer.entries[1].z, @as(f32, 1.0));
    // Verify original layer indices are tracked correctly.
    try testz.expectEqual(renderer.entries[0].layerIndex, @as(usize, 1));
    try testz.expectEqual(renderer.entries[1].layerIndex, @as(usize, 0));
}

/// A layer whose tileset names its image draws from the texture that image
/// resolves to -- nothing is handed to the renderer but the map's name.
pub fn tiledResolvesTilesetTextureTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var res = try ctx.makeResourceManager(alloc);
    defer res.deinit();

    // A texture already registered under the image's base name is reused
    // rather than read off disk, which is what lets a map built in code name
    // a texture the game loaded itself.
    var pixels = [_]u8{ 255, 255, 255, 255 };
    _ = try res.loadTextureFromBuffer("tiles", 1, 1, pixels[0..]);

    var map = try TileMap.init(alloc);
    errdefer map.deinit();

    var tileset = try TileSet.initEmpty(alloc, .{ .x = 8, .y = 8 }, .{ .x = 32, .y = 32 }, 16);
    tileset.imageSource = try alloc.dupe(u8, "art/tiles.png");
    try map.tilesets.append(alloc, tileset);

    var layer = try makeLayer(alloc);
    layer.tileset = &map.tilesets.items[0];
    try map.layers.append(alloc, layer);
    _ = try res.addTileMap("level", map);

    var renderer = try TileMapRenderer.init(alloc, &res, "level");
    defer renderer.deinit();

    const expected = try res.getTexture("tiles");
    try testz.expectEqual(renderer.entries.len, 1);
    try testz.expectEqual(renderer.entries[0].renderer.texture.?, expected);
}

/// A map name nothing was registered under is an error, not a silent no-op.
pub fn tiledUnknownMapNameFailsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const ctx = glCtx();

    var res = try ctx.makeResourceManager(alloc);
    defer res.deinit();

    try testz.expectError(TileMapRenderer.init(alloc, &res, "nope"), error.NoTileMapWithThatName);
}

pub fn shaderCompileFailureErrorsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    _ = glCtx();

    const shaders = pixzig.shaders;
    const bad: shaders.ShaderCode = "#version 300 es\nnot glsl at all";
    try testz.expectError(shaders.Shader.init(&shaders.TexVertexShader, &bad), error.BadShader);
}

pub fn shaderLinkFailureErrorsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    _ = glCtx();

    // Compiles on its own, but reads Texcoord as a vec3 where the vertex
    // shader writes a vec2, so linking fails.
    const shaders = pixzig.shaders;
    const mismatched: shaders.ShaderCode =
        \\#version 300 es
        \\precision mediump float;
        \\in vec3 Texcoord;
        \\out vec4 fragColor;
        \\void main() { fragColor = vec4(Texcoord, 1.0); }
    ;
    try testz.expectError(shaders.Shader.init(&shaders.TexVertexShader, &mismatched), error.ShaderLinkError);
}

// ---------------------------------------------------------------------------
// Render targets, blend modes, shaders
// ---------------------------------------------------------------------------

const gl = pixzig.gl;
const Color = pixzig.Color;

/// The RGBA bytes at raster pixel (x, y) of the bound framebuffer, counting
/// y down from the top of a target `height` pixels tall.
fn pixelAt(x: i32, y: i32, height: i32) [4]u8 {
    var px: [4]u8 = undefined;
    gl.readPixels(x, height - 1 - y, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, &px);
    return px;
}

fn expectPixel(got: [4]u8, want: [4]u8) !void {
    for (got, want) |g, w| {
        if (@abs(@as(i32, g) - @as(i32, w)) > 2) {
            std.debug.print("pixel {any}, wanted {any}\n", .{ got, want });
            return error.WrongPixel;
        }
    }
}

pub fn renderTargetDrawsUprightTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{ .textRendering = false });
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();
    var r = try Rndr.init(alloc, &rm, &test_viewport, .{ .font = .none });
    defer r.deinit();

    // Half the logical size, so a `.logical` pass is scaled down 2x.
    var target = try pixzig.RenderTarget.init(.{ .x = 400, .y = 240 }, .{});
    defer target.deinit();
    try testz.expectEqual(target.texture.val.src.t, 1);

    r.setTarget(&target);
    try testz.expectTrue(r.currentTarget() == &target);
    r.begin(.logical);
    r.clear(0, 0, 255, 255);
    // Red over the logical top-left 100x100: target pixels 0..50.
    r.drawFilledRect(RectF.fromPosSize(0, 0, 100, 100), Color.red);
    r.end();

    try expectPixel(pixelAt(10, 10, 240), .{ 255, 0, 0, 255 });
    try expectPixel(pixelAt(60, 10, 240), .{ 0, 0, 255, 255 });
    try expectPixel(pixelAt(10, 200, 240), .{ 0, 0, 255, 255 });

    // A `.screen` pass inside a target draws in the target's own pixels.
    r.begin(.screen);
    r.drawFilledRect(RectF.fromPosSize(390, 230, 10, 10), Color.green);
    r.end();
    try expectPixel(pixelAt(395, 235, 240), .{ 0, 255, 0, 255 });

    // A clip in logical coordinates lands on the matching target pixels.
    r.begin(.logical);
    r.setClip(RectF.fromPosSize(400, 0, 400, 480));
    r.drawFilledRect(RectF.fromPosSize(0, 400, 800, 80), Color.white);
    r.setClip(null);
    r.end();
    try expectPixel(pixelAt(150, 220, 240), .{ 0, 0, 255, 255 });
    try expectPixel(pixelAt(250, 220, 240), .{ 255, 255, 255, 255 });

    // Drawn as a texture into another target, it comes out upright: the
    // red corner stays top-left.
    var copy = try pixzig.RenderTarget.init(.{ .x = 400, .y = 240 }, .{});
    defer copy.deinit();
    r.setTarget(&copy);
    r.begin(.screen);
    r.drawTexture(&target.texture, RectF.fromPosSize(0, 0, 400, 240), target.texture.val.src);
    r.end();
    try expectPixel(pixelAt(10, 10, 240), .{ 255, 0, 0, 255 });
    try expectPixel(pixelAt(10, 200, 240), .{ 0, 0, 255, 255 });

    r.setTarget(null);
    try testz.expectTrue(r.currentTarget() == null);

    // Resizing keeps the handle and bumps its version.
    const before = target.texture.version;
    try target.resize(.{ .x = 64, .y = 32 });
    try testz.expectEqual(target.size().x, 64);
    try testz.expectTrue(target.texture.version != before);
    try testz.expectError(target.resize(.{ .x = 0, .y = 32 }), error.InvalidRenderTargetSize);
}

pub fn blendModesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{ .textRendering = false });
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();
    var r = try Rndr.init(alloc, &rm, &test_viewport, .{ .font = .none });
    defer r.deinit();

    var target = try pixzig.RenderTarget.init(.{ .x = 8, .y = 8 }, .{});
    defer target.deinit();
    r.setTarget(&target);
    defer r.setTarget(null);

    const gray = Color.from(100, 100, 100, 255);
    const cases = [_]struct { mode: pixzig.BlendMode, want: u8 }{
        .{ .mode = .alpha, .want = 150 }, // 100 + (200 - 100) / 2
        .{ .mode = .additive, .want = 200 }, // 100 + 200 / 2
        .{ .mode = .multiply, .want = 128 }, // 100 * 200/255 + 100 / 2
        .{ .mode = .premultiplied, .want = 250 }, // 200 + 100 / 2
    };
    for (cases) |c| {
        r.begin(.screen);
        r.clear(100, 100, 100, 255);
        r.drawFilledRect(RectF.fromPosSize(0, 0, 8, 8), gray);
        r.setBlend(c.mode);
        r.drawFilledRect(RectF.fromPosSize(0, 0, 8, 8), Color.from(200, 200, 200, 128));
        r.end();
        const px = pixelAt(4, 4, 8);
        if (@abs(@as(i32, px[0]) - c.want) > 3) {
            std.debug.print("{t}: got {d}, wanted {d}\n", .{ c.mode, px[0], c.want });
            return error.WrongBlend;
        }
    }

    // `begin` puts the mode back to alpha.
    r.begin(.screen);
    r.clear(100, 100, 100, 255);
    r.drawFilledRect(RectF.fromPosSize(0, 0, 8, 8), Color.from(200, 200, 200, 128));
    r.end();
    try testz.expectTrue(@abs(@as(i32, pixelAt(4, 4, 8)[0]) - 150) <= 3);
}

pub fn customShaderAndFadeTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = glCtx();

    const Rndr = pixzig.renderer.Renderer(.{ .textRendering = false });
    var rm = pixzig.resources.ResourceManager.init(alloc);
    defer rm.deinit();
    var r = try Rndr.init(alloc, &rm, &test_viewport, .{ .font = .none });
    defer r.deinit();

    const tinted = try r.createShader(&rm, "tinted",
        \\#version 300 es
        \\precision mediump float;
        \\in vec2 Texcoord;
        \\in vec4 Col;
        \\flat in float Mode;
        \\uniform sampler2D tex;
        \\uniform vec4 tint;
        \\out vec4 fragColor;
        \\void main() { fragColor = texture(tex, Texcoord) * Col * tint; }
    );

    var target = try pixzig.RenderTarget.init(.{ .x = 8, .y = 8 }, .{});
    defer target.deinit();
    r.setTarget(&target);
    defer r.setTarget(null);

    r.begin(.screen);
    r.clear(0, 0, 0, 255);
    r.setShader(tinted);
    r.setUniform("tint", Color.from(0, 255, 0, 255));
    r.drawFilledRect(RectF.fromPosSize(0, 0, 4, 8), Color.white);
    r.setShader(null);
    r.drawFilledRect(RectF.fromPosSize(4, 0, 4, 8), Color.white);
    r.end();
    try expectPixel(pixelAt(1, 4, 8), .{ 0, 255, 0, 255 });
    try expectPixel(pixelAt(6, 4, 8), .{ 255, 255, 255, 255 });

    // A fade covers the (logical) screen, which here is the whole target.
    r.fade(Color.black, 1.0);
    try expectPixel(pixelAt(6, 4, 8), .{ 0, 0, 0, 255 });
    r.fade(Color.white, 0);
    try expectPixel(pixelAt(6, 4, 8), .{ 0, 0, 0, 255 });
}
