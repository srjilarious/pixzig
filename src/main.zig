const std = @import("std");
const gl = @import("zopengl");
const sdl = @import("zsdl");
const stbi = @import("zstbi");

const pixzig = @import("pixzig");
const Flip = pixzig.sprites.Flip;

pub fn main() !void {
    std.log.info("Pixzig Engine test!", .{});
    var eng = try pixzig.PixzigEngine.create("Pixzig Test!", std.heap.page_allocator);
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

    main_loop: while (true) {
        var event: sdl.Event = undefined;
        eng.keyboard.update();
        while (sdl.pollEvent(&event)) {
            if (event.type == .quit) {
                break :main_loop;
            } else if (event.type == .keydown or event.type == .keyup) {
                eng.keyboard.keyEvent(event.key.keysym.sym, event.type == .keydown);
            }
        }

        if (eng.keyboard.down(.escape)) break :main_loop;
        if (eng.keyboard.pressed(.@"1")) fr1.apply(&spr);
        if (eng.keyboard.pressed(.@"2")) fr2.apply(&spr);
        if (eng.keyboard.pressed(.@"3")) fr3.apply(&spr);

        try renderer.setDrawColorRGB(32, 32, 100);
        try renderer.clear();

        try renderer.setDrawColorRGB(128, 10, 10);
        try renderer.fillRect(.{ .x = 50, .y = 50, .w = 300, .h = 300 });

        try spr.draw(renderer);
        renderer.present();
    }
}
