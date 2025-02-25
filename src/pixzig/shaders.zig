// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");
const common = @import("./common.zig");
const textures = @import("./textures.zig");

const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Color = common.Color;
const Texture = textures.Texture;

pub const ShaderCode = [*c]const u8;
pub const ShaderCodePtr = [*c]const ShaderCode;

pub const TexVertexShader: ShaderCode =
    \\#version 300 es
    \\in vec2 coord3d;
    \\in vec2 texcoord;
    \\out vec2 Texcoord; // Pass texture coordinate to fragment shader
    \\ 
    \\uniform mat4 projectionMatrix;
    \\ 
    \\void main() {
    \\    gl_Position = projectionMatrix * vec4(coord3d, 0.0, 1.0);
    \\    Texcoord = texcoord; // Pass texture coordinate to fragment shader
    \\}
;

pub const TexPixelShader: ShaderCode =
    \\#version 300 es
    \\precision mediump float;
    \\
    \\in vec2 Texcoord; // Received from vertex shader
    \\uniform sampler2D tex; // Texture sampler
    \\out vec4 fragColor;
    \\
    \\void main() {
    \\    fragColor = texture(tex, Texcoord); // Sample the texture at the given coordinates
    \\}
;

pub const ColorVertexShader: ShaderCode =
    \\#version 300 es
    \\in vec2 coord3d;
    \\in vec4 color;
    \\out vec4 Col; // Pass color to fragment shader
    \\
    \\uniform mat4 projectionMatrix;
    \\
    \\void main() {
    \\    gl_Position = projectionMatrix * vec4(coord3d, 0.0, 1.0);
    \\    Col = color; // Pass color to fragment shader
    \\}
;

pub const ColorPixelShader: ShaderCode =
    \\#version 300 es
    \\precision mediump float;
    \\
    \\in vec4 Col; // Received from vertex shader
    \\out vec4 fragColor;
    \\
    \\void main() {
    \\    fragColor = Col; // Output the color
    \\}
;

// pub const TexVertexShader: ShaderCode =
//     \\ #version 330 core
//     \\ layout(location = 0) in vec2 coord3d;
//     \\ layout(location = 1) in vec2 texcoord;
//     \\ // Pass texture coordinate to fragment shader
//     \\ out vec2 Texcoord;
//     \\ 
//     \\ uniform mat4 projectionMatrix;
//     \\ 
//     \\ void main() {
//     \\    gl_Position = projectionMatrix * vec4(coord3d, 0.0, 1.0);
//     \\    // Pass texture coordinate to fragment shader
//     \\    Texcoord = texcoord;
//     \\ }
// ;

// pub const TexPixelShader: ShaderCode =
//     \\ #version 330 core
//     \\ in vec2 Texcoord; // Received from vertex shader
//     \\ uniform sampler2D tex; // Texture sampler
//     \\ out vec4 fragColor;
//     \\ void main() {
//     \\   // Sample the texture at the given coordinates
//     \\   fragColor = texture(tex, Texcoord); 
//     \\ }
// ;

// pub const ColorVertexShader: ShaderCode =
//     \\ #version 330 core
//     \\ layout(location = 0) in vec2 coord3d;
//     \\ layout(location = 1) in vec4 color;
//     \\ // Pass texture coordinate to fragment shader
//     \\ out vec4 Col;
//     \\ 
//     \\ uniform mat4 projectionMatrix;
//     \\ 
//     \\ void main() {
//     \\    gl_Position = projectionMatrix * vec4(coord3d, 0.0, 1.0);
//     \\    // Pass texture coordinate to fragment shader
//     \\    Col = color;
//     \\ }
// ;

// pub const ColorPixelShader: ShaderCode =
//     \\ #version 330 core
//     \\ in vec4 Col; // Received from vertex shader
//     \\ out vec4 fragColor;
//     \\ void main() {
//     \\   // Sample the texture at the given coordinates
//     \\   fragColor = Col; 
//     \\ }
// ;


pub const Shader = struct {
    program: u32 = 0,
    vertex: u32 = 0,
    fragment: u32 = 0,

    fn compile(glsl: ShaderCodePtr, shaderType: u32) !u32 {
        const res = gl.createShader(shaderType);
        gl.shaderSource(res, 1, glsl, 0);
        gl.compileShader(res);
        var compileOk: c_int = gl.FALSE;
        gl.getShaderiv(res, gl.COMPILE_STATUS, &compileOk);
        if (compileOk == gl.FALSE) {
            var logBuffer: [1024]u8 = undefined; // Adjust size as needed
            var length: c_int = 0;
            gl.getShaderInfoLog(res, 1024, &length, &logBuffer);
            std.log.err("Error compiling shader: {s}", .{logBuffer[0..@intCast(length)]});

            return error.BadShader;
        }

        return res;
    }

    pub fn init(vs: ShaderCodePtr, fs: ShaderCodePtr) !Shader {
        var shader = Shader{};

        // Compile the vertex and fragment shaders.
        shader.vertex = try compile(vs, gl.VERTEX_SHADER);
        shader.fragment = try compile(fs, gl.FRAGMENT_SHADER);
        
        // Create the shader program and attach our vertex/fragment shaders.
        shader.program = gl.createProgram();
        gl.attachShader(shader.program, shader.vertex);
        gl.attachShader(shader.program, shader.fragment);
        gl.linkProgram(shader.program);
        
        // Check linking was ok.
        var linkOk: c_int = gl.FALSE;
        gl.getProgramiv(shader.program, gl.LINK_STATUS, &linkOk);
        if (linkOk == gl.FALSE) {
            return error.ShaderCompileError;
        }

        return shader;
    }

    pub fn deinit(self: *Shader) void {
        gl.deleteProgram(self.program);
        gl.deleteShader(self.vertex);
        gl.deleteShader(self.fragment);
    }
};

