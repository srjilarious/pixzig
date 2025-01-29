const std = @import("std");
const gl = @import("zopengl").bindings;
const glfw = @import("zglfw");
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
    const projMat = math.mul(math.scaling(4.0, 4.0, 1.0), math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000));

    const tex = try eng.textures.loadTexture("pacman_sprites", "assets/pac-tiles.png");

    var texShader = try pixzig.shaders.Shader.init(&pixzig.shaders.TexVertexShader, &pixzig.shaders.TexPixelShader);
    defer texShader.deinit();

    var spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(gpa, &texShader);
    defer spriteBatch.deinit();

    var fr1: Frame = .{ .coords = RectF.fromCoords(96, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .none };
    var fr2: Frame = .{ .coords = RectF.fromCoords(112, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .none };
    var fr3: Frame = .{ .coords = RectF.fromCoords(96, 64, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .none };

    const frseq = try pixzig.sprites.FrameSequence.init("test", gpa, &[_]Frame{ fr1, fr2, fr3 });
    // defer frseq.deinit();

    const fr1_2: Frame = .{ .coords = RectF.fromCoords(96, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .horz };
    const fr2_2: Frame = .{ .coords = RectF.fromCoords(112, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .horz };
    const fr3_2: Frame = .{ .coords = RectF.fromCoords(96, 64, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .horz };

    const frseq_2 = try pixzig.sprites.FrameSequence.init("test_left", gpa, &[_]Frame{ fr1_2, fr2_2, fr3_2 });
    // defer frseq_2.deinit();

    var actor = try pixzig.sprites.Actor.init(gpa);
    defer actor.deinit();
    _ = try actor.addState(frseq, "right");
    _ = try actor.addState(frseq_2, "left");
    // actor.setState("test");

    var spr = pixzig.sprites.Sprite.create(tex, .{ .x = 16, .y = 16 });
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
        spriteBatch.drawSprite(&spr);
        spriteBatch.end();

        if (eng.keyboard.pressed(.one)) fr1.apply(&spr);
        if (eng.keyboard.pressed(.two)) fr2.apply(&spr);
        if (eng.keyboard.pressed(.three)) fr3.apply(&spr);
        if (eng.keyboard.pressed(.up)) {
            spr.rotate = .rot90;
        }
        if (eng.keyboard.pressed(.down)) {
            spr.rotate = .rot270;
        }
        if (eng.keyboard.pressed(.left)) {
            std.debug.print("Left!\n", .{});
            spr.rotate = .flipHorz;
            // actor.setState("left");
        }
        if (eng.keyboard.pressed(.right)) {
            spr.rotate = .none;
            std.debug.print("Right!\n", .{});
            // actor.setState("right");
        }

        eng.window.swapBuffers();
    }
}
