const std = @import("std");
const gl = @import("zopengl");
const sdl = @import("zsdl");
const stbi = @import("zstbi");

const pixzig = @import("pixzig");
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;

pub fn main() !void {
    std.log.info("Pixzig Engine test!", .{});
    var eng = try pixzig.PixzigEngineSdl.create("Pixzig Test!", std.heap.page_allocator);
    defer eng.destroy();

    var renderer = eng.renderer;
    try renderer.setScale(4.0, 4.0);

    const tex = try eng.textures.loadTexture("pacman_sprites", "assets/pac-tiles.png");

    var fr1: Frame = .{ .coords = .{ .x = 96, .y = 48, .w = 16, .h = 16 }, .frameTimeUs = 20000, .flip = Flip.None };
    var fr2: Frame = .{ .coords = .{ .x = 112, .y = 48, .w = 16, .h = 16 }, .frameTimeUs = 20000, .flip = Flip.None };
    var fr3: Frame = .{ .coords = .{ .x = 96, .y = 64, .w = 16, .h = 16 }, .frameTimeUs = 20000, .flip = Flip.None };

    const frseq = try pixzig.sprites.FrameSequence.init("test", std.heap.page_allocator, &[_]Frame{ fr1, fr2, fr3 });

    const fr1_2: Frame = .{ .coords = .{ .x = 96, .y = 48, .w = 16, .h = 16 }, .frameTimeUs = 20000, .flip = Flip.Horz };
    const fr2_2: Frame = .{ .coords = .{ .x = 112, .y = 48, .w = 16, .h = 16 }, .frameTimeUs = 20000, .flip = Flip.Horz };
    const fr3_2: Frame = .{ .coords = .{ .x = 96, .y = 64, .w = 16, .h = 16 }, .frameTimeUs = 20000, .flip = Flip.Horz };

    const frseq_2 = try pixzig.sprites.FrameSequence.init("test", std.heap.page_allocator, &[_]Frame{ fr1_2, fr2_2, fr3_2 });

    var actor = try pixzig.sprites.Actor.init(std.heap.page_allocator);
    _ = try actor.addState(frseq, "right");
    _ = try actor.addState(frseq_2, "left");
    // actor.setState("test");

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
                eng.keyboard.keyEvent(event.key.keysym.scancode, event.type == .keydown);
            }
        }

        if (eng.keyboard.down(.escape)) break :main_loop;
        if (eng.keyboard.pressed(.@"1")) fr1.apply(&spr);
        if (eng.keyboard.pressed(.@"2")) fr2.apply(&spr);
        if (eng.keyboard.pressed(.@"3")) fr3.apply(&spr);
        if (eng.keyboard.pressed(.left)) {
            std.debug.print("Left!\n", .{});
            actor.setState("left");
        }
        if (eng.keyboard.pressed(.right)) {
            std.debug.print("Right!\n", .{});
            actor.setState("right");
        }

        try renderer.setDrawColorRGB(32, 32, 100);
        try renderer.clear();

        try renderer.setDrawColorRGB(128, 10, 10);
        try renderer.fillRect(.{ .x = 50, .y = 50, .w = 300, .h = 300 });

        actor.update(30, &spr);
        try spr.draw(renderer);
        renderer.present();
    }
}