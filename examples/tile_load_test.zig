const std = @import("std");
const gl = @import("zopengl");
const sdl = @import("zsdl");
const stbi = @import("zstbi");

const pixzig = @import("pixzig");
const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;

pub fn main() !void {
    std.log.info("Pixzig Engine test!", .{});
    var eng = try pixzig.PixzigEngine.create("Pixzig Test!", std.heap.page_allocator);
    defer eng.destroy();

    var renderer = eng.renderer;
    try renderer.setScale(2.0, 2.0);

    var tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");
    const map = try tile.TileMap.initFromFile("assets/level1a.tmx", std.heap.page_allocator);
    // defer map.deinit();

    var mapRender = try tile.TileMapRenderer.init(std.heap.page_allocator);
    defer mapRender.deinit();

    try mapRender.recreateVertices(&map.tilesets.items[0], &map.layers.items[1]);

    main_loop: while (true) {
        var event: sdl.Event = undefined;
        eng.keyboard.update();
        while (sdl.pollEvent(&event)) {
            if (event.type == .quit) {
                break :main_loop;
            } else if (event.type == .keydown or event.type == .keyup) {
                eng.keyboard.keyEvent(event.key.keysym.scancode, event.type == .keydown);
            }
        }

        // if (eng.keyboard.down(.escape)) break :main_loop;
        // if (eng.keyboard.pressed(.@"1")) fr1.apply(&spr);
        // if (eng.keyboard.pressed(.@"2")) fr2.apply(&spr);
        // if (eng.keyboard.pressed(.@"3")) fr3.apply(&spr);
        // if (eng.keyboard.pressed(.left)) {
        //     std.debug.print("Left!\n", .{});
        //     actor.setState("left");
        // }
        // if (eng.keyboard.pressed(.right)) {
        //     std.debug.print("Right!\n", .{});
        //     actor.setState("right");
        // }

        try renderer.setDrawColorRGB(32, 32, 100);
        try renderer.clear();

        try renderer.setDrawColorRGB(128, 10, 10);
        try renderer.fillRect(.{ .x = 50, .y = 50, .w = 300, .h = 300 });

        try mapRender.draw(renderer, tex.texture, &map.layers.items[0]);

        // actor.update(30, &spr);
        // try spr.draw(renderer);
        renderer.present();
    }
}
