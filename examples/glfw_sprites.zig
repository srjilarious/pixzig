const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");

const pixzig = @import("pixzig");
const EngOptions = pixzig.PixzigEngineGlfwOptions;

const VertexShader: [*c]const u8 =
    \\ attribute vec3 coord3d;
    \\ attribute vec2 texcoord;
    \\ varying vec2 f_texcoord;
    \\ uniform mat4 mvp;
    \\ void main(void) {
    \\   gl_Position = mvp * vec4(coord3d, 1.0);
    \\   f_texcoord = texcoord;
    \\ }
;

const PixelShader: [*c]const u8 =
    \\ varying vec2 f_texcoord;
    \\ uniform sampler2D mytexture;
    \\ void main(void) {
    \\   vec2 flipped_texcoord = vec2(f_texcoord.x, 1.0 - f_texcoord.y);
    \\   gl_FragColor = texture2D(mytexture, flipped_texcoord);
    \\ }
;

fn createShader(glsl: [*c]const [*c]const u8, shaderType: u32) void {
    const res = gl.createShader(shaderType);
    gl.shaderSource(res, 1, glsl, 0);
    gl.compileShader(res);
    var compileOk: c_int = gl.FALSE;
    gl.getShaderiv(res, gl.COMPILE_STATUS, &compileOk);
    if (compileOk == gl.FALSE) {
        std.debug.print("Error compiling shader!\n", .{});
    } else {
        std.debug.print("Successfully compiled shader!\n", .{});
    }

    // TEST
    // gl.deleteShader(res);
}

pub fn main() !void {
    std.debug.print("\n\nVertexShader\n-----\n{s}\n----\n", .{VertexShader});
    std.debug.print("\n\nPixelShader\n-----\n{s}\n----\n", .{PixelShader});

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngineGlfw.init("Glfw Eng Test.", gpa, EngOptions{});
    defer eng.deinit();

    std.debug.print("Creating Shaders...\n", .{});
    createShader(&VertexShader, gl.VERTEX_SHADER);
    createShader(&PixelShader, gl.FRAGMENT_SHADER);
    std.debug.print("Done creating Shaders!\n", .{});
}
