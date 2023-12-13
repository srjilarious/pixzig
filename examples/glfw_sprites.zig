// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
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
//
// const VertexShader: [*c]const u8 =
//     \\ #version 330 core
//     \\ layout(location = 0) in vec2 coord3d;
//     \\ void main(void) {
//     \\   gl_Position = vec4(coord3d.x, coord3d.y, -0.9, 1.0);
//     \\ }
// ;
//
// const PixelShader: [*c]const u8 =
//     \\ #version 330 core
//     \\ out vec4 fragColor;
//     \\ void main(void) {
//     \\   fragColor = vec4(0.8, 0.8, 0.3, 1); 
//     \\ }
// ;

const VertexShader: [*c]const u8 =
    \\ #version 330 core
    \\ layout(location = 0) in vec2 coord3d;
    \\ layout(location = 1) in vec2 texcoord;
    \\ // Pass texture coordinate to fragment shader
    \\ out vec2 Texcoord;
    \\ void main() {
    \\    gl_Position = vec4(coord3d, 0.0, 1.0);
    \\    // Pass texture coordinate to fragment shader
    \\    Texcoord = texcoord;
    \\ }
;

const PixelShader: [*c]const u8 =
    \\ #version 330 core
    \\ in vec2 Texcoord; // Received from vertex shader
    \\ uniform sampler2D tex; // Texture sampler
    \\ out vec4 fragColor;
    \\ void main() {
    \\   // Sample the texture at the given coordinates
    \\   fragColor = texture(tex, Texcoord); 
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

fn createShader(glsl: [*c]const [*c]const u8, shaderType: u32) !u32 {
    const res = gl.createShader(shaderType);
    gl.shaderSource(res, 1, glsl, 0);
    gl.compileShader(res);
    var compileOk: c_int = gl.FALSE;
    gl.getShaderiv(res, gl.COMPILE_STATUS, &compileOk);
    if (compileOk == gl.FALSE) {
        std.debug.print("Error compiling shader!\n", .{});
        return error.BadShader;
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
    const vs = createShader(&VertexShader, gl.VERTEX_SHADER) catch |e| {
        return e;
    };
    const ps = createShader(&PixelShader, gl.FRAGMENT_SHADER) catch |e| {
        return e;
    };
    std.debug.print("Done creating Shaders!\n", .{});

    var texture: c_uint = undefined;
    gl.genTextures(1, &texture);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    // Try to load an image
    var image = try stbi.Image.loadFromFile("assets/mario_grassish2.png", 0);
    defer image.deinit();

    const format = gl.RGBA;
    gl.texImage2D(gl.TEXTURE_2D, 0, format, @intCast(image.width), @intCast(image.height), 0, format, gl.UNSIGNED_BYTE, @ptrCast(image.data));

    var vao: c_uint = undefined;
    gl.genVertexArrays(1, &vao);
    gl.bindVertexArray(vao);

    gl.genBuffers(1, &buffers.vboVertices);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vboVertices);
    gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &buffers.vertices, gl.DYNAMIC_DRAW);

    gl.genBuffers(1, &buffers.vboTexCoords);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vboTexCoords);
    gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &buffers.texCoords, gl.DYNAMIC_DRAW);

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
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.enable(gl.TEXTURE_2D);
    gl.disable(gl.CULL_FACE);
    gl.cullFace(gl.CCW);
    // var attrCoord3d: c_uint = undefined;
    // var attrTexCoord: c_uint = undefined;
    // var uniformMvp: c_uint = undefined;
    // var uniformTexture: c_uint = undefined;

    const attrCoord3d: c_uint = @intCast(gl.getAttribLocation(program, "coord3d"));
    const attrTexCoord: c_uint = @intCast(gl.getAttribLocation(program, "texcoord"));
    std.debug.print("attrCoord3d = {}, attrTexCoord = {}\n", .{ attrCoord3d, attrTexCoord});
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

    buffers.texCoords[0] = 0;
    buffers.texCoords[1] = 1;

    buffers.texCoords[2] = 0;
    buffers.texCoords[3] = 0;
    
    buffers.texCoords[4] = 1;
    buffers.texCoords[5] = 0;
    
    buffers.texCoords[6] = 1;
    buffers.texCoords[7] = 1;

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

        gl.activeTexture(gl.TEXTURE0); // Activate texture unit 0
        gl.bindTexture(gl.TEXTURE_2D, texture); // Bind your texture
        gl.uniform1i(gl.getUniformLocation(program, "tex"), 0); // Set 'tex' to use texture unit 0
        //
        gl.enableVertexAttribArray(attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vboTexCoords); 
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &buffers.texCoords, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            // attribute
            attrTexCoord,
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
        gl.disableVertexAttribArray(attrTexCoord);

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
