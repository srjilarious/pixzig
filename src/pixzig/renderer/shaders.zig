const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");
const common = @import("../common.zig");

const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Color = common.Color;

pub const ShaderCode = [*c]const u8;
pub const ShaderCodePtr = [*c]const ShaderCode;

/// A 2d vertex shader that multiples by the projectionMAtrix and passes
/// through the texture coord.
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

/// A shader that just applies a texture to the fragment.
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

/// A 2d vertex shader that multiples by the projectionMAtrix and passes
/// through the color value.
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

/// A pixel shader that applies the color.
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

/// A pixel shader that applies all white, using red as the alpha channel.
pub const TextPixelShader_Desktop: ShaderCode =
    \\ #version 300 es
    \\ precision mediump float;
    \\ in vec2 Texcoord; // Received from vertex shader
    \\ uniform sampler2D tex; // Texture sampler
    \\ out vec4 fragColor;
    \\ void main() {
    \\   fragColor = vec4(1.0, 1.0, 1.0, texture(tex, Texcoord).r); 
    \\ }
;

/// A web version of the text pixel shader that uses the alpha channel instead of the red channel.
pub const TextPixelShader_Web: ShaderCode =
    \\ #version 300 es
    \\ precision mediump float;
    \\ in vec2 Texcoord; // Received from vertex shader
    \\ uniform sampler2D tex; // Texture sampler
    \\ out vec4 fragColor;
    \\ void main() {
    \\   fragColor = vec4(1.0, 1.0, 1.0, texture(tex, Texcoord).a); 
    \\ }
;

/// A vertex shader that maps the pixel position to the screen position
pub const PixBuffVertexShader: ShaderCode =
    \\#version 300 es
    \\in vec2 a_pos;
    \\out vec2 Texcoord; // Pass texture coordinate to fragment shader
    \\ 
    \\void main() {
    \\    gl_Position = vec4(a_pos, 0.0, 1.0);
    \\    Texcoord = vec2(a_pos.x+1.0, 1.0-a_pos.y)*0.5; // Pass texture coordinate to fragment shader
    \\}
;

/// The name for our color shader
pub const ColorShader = "color_shader";

/// The name for our normal texture shader used for sprites.
pub const TextureShader = "texture_shader";

/// Our text/font shader.
pub const FontShader = "font_shader";

/// Our pixel buffer shader that maps directly to the screen pixels.
pub const PixelBuffShader = "pixel_buffer_shader";

/// Stores the name and opengl IDs for the shader program, and vertex/fragment shaders.
pub const Shader = struct {
    program: u32 = 0,
    vertex: u32 = 0,
    fragment: u32 = 0,
    name: ?[]const u8 = null,

    // Compiles shader source and returns the OpenGL id of it.
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

    /// Initializes the shader, given a pointer to the shader strings, optionally providing the
    /// name for the shader.  If a name is provided it is expected to be managed by the caller.
    pub fn init(vs: ShaderCodePtr, fs: ShaderCodePtr, extra: struct { name: ?[]const u8 = null }) !Shader {
        var shader = Shader{};

        // Compile the vertex and fragment shaders.
        shader.vertex = try compile(vs, gl.VERTEX_SHADER);
        shader.fragment = try compile(fs, gl.FRAGMENT_SHADER);
        if (extra.name != null) {
            shader.name = extra.name;
        }

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

    /// Frees up the OpenGL shader resources.
    pub fn deinit(self: *Shader) void {
        gl.deleteProgram(self.program);
        gl.deleteShader(self.vertex);
        gl.deleteShader(self.fragment);
    }
};
