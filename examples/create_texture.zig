// An example of generating a texture from a character buffer with a
// mapping from character to color.  Useful for simple game assets.
const std = @import("std");

const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const math = @import("zmath");

const pixzig = @import("pixzig");
const RectF = pixzig.RectF;
const Color8 = pixzig.Color8;
const EngOptions = pixzig.PixzigEngineOptions;
const CharToColor = pixzig.textures.CharToColor;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Create Texture Example", gpa, EngOptions{});
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

    const tex = try eng.resources.createTextureImageFromChars("test", 8, 8, chars, &[_]CharToColor{
        .{ .char = '#', .color = Color8.from(40, 255, 40, 255) },
        .{ .char = '-', .color = Color8.from(100, 100, 200, 255) },
        .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
        .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
        .{ .char = '@', .color = Color8.from(30, 155, 30, 255) },
        .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
    });

    std.debug.print("Created texture from characters.\n", .{});

    const projMat = math.orthographicOffCenterLhGl(0, 320, 0, 240, -0.1, 1000);

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

        spriteBatch.draw(tex, RectF.fromPosSize(64, 64, 64, 64), RectF.fromCoords(0, 0, 8, 8, 8, 8), .none);
        spriteBatch.draw(tex, RectF.fromPosSize(128, 64, 64, 64), RectF.fromCoords(0, 0, 8, 8, 8, 8), .none);
        spriteBatch.draw(tex, RectF.fromPosSize(192, 64, 64, 64), RectF.fromCoords(0, 0, 8, 8, 8, 8), .none);
        spriteBatch.draw(tex, RectF.fromPosSize(128, 128, 64, 64), RectF.fromCoords(0, 0, 8, 8, 8, 8), .none);
        spriteBatch.end();

        eng.window.swapBuffers();
    }
}
