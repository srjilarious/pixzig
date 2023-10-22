const std = @import("std");
const gl = @import("zopengl");
const sdl = @import("zsdl");
const stbi = @import("zstbi");

const pixzig = @import("pixzig");
const Flip = pixzig.sprites.Flip;

pub fn main() !void {
    std.log.info("Pixzig Engine test!", .{});
    var eng = try pixzig.create("Pixzig Test!", std.heap.page_allocator);
    defer eng.destroy();

    var renderer = eng.renderer;
    try renderer.setScale(4.0, 4.0);

    var tex = try eng.textures.loadTexture("pacman_sprites", "assets/pac-tiles.png");

    var fr1: pixzig.sprites.Frame = .{ .coords = .{ .x = 96, .y = 48, .w = 16, .h = 16 }, .frameTimeUs = 4000, .flip = Flip.None };
    var fr2: pixzig.sprites.Frame = .{ .coords = .{ .x = 112, .y = 48, .w = 16, .h = 16 }, .frameTimeUs = 4000, .flip = Flip.None };
    var fr3: pixzig.sprites.Frame = .{ .coords = .{ .x = 96, .y = 64, .w = 16, .h = 16 }, .frameTimeUs = 4000, .flip = Flip.None };

    var spr = pixzig.sprites.Sprite.create(tex.texture, sdl.Rect{ .x = 0, .y = 0, .w = 16, .h = 16 });
    spr.setPos(32, 32);
    fr1.apply(&spr);
    fr2.apply(&spr);
    fr3.apply(&spr);
    // // Try to load an image
    // var image = try stbi.Image.loadFromFile("assets/pac-tiles.png", 0);
    // defer image.deinit();
    //
    // std.debug.print("Loaded image, width={}, height={}", .{ image.width, image.height });
    //
    // var surf = try sdl.Surface.createRGBSurfaceFrom(image.data, image.width, image.height, 32, image.width * 4, 0x000000FF, // red mask
    //     0x0000FF00, // green mask
    //     0x00FF0000, // blue mask
    //     0xFF000000 // alpha mask
    // );
    //
    // var tex = try renderer.createTextureFromSurface(surf);
    // surf.free();

    main_loop: while (true) {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == .quit) {
                break :main_loop;
            } else if (event.type == .keydown) {
                if (event.key.keysym.sym == .escape) break :main_loop;
                if (event.key.keysym.sym == .@"1") fr1.apply(&spr);
                if (event.key.keysym.sym == .@"2") fr2.apply(&spr);
                if (event.key.keysym.sym == .@"3") fr3.apply(&spr);
            }
        }

        try renderer.setDrawColorRGB(32, 32, 100);
        try renderer.clear();

        try renderer.setDrawColorRGB(128, 10, 10);
        try renderer.fillRect(.{ .x = 50, .y = 50, .w = 300, .h = 300 });

        // var dest = sdl.Rect{ .x = 120, .y = 80, .w = 128, .h = 128 };
        // try renderer.copy(tex.texture, null, &dest);

        try spr.draw(renderer);
        renderer.present();
    }
}
