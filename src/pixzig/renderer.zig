// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl");
const zmath = @import("zmath");
const common = @import("./common.zig");
const textures = @import("./textures.zig");

const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Texture = textures.Texture;

const ShaderCode = [*c]const u8;

pub const VertexShader: ShaderCode =
    \\ #version 330 core
    \\ layout(location = 0) in vec2 coord3d;
    \\ layout(location = 1) in vec2 texcoord;
    \\ // Pass texture coordinate to fragment shader
    \\ out vec2 Texcoord;
    \\ 
    \\ uniform mat4 projectionMatrix;
    \\ 
    \\ void main() {
    \\    gl_Position = projectionMatrix * vec4(coord3d, 0.0, 1.0);
    \\    // Pass texture coordinate to fragment shader
    \\    Texcoord = texcoord;
    \\ }
;

pub const PixelShader: ShaderCode =
    \\ #version 330 core
    \\ in vec2 Texcoord; // Received from vertex shader
    \\ uniform sampler2D tex; // Texture sampler
    \\ out vec4 fragColor;
    \\ void main() {
    \\   // Sample the texture at the given coordinates
    \\   fragColor = texture(tex, Texcoord); 
    \\ }
;

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

const MaxSprites = 1000;
pub const SpriteBatchQueue = struct {
    shaderProgram: u32 = 0,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboTexCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: [2 * 4 * MaxSprites]f32 = undefined,
    texCoords: [2 * 4 * MaxSprites]f32 = undefined,
    indices: [6 * MaxSprites]u16 = undefined,
    allocator: std.mem.Allocator = undefined,

    attrCoord: c_uint = 0,
    attrTexCoord: c_uint = 0,
    uniformMVP: c_int = 0,

    currVert: usize = 0,
    currTexCoord: usize = 0,
    currIdx: usize = 0,
    currNumSprites: usize = 0,

    pub fn init(alloc: std.mem.Allocator, vsCode: ShaderCode, psCode: ShaderCode) !SpriteBatchQueue {
    
        std.debug.print("Creating Shaders...\n", .{});
        const vs = createShader(&vsCode, gl.VERTEX_SHADER) catch |e| {
            return e;
        };
        const ps = createShader(&psCode, gl.FRAGMENT_SHADER) catch |e| {
            return e;
        };
        std.debug.print("Done creating Shaders!\n", .{});

        var batch = SpriteBatchQueue{
            .allocator = alloc
        };

        gl.genVertexArrays(1, &batch.vao);
        gl.bindVertexArray(batch.vao);

        gl.genBuffers(1, &batch.vboVertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &batch.vertices, gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboTexCoords);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &batch.texCoords, gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboIndices);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, batch.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 6 * MaxSprites, &batch.indices, gl.DYNAMIC_DRAW);

        batch.shaderProgram = gl.createProgram();
        gl.attachShader(batch.shaderProgram, vs);
        gl.attachShader(batch.shaderProgram, ps);
        gl.linkProgram(batch.shaderProgram);
        var linkOk: c_int = gl.FALSE;
        gl.getProgramiv(batch.shaderProgram, gl.LINK_STATUS, &linkOk);
        if (linkOk == gl.FALSE) {
            std.debug.print("Error compiling shader program!", .{});
            return error.ShaderCompileError;
        }

        std.debug.print("Created shader program!\n", .{});

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

        batch.attrCoord = @intCast(gl.getAttribLocation(batch.shaderProgram, "coord3d"));
        batch.attrTexCoord = @intCast(gl.getAttribLocation(batch.shaderProgram, "texcoord"));
        batch.uniformMVP = @intCast(gl.getUniformLocation(batch.shaderProgram, "projectionMatrix"));

        return batch;
    }

    pub fn deinit(self: *SpriteBatchQueue) void {
        gl.deleteProgram(self.shaderProgram);
        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboTexCoords);
        gl.deleteBuffers(1, &self.vboIndices);
    }

    pub fn begin(self: *SpriteBatchQueue, mvp: zmath.Mat, texture: *Texture) void {
        gl.useProgram(self.shaderProgram);

        gl.enableVertexAttribArray(self.attrCoord);

        const mvpArr = zmath.matToArr(mvp);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&mvpArr[0]));

        gl.activeTexture(gl.TEXTURE0); // Activate texture unit 0
        gl.bindTexture(gl.TEXTURE_2D, texture.texture); // Bind your texture
        gl.uniform1i(gl.getUniformLocation(self.shaderProgram, "tex"), 0); // Set 'tex' to use texture unit 0

    }

    pub fn drawSprite(self: *SpriteBatchQueue, dest: RectF, srcCoords: RectF) void {
        // const verts = self.vertices[self.currVert..8];
        self.vertices[0] = dest.l;
        self.vertices[1] = dest.b;

        self.vertices[2] = dest.l;
        self.vertices[3] = dest.t;

        self.vertices[4] = dest.r;
        self.vertices[5] = dest.t;

        self.vertices[6] = dest.r;
        self.vertices[7] = dest.b;

        // const texCoords = self.texCoords[self.currTexCoord..8];
        self.texCoords[0] = srcCoords.l;
        self.texCoords[1] = srcCoords.b;

        self.texCoords[2] = srcCoords.l;
        self.texCoords[3] = srcCoords.t;
        
        self.texCoords[4] = srcCoords.r;
        self.texCoords[5] = srcCoords.t;
        
        self.texCoords[6] = srcCoords.r;
        self.texCoords[7] = srcCoords.b;

        // const indices = self.indices[self.currIdx..6];
        const currVertIdx:u16 = @intCast(self.currVert / 2);
        self.indices[0] = currVertIdx+0;
        self.indices[1] = currVertIdx+1;
        self.indices[2] = currVertIdx+2;
        self.indices[3] = currVertIdx+2;
        self.indices[4] = currVertIdx+3;
        self.indices[5] = currVertIdx+0;
        // const verts = self.vertices[self.currVert..8];
        // verts[0] = dest.l;
        // verts[1] = dest.b;
        //
        // verts[2] = dest.l;
        // verts[3] = dest.t;
        //
        // verts[4] = dest.r;
        // verts[5] = dest.t;
        //
        // verts[6] = dest.r;
        // verts[7] = dest.b;
        //
        // const texCoords = self.texCoords[self.currTexCoord..8];
        // texCoords[0] = srcCoords.l;
        // texCoords[1] = srcCoords.b;
        //
        // texCoords[2] = srcCoords.l;
        // texCoords[3] = srcCoords.t;
        // 
        // texCoords[4] = srcCoords.r;
        // texCoords[5] = srcCoords.t;
        // 
        // texCoords[6] = srcCoords.r;
        // texCoords[7] = srcCoords.b;
        //
        // const indices = self.indices[self.currIdx..6];
        // const currVertIdx:u16 = @intCast(self.currVert / 2);
        // indices[0] = currVertIdx+0;
        // indices[1] = currVertIdx+1;
        // indices[2] = currVertIdx+2;
        // indices[3] = currVertIdx+2;
        // indices[4] = currVertIdx+3;
        // indices[5] = currVertIdx+0;

        self.currVert += 8;
        self.currTexCoord += 8;
        self.currIdx += 6;

        self.currNumSprites += 1;
    }

    pub fn end(self: *SpriteBatchQueue) void {
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * self.currNumSprites), &self.vertices, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            // attribute
            self.attrCoord,
            // Num elems per vertex
            2, 
            gl.FLOAT, 
            gl.FALSE,
            // stride
            0, 
            null
        );

        gl.enableVertexAttribArray(self.attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * self.currNumSprites), &self.texCoords, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            // attribute
            self.attrTexCoord,
            // Num elems per vertex
            2, 
            gl.FLOAT, 
            gl.FALSE,
            // stride
            0, 
            null
        );

        // gl.disableVertexAttribArray(buffers.vboTexCoords);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * self.currNumSprites), &self.indices, gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(6*self.currNumSprites), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrTexCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        self.currVert = 0;
        self.currTexCoord = 0;
        self.currIdx = 0;
        self.currNumSprites = 0;
    }
};


pub const Renderer = struct {

};

