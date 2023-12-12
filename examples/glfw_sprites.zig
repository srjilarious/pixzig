// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");

const pixzig = @import("pixzig");
const EngOptions = pixzig.PixzigEngineGlfwOptions;

// const VertexShader: [*c]const u8 =
//     \\ attribute vec3 coord3d;
//     \\ attribute vec2 texcoord;
//     \\ varying vec2 f_texcoord;
//     \\ uniform mat4 mvp;
//     \\ void main(void) {
//     \\   gl_Position = mvp * vec4(coord3d, 1.0);
//     \\   f_texcoord = texcoord;
//     \\ }
// ;

const VertexShader: [*c]const u8 =
    \\ #version 330 core
    \\ layout(location = 0) in vec2 coord3d;
    \\ void main(void) {
    \\   gl_Position = vec4(coord3d.x, coord3d.y, -0.9, 1.0);
    \\ }
;

const PixelShader: [*c]const u8 =
    \\ #version 330 core
    \\ out vec4 fragColor;
    \\ void main(void) {
    \\   fragColor = vec4(0.8, 0.8, 0.3, 1); 
    \\ }
;

const MaxSprites = 100;
const VboBuffers = struct {
    vboVertices: u32 = 0,
    vboTexCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: [2 * 4 * MaxSprites]f32 = undefined,
    texCoords: [2 * 4 * MaxSprites]f32 = undefined,
    indices: [6 * MaxSprites]u16 = undefined,
};

var buffers: VboBuffers = .{};

fn createShader(glsl: [*c]const [*c]const u8, shaderType: u32) u32 {
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

    return res;
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
    const vs = createShader(&VertexShader, gl.VERTEX_SHADER);
    const ps = createShader(&PixelShader, gl.FRAGMENT_SHADER);
    std.debug.print("Done creating Shaders!\n", .{});

    var vao: c_uint = undefined;
    gl.genVertexArrays(1, &vao);
    gl.bindVertexArray(vao);

    gl.genBuffers(1, &buffers.vboVertices);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vboVertices);
    gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &buffers.vertices, gl.DYNAMIC_DRAW);

    // gl.genBuffers(1, &buffers.vboTexCoords);
    // gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vboTexCoords);
    // gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &buffers.texCoords, gl.DYNAMIC_DRAW);

    gl.genBuffers(1, &buffers.vboIndices);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffers.vboIndices);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 6 * MaxSprites, &buffers.indices, gl.DYNAMIC_DRAW);

    const program: c_uint = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, ps);
    gl.linkProgram(program);
    var linkOk: c_int = gl.FALSE;
    gl.getProgramiv(program, gl.LINK_STATUS, &linkOk);
    if (linkOk == gl.FALSE) {
        std.debug.print("Error compiling shader program!", .{});
    }

    std.debug.print("Created shader program!\n", .{});

    // gl.matrixMode(gl.PROJECTION);
    // gl.loadIdentity();

    gl.disable(gl.DEPTH_TEST);
    // gl.enable(gl.BLEND);
    // gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.disable(gl.TEXTURE_2D);
    gl.disable(gl.CULL_FACE);
    gl.cullFace(gl.CCW);
    // var attrCoord3d: c_uint = undefined;
    // var attrTexCoord: c_uint = undefined;
    // var uniformMvp: c_uint = undefined;
    // var uniformTexture: c_uint = undefined;

    const attrCoord3d: c_uint = @intCast(gl.getAttribLocation(program, "coord3d"));
    // const attrTexCoord = gl.getAttribLocation(program, "texcoord");
    // _ = attrTexCoord;
    // const uniformMvp = gl.getAttribLocation(program, "mvp");
    // _ = uniformMvp;
    // const uniformTexture = gl.getAttribLocation(program, "mytexture");
    // _ = uniformTexture;

    const pos: f32 = 0.88;
    buffers.vertices[0] = -pos;
    buffers.vertices[1] = pos;

    buffers.vertices[2] = -pos;
    buffers.vertices[3] = -pos;

    buffers.vertices[4] = pos;
    buffers.vertices[5] = -pos;

    buffers.vertices[6] = pos;
    buffers.vertices[7] = pos;

    buffers.indices[0] = 0;
    buffers.indices[1] = 1;
    buffers.indices[2] = 2;
    buffers.indices[3] = 2;
    buffers.indices[4] = 3;
    buffers.indices[5] = 0;

    // glfw.swapInterval(1);

    std.debug.print("Starting main loop...\n", .{});
    // Main loop
    while (!eng.window.shouldClose() and eng.window.getKey(.escape) != .press) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.1, 0.1, 0.5, 1.0 });
        
        gl.useProgram(program);

        // gl.enableClientState(gl.VERTEX_ARRAY);
        gl.enableVertexAttribArray(attrCoord3d);
        gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vboVertices); 
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &buffers.vertices, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            // attribute
            attrCoord3d,
            // Num elems per vertex
            2, 
            gl.FLOAT, 
            gl.FALSE,
            // stride
            0, 
            null
        );

        // gl.disableVertexAttribArray(buffers.vboTexCoords);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffers.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 6 * MaxSprites, &buffers.indices, gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(attrCoord3d);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0); 
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
    gl.deleteProgram(program);
    gl.deleteBuffers(1, &buffers.vboVertices);
    gl.deleteBuffers(1, &buffers.vboTexCoords);
    gl.deleteBuffers(1, &buffers.vboIndices);
}
