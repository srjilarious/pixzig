// zig fmt: off
// Natetris: A tetris clone for Nate.

const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import ("zstbi");
const zmath = @import("zmath"); 
const flecs = @import("zflecs"); 
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const Color8 = pixzig.Color8;
const CharToColor = pixzig.textures.CharToColor;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Natetris", gpa, EngOptions{});
    defer eng.deinit();

    std.debug.print("Engine initialized.\n", .{});

    const chars =
        \\=------=
        \\-..####-
        \\-.####=-
        \\-#####=-
        \\-#####=-
        \\-#####=-
        \\-##===@-
        \\=------=
    ;

    const tex = try eng.textures.createTextureFromChars("test", 8, 8, chars, &[_]CharToColor{
        .{ .char = '#', .color = Color8.from(40, 255, 40, 255) },
        .{ .char = '-', .color = Color8.from(100, 100, 200, 255) },
        .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
        .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
        .{ .char = '@', .color = Color8.from(30, 155, 30, 255) },
        .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
    });

    std.debug.print("Created texture from characters.\n", .{});

    const projMat = math.orthographicOffCenterLhGl(0, 640, 0, 480, -0.1, 1000);

    var texShader = try pixzig.shaders.Shader.init(&pixzig.shaders.TexVertexShader, &pixzig.shaders.TexPixelShader);

    var spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(gpa, &texShader);

    while (!eng.window.shouldClose() and eng.window.getKey(.escape) != .press) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0.1, 1.0 });

        // const fb_size = eng.window.getFramebufferSize();
        spriteBatch.begin(projMat);
        // set texture options
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        spriteBatch.drawSprite(tex, RectF.fromPosSize(32, 32, 32, 32), RectF.fromCoords(0, 0, 8, 8, 8, 8));
        spriteBatch.drawSprite(tex, RectF.fromPosSize(64, 32, 32, 32), RectF.fromCoords(0, 0, 8, 8, 8, 8));
        spriteBatch.drawSprite(tex, RectF.fromPosSize(96, 32, 32, 32), RectF.fromCoords(0, 0, 8, 8, 8, 8));
        spriteBatch.drawSprite(tex, RectF.fromPosSize(64, 64, 32, 32), RectF.fromCoords(0, 0, 8, 8, 8, 8));
        spriteBatch.end();

        eng.window.swapBuffers();
    }
}
