// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const Color = pixzig.common.Color;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

pub fn main() !void {

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Glfw Eng Test.", gpa, EngOptions{});
    defer eng.deinit();

    // Orthographic projection matrix
    const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

    // Try to load an image
    const texture = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");

    var spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(
            gpa,
            pixzig.renderer.VertexShader,
            pixzig.renderer.PixelShader
        );
    defer spriteBatch.deinit();

    var shapeBatch = try pixzig.renderer.ShapeBatchQueue.init(
            gpa,
            pixzig.renderer.ColorVertexShader,
            pixzig.renderer.ColorPixelShader
        );
    defer shapeBatch.deinit();

    gl.disable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.enable(gl.TEXTURE_2D);
    gl.disable(gl.CULL_FACE);
    gl.cullFace(gl.CCW);

    const dest = [_]RectF{
        RectF.fromPosSize(10, 10, 32, 32),
        RectF.fromPosSize(200, 50, 32, 32),
        RectF.fromPosSize(566, 300, 32, 32),
    };

    const srcCoords = [_]RectF{
        RectF.fromCoords(32, 32, 32, 32, 512, 512),
        RectF.fromCoords(64, 64, 32, 32, 512, 512),
        RectF.fromCoords(128, 128, 32, 32, 512, 512),
    };

    const destRects = [_]RectF{
        RectF.fromPosSize(50, 40, 32, 64),
        RectF.fromPosSize(220, 80, 64, 32),
        RectF.fromPosSize(540, 316, 128, 128),
    };

    const colorRects = [_]Color{
        Color.from(255, 100, 100, 255),
        Color.from(100, 255, 200, 200),
        Color.from(25, 100, 255, 128),
    };

    std.debug.print("Starting main loop...\n", .{});
    // Main loop
    while (!eng.window.shouldClose() and eng.window.getKey(.escape) != .press) {
        glfw.pollEvents();

        eng.keyboard.update();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.0, 1.0 });
        
        spriteBatch.begin(projMat, texture);
        
        for(0..3) |idx| {
            spriteBatch.drawSprite(dest[idx], srcCoords[idx]);
        }
        spriteBatch.end();
        
        shapeBatch.begin(projMat);
        
        for(0..3) |idx| {
            shapeBatch.drawFilledRect(destRects[idx], colorRects[idx]);
        }
        shapeBatch.end();

        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
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

    std.debug.print("Cleaning up...\n", .{});
}

