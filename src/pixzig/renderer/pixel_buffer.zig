const std = @import("std");
const gl = @import("zopengl").bindings;
const common = @import("../common.zig");
const Vec2U = common.Vec2U;
const shaders = @import("shaders.zig");
const Shader = shaders.Shader;
const ResourceManager = @import("../resources.zig").ResourceManager;

pub const PixelBuffer = struct {
    texId: c_uint,
    vbo: c_uint,
    shader: *const Shader,
    size: Vec2U,
    pixels: []u8,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        res: *ResourceManager,
        size: Vec2U,
    ) !PixelBuffer {
        var self = PixelBuffer{
            .texId = undefined,
            .vbo = undefined,
            .shader = undefined,
            .size = size,
            .pixels = undefined,
            .allocator = allocator,
        };

        // Allocate pixel buffer (RGB format)
        self.pixels = try allocator.alloc(u8, size.x * size.y * 3);
        @memset(self.pixels, 0);

        // Load the shader
        self.shader = try res.loadShader(
            shaders.PixelBuffShader,
            &shaders.PixBuffVertexShader,
            &shaders.TexPixelShader,
        );

        // Create texture
        gl.genTextures(1, &self.texId);
        gl.bindTexture(gl.TEXTURE_2D, self.texId);

        // Allocate texture storage
        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGB,
            @as(c_int, @intCast(size.x)),
            @as(c_int, @intCast(size.y)),
            0,
            gl.RGB,
            gl.UNSIGNED_BYTE,
            null,
        );

        // Set texture parameters for nearest-neighbor (pixelated) filtering
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        // Create fullscreen triangle vertices
        const vertices = [_]f32{
            -1.0, -1.0, // bottom-left
            1.0,  1.0,
            -1.0, 1.0, // top-left
            -1.0, -1.0,
            1.0,  -1.0,
            1.0,  1.0,
        };

        // Create VBO
        gl.genBuffers(1, &self.vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            vertices.len * @sizeOf(f32),
            &vertices,
            gl.STATIC_DRAW,
        );

        return self;
    }

    pub fn deinit(self: *PixelBuffer) void {
        self.allocator.free(self.pixels);
        gl.deleteTexture(self.texture);
        gl.deleteBuffer(self.vbo);
        gl.deleteProgram(self.shader_program);
    }

    pub fn setPixel(self: *PixelBuffer, x: usize, y: usize, r: u8, g: u8, b: u8) void {
        if (x >= self.size.x or y >= self.size.y) return;
        const index = (y * self.size.x + x) * 3;
        self.pixels[index + 0] = r;
        self.pixels[index + 1] = g;
        self.pixels[index + 2] = b;
    }

    pub fn clear(self: *PixelBuffer, r: u8, g: u8, b: u8) void {
        var i: usize = 0;
        while (i < self.pixels.len) : (i += 3) {
            self.pixels[i + 0] = r;
            self.pixels[i + 1] = g;
            self.pixels[i + 2] = b;
        }
    }

    pub fn render(self: *PixelBuffer) void {
        // Upload pixel data to texture
        gl.bindTexture(gl.TEXTURE_2D, self.texId);
        gl.texSubImage2D(
            gl.TEXTURE_2D,
            0,
            0,
            0,
            @as(c_int, @intCast(self.size.x)),
            @as(c_int, @intCast(self.size.y)),
            gl.RGB,
            gl.UNSIGNED_BYTE,
            self.pixels.ptr,
        );

        // Use shader program
        gl.useProgram(self.shader.program);

        // Bind texture to texture unit 0
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.texId);

        const texture_location = gl.getUniformLocation(self.shader.program, "tex");
        gl.uniform1i(texture_location, 0);

        // Bind vertex buffer and set up vertex attributes
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);

        const position_attrib = gl.getAttribLocation(self.shader.program, "a_pos");
        gl.enableVertexAttribArray(@intCast(position_attrib));
        gl.vertexAttribPointer(
            @intCast(position_attrib),
            2,
            gl.FLOAT,
            gl.FALSE,
            0,
            null,
        );

        // Draw the fullscreen triangle
        gl.drawArrays(gl.TRIANGLES, 0, 6);

        gl.disableVertexAttribArray(@intCast(position_attrib));
    }
};
