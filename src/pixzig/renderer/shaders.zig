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

/// The renderer's sprite batch vertex shader (see `SpriteBatch`). Every
/// quad carries a texcoord, a color and a draw mode. Attribute locations are
/// fixed so the batch's vertex layout never needs looking up.
pub const SpriteVertexShader: ShaderCode =
    \\#version 300 es
    \\layout(location = 0) in vec2 coord3d;
    \\layout(location = 1) in vec2 texcoord;
    \\layout(location = 2) in vec4 color;
    \\layout(location = 3) in float mode;
    \\out vec2 Texcoord;
    \\out vec4 Col;
    \\flat out float Mode;
    \\
    \\uniform mat4 projectionMatrix;
    \\
    \\void main() {
    \\    gl_Position = projectionMatrix * vec4(coord3d, 0.0, 1.0);
    \\    Texcoord = texcoord;
    \\    Col = color;
    \\    Mode = mode;
    \\}
;

/// The sprite batch pixel shader. `Mode` is a `DrawMode`: 0 multiplies the
/// texel by the color, 1 uses the texel's red channel as coverage for the
/// color (font atlases), 2 replaces the texel's rgb with the color
/// (blended by its alpha) and keeps the texel's alpha (silhouettes).
pub const SpritePixelShader: ShaderCode =
    \\#version 300 es
    \\precision mediump float;
    \\
    \\in vec2 Texcoord;
    \\in vec4 Col;
    \\flat in float Mode;
    \\uniform sampler2D tex;
    \\out vec4 fragColor;
    \\
    \\void main() {
    \\    vec4 texel = texture(tex, Texcoord);
    \\    if (Mode < 0.5) {
    \\        fragColor = texel * Col;
    \\    } else if (Mode < 1.5) {
    \\        fragColor = vec4(Col.rgb, Col.a * texel.r);
    \\    } else {
    \\        fragColor = vec4(mix(texel.rgb, Col.rgb, Col.a), texel.a);
    \\    }
    \\}
;

/// A 3d vertex shader for arbitrary world-space quads (walls, floors,
/// ceilings), used by Quad3DBatchQueue. Multiplies a true 3d position by
/// the projectionMatrix (expected to be a full view*projection matrix)
/// and passes through the texture coord.
pub const Quad3DVertexShader: ShaderCode =
    \\#version 300 es
    \\in vec3 coord3d;
    \\in vec2 texcoord;
    \\out vec2 Texcoord; // Pass texture coordinate to fragment shader
    \\
    \\uniform mat4 projectionMatrix;
    \\
    \\void main() {
    \\    gl_Position = projectionMatrix * vec4(coord3d, 1.0);
    \\    Texcoord = texcoord; // Pass texture coordinate to fragment shader
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

/// The name for the renderer's sprite batch shader (`SpriteVertexShader` +
/// `SpritePixelShader`), which draws sprites, shapes and text.
pub const SpriteShader = "sprite_shader";

/// Our pixel buffer shader that maps directly to the screen pixels.
pub const PixelBuffShader = "pixel_buffer_shader";

/// The name for our 3d quad shader used by Quad3DBatchQueue.
pub const Quad3DShader = "quad3d_shader";

/// Stores the opengl IDs for the shader program, and vertex/fragment shaders.
pub const Shader = struct {
    program: u32 = 0,
    vertex: u32 = 0,
    fragment: u32 = 0,

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

            gl.deleteShader(res);
            return error.BadShader;
        }

        return res;
    }

    /// Initializes the shader, given pointers to the vertex and fragment
    /// shader source. On failure the GL info log is logged and every GL
    /// object created so far is deleted.
    pub fn init(vs: ShaderCodePtr, fs: ShaderCodePtr) !Shader {
        var shader = Shader{};

        // Compile the vertex and fragment shaders.
        shader.vertex = try compile(vs, gl.VERTEX_SHADER);
        errdefer gl.deleteShader(shader.vertex);
        shader.fragment = try compile(fs, gl.FRAGMENT_SHADER);
        errdefer gl.deleteShader(shader.fragment);

        // Create the shader program and attach our vertex/fragment shaders.
        shader.program = gl.createProgram();
        errdefer gl.deleteProgram(shader.program);
        gl.attachShader(shader.program, shader.vertex);
        gl.attachShader(shader.program, shader.fragment);
        gl.linkProgram(shader.program);

        // Check linking was ok.
        var linkOk: c_int = gl.FALSE;
        gl.getProgramiv(shader.program, gl.LINK_STATUS, &linkOk);
        if (linkOk == gl.FALSE) {
            var logBuffer: [1024]u8 = undefined;
            var length: c_int = 0;
            gl.getProgramInfoLog(shader.program, 1024, &length, &logBuffer);
            std.log.err("Error linking shader program: {s}", .{logBuffer[0..@intCast(length)]});
            return error.ShaderLinkError;
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
