const std = @import("std");
const gl = @import("zopengl").bindings;
const glfw = @import("zglfw");
// const sdl = @import("zsdl");
const stbi = @import("zstbi");

const math = @import("zmath");
const pixzig = @import("pixzig");
const shaders = pixzig.shaders;

const SpriteBatchQueue = pixzig.renderer.SpriteBatchQueue;
const RectF = pixzig.common.RectF;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;

const EngOptions = pixzig.PixzigEngineOptions;

pub fn main() !void {
    std.log.info("Pixzig Engine actor test!", .{});
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Pixzig Actor Test!", gpa, EngOptions{});
    defer eng.deinit();

    // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    // Orthographic projection matrix
    const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

    const tex = try eng.textures.loadTexture("pacman_sprites", "assets/pac-tiles.png");

    var texShader = try pixzig.shaders.Shader.init(&pixzig.shaders.TexVertexShader, &pixzig.shaders.TexPixelShader);
    defer texShader.deinit();

    var spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(gpa, &texShader);
    defer spriteBatch.deinit();

    var fr1: Frame = .{ .coords = RectF.fromCoords(96, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = Flip.None };
    var fr2: Frame = .{ .coords = RectF.fromCoords(112, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = Flip.None };
    var fr3: Frame = .{ .coords = RectF.fromCoords(96, 64, 16, 16, 128, 128), .frameTimeUs = 300, .flip = Flip.None };

    const frseq = try pixzig.sprites.FrameSequence.init("test", gpa, &[_]Frame{ fr1, fr2, fr3 });
    // defer frseq.deinit();

    const fr1_2: Frame = .{ .coords = RectF.fromCoords(96, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = Flip.Horz };
    const fr2_2: Frame = .{ .coords = RectF.fromCoords(112, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = Flip.Horz };
    const fr3_2: Frame = .{ .coords = RectF.fromCoords(96, 64, 16, 16, 128, 128), .frameTimeUs = 300, .flip = Flip.Horz };

    const frseq_2 = try pixzig.sprites.FrameSequence.init("test_left", gpa, &[_]Frame{ fr1_2, fr2_2, fr3_2 });
    // defer frseq_2.deinit();

    var actor = try pixzig.sprites.Actor.init(gpa);
    defer actor.deinit();
    _ = try actor.addState(frseq, "right");
    _ = try actor.addState(frseq_2, "left");
    // actor.setState("test");

    var spr = pixzig.sprites.Sprite.create(tex, .{ .x = 16, .y = 16 }, RectF.fromPosSize(0, 0, 16, 16));
    spr.setPos(32, 32);
    fr1.apply(&spr);
    fr2.apply(&spr);
    fr3.apply(&spr);

    std.debug.print("Starting main loop...\n", .{});
    // Main loop
    while (!eng.window.shouldClose() and eng.window.getKey(.escape) != .press) {
        glfw.pollEvents();

        eng.keyboard.update();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.0, 1.0 });

        spriteBatch.begin(projMat);
        actor.update(30, &spr);
        try spr.draw(&spriteBatch);
        spriteBatch.end();

        if (eng.keyboard.pressed(.one)) fr1.apply(&spr);
        if (eng.keyboard.pressed(.two)) fr2.apply(&spr);
        if (eng.keyboard.pressed(.three)) fr3.apply(&spr);
        if (eng.keyboard.pressed(.left)) {
            std.debug.print("Left!\n", .{});
        }
        if (eng.keyboard.pressed(.right)) {
            std.debug.print("Right!\n", .{});
        }

        // const fb_size = eng.window.getFramebufferSize();
        //
        // zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));
        //
        // // Set the starting window position and size to custom values
        // zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        // zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });
        //
        // if (zgui.begin("My window", .{})) {
        //     if (zgui.button("Press me!", .{ .w = 200.0 })) {
        //         std.debug.print("Button pressed\n", .{});
        //     }
        // }
        // zgui.end();
        //
        // zgui.backend.draw();

        eng.window.swapBuffers();
    }

    // main_loop: while (true) {
    //     var event: sdl.Event = undefined;
    //     // eng.keyboard.update();
    //     while (sdl.pollEvent(&event)) {
    //         if (event.type == .quit) {
    //             break :main_loop;
    //         } else if (event.type == .keydown or event.type == .keyup) {
    //             // eng.keyboard.keyEvent(event.key.keysym.scancode, event.type == .keydown);
    //         }
    //     }
    //
    //     // if (eng.keyboard.down(.escape)) break :main_loop;
    //     // if (eng.keyboard.pressed(.@"1")) fr1.apply(&spr);
    //     // if (eng.keyboard.pressed(.@"2")) fr2.apply(&spr);
    //     // if (eng.keyboard.pressed(.@"3")) fr3.apply(&spr);
    //     // if (eng.keyboard.pressed(.left)) {
    //     //     std.debug.print("Left!\n", .{});
    //     //     actor.setState("left");
    //     // }
    //     // if (eng.keyboard.pressed(.right)) {
    //     //     std.debug.print("Right!\n", .{});
    //     //     actor.setState("right");
    //     // }
    //
    //     try renderer.setDrawColorRGB(32, 32, 100);
    //     try renderer.clear();
    //
    //     try renderer.setDrawColorRGB(128, 10, 10);
    //     try renderer.fillRect(.{ .x = 50, .y = 50, .w = 300, .h = 300 });
    //
    //     actor.update(30, &spr);
    //     try spr.draw(renderer);
    //     renderer.present();
    // }
}
