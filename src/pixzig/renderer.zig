// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl");
const zmath = @import("zmath");
const common = @import("./common.zig");
const textures = @import("./textures.zig");

const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Color = common.Color;
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

pub const ColorVertexShader: ShaderCode =
    \\ #version 330 core
    \\ layout(location = 0) in vec2 coord3d;
    \\ layout(location = 1) in vec4 color;
    \\ // Pass texture coordinate to fragment shader
    \\ out vec4 Col;
    \\ 
    \\ uniform mat4 projectionMatrix;
    \\ 
    \\ void main() {
    \\    gl_Position = projectionMatrix * vec4(coord3d, 0.0, 1.0);
    \\    // Pass texture coordinate to fragment shader
    \\    Col = color;
    \\ }
;

pub const ColorPixelShader: ShaderCode =
    \\ #version 330 core
    \\ in vec4 Col; // Received from vertex shader
    \\ out vec4 fragColor;
    \\ void main() {
    \\   // Sample the texture at the given coordinates
    \\   fragColor = Col; 
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

    mvpArr: [16]f32 = undefined,
    texture: *Texture = undefined,

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
        self.mvpArr = zmath.matToArr(mvp);
        self.texture = texture;
    }

    pub fn drawSprite(self: *SpriteBatchQueue, dest: RectF, srcCoords: RectF) void {
        const verts = self.vertices[self.currVert..self.currVert+8];
        verts[0] = dest.l;
        verts[1] = dest.b;

        verts[2] = dest.l;
        verts[3] = dest.t;

        verts[4] = dest.r;
        verts[5] = dest.t;

        verts[6] = dest.r;
        verts[7] = dest.b;

        const texCoords = self.texCoords[self.currTexCoord..self.currTexCoord+8];
        texCoords[0] = srcCoords.l;
        texCoords[1] = srcCoords.b;

        texCoords[2] = srcCoords.l;
        texCoords[3] = srcCoords.t;
        
        texCoords[4] = srcCoords.r;
        texCoords[5] = srcCoords.t;
        
        texCoords[6] = srcCoords.r;
        texCoords[7] = srcCoords.b;

        const indices = self.indices[self.currIdx..self.currIdx+6];
        const currVertIdx: u16 = @intCast(self.currVert / 2);
        indices[0] = currVertIdx+0;
        indices[1] = currVertIdx+1;
        indices[2] = currVertIdx+2;
        indices[3] = currVertIdx+2;
        indices[4] = currVertIdx+3;
        indices[5] = currVertIdx+0;

        self.currVert += 8;
        self.currTexCoord += 8;
        self.currIdx += 6;

        self.currNumSprites += 1;
    }

    pub fn end(self: *SpriteBatchQueue) void {
        self.flush();
    }

    fn flush(self: *SpriteBatchQueue) void {
        gl.useProgram(self.shaderProgram);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&self.mvpArr[0]));

        gl.activeTexture(gl.TEXTURE0); // Activate texture unit 0
        gl.bindTexture(gl.TEXTURE_2D, self.texture.texture); // Bind your texture
        gl.uniform1i(gl.getUniformLocation(self.shaderProgram, "tex"), 0); // Set 'tex' to use texture unit 0

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices); 
        // gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * self.currNumSprites), &self.vertices, gl.STATIC_DRAW);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.vertices, gl.STATIC_DRAW);
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
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.texCoords, gl.STATIC_DRAW);
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
        // gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * self.currNumSprites), &self.indices, gl.STATIC_DRAW);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.currNumSprites), &self.indices, gl.STATIC_DRAW);

        // gl.drawElements(gl.LINES, @intCast(6*self.currNumSprites), gl.UNSIGNED_SHORT, null);
        gl.drawElements(gl.TRIANGLES, @intCast(6 * self.currNumSprites), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrTexCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        self.currVert = 0;
        self.currTexCoord = 0;
        self.currIdx = 0;
        self.currNumSprites = 0;
    }
};

pub const ShapeBatchQueue = struct {
    shaderProgram: u32 = 0,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboColorCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: [2 * 4 * MaxSprites]f32 = undefined,
    colorCoords: [4 * 4 * MaxSprites]f32 = undefined,
    indices: [6 * MaxSprites]u16 = undefined,
    allocator: std.mem.Allocator = undefined,

    attrCoord: c_uint = 0,
    attrColor: c_uint = 0,
    uniformMVP: c_int = 0,

    currVert: usize = 0,
    currColorCoord: usize = 0,
    currIdx: usize = 0,
    currNumSprites: usize = 0,
    mvpArr: [16]f32 = undefined,

    pub fn init(alloc: std.mem.Allocator, vsCode: ShaderCode, psCode: ShaderCode) !ShapeBatchQueue {
    
        std.debug.print("Creating Shaders...\n", .{});
        const vs = createShader(&vsCode, gl.VERTEX_SHADER) catch |e| {
            return e;
        };
        const ps = createShader(&psCode, gl.FRAGMENT_SHADER) catch |e| {
            return e;
        };
        std.debug.print("Done creating Shaders!\n", .{});

        var batch = ShapeBatchQueue{
            .allocator = alloc
        };

        gl.genVertexArrays(1, &batch.vao);
        gl.bindVertexArray(batch.vao);

        gl.genBuffers(1, &batch.vboVertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &batch.vertices, gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboColorCoords);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboColorCoords);
        gl.bufferData(gl.ARRAY_BUFFER, 4 * 4 * MaxSprites, &batch.colorCoords, gl.DYNAMIC_DRAW);

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
        
        batch.attrCoord = @intCast(gl.getAttribLocation(batch.shaderProgram, "coord3d"));
        batch.attrColor = @intCast(gl.getAttribLocation(batch.shaderProgram, "color"));
        batch.uniformMVP = @intCast(gl.getUniformLocation(batch.shaderProgram, "projectionMatrix"));

        return batch;
    }

    pub fn deinit(self: *ShapeBatchQueue) void {
        gl.deleteProgram(self.shaderProgram);
        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboColorCoords);
        gl.deleteBuffers(1, &self.vboIndices);
    }

    pub fn begin(self: *ShapeBatchQueue, mvp: zmath.Mat) void {

        self.mvpArr = zmath.matToArr(mvp);
                // gl.activeTexture(gl.TEXTURE0); // Activate texture unit 0
        // gl.bindTexture(gl.TEXTURE_2D, texture.texture); // Bind your texture
        // gl.uniform1i(gl.getUniformLocation(self.shaderProgram, "tex"), 0); // Set 'tex' to use texture unit 0

    }

    pub fn drawFilledRect(self: *ShapeBatchQueue, dest: RectF, color: Color) void {
        const verts = self.vertices[self.currVert..self.currVert+8];
        verts[0] = dest.l;
        verts[1] = dest.b;

        verts[2] = dest.l;
        verts[3] = dest.t;

        verts[4] = dest.r;
        verts[5] = dest.t;

        verts[6] = dest.r;
        verts[7] = dest.b;

        const colorCoords = self.colorCoords[self.currColorCoord..self.currColorCoord+16];
        colorCoords[0] = color.r;
        colorCoords[1] = color.g;
        colorCoords[2] = color.b;
        colorCoords[3] = color.a;
        
        colorCoords[4] = color.r;
        colorCoords[5] = color.g;
        colorCoords[6] = color.b;
        colorCoords[7] = color.a;
        
        colorCoords[8] = color.r;
        colorCoords[9] = color.g;
        colorCoords[10] = color.b;
        colorCoords[11] = color.a;
        
        colorCoords[12] = color.r;
        colorCoords[13] = color.g;
        colorCoords[14] = color.b;
        colorCoords[15] = color.a;
        // 
        // texCoords[4] = srcCoords.r;
        // texCoords[5] = srcCoords.t;
        // 
        // texCoords[6] = srcCoords.r;
        // texCoords[7] = srcCoords.b;

        const indices = self.indices[self.currIdx..self.currIdx+6];
        const currVertIdx: u16 = @intCast(self.currVert / 2);
        indices[0] = currVertIdx+0;
        indices[1] = currVertIdx+1;
        indices[2] = currVertIdx+2;
        indices[3] = currVertIdx+2;
        indices[4] = currVertIdx+3;
        indices[5] = currVertIdx+0;

        self.currVert += 8;
        self.currColorCoord += 16;
        self.currIdx += 6;

        self.currNumSprites += 1;
    }

    // This draw a rect with the bounds being dest with it encroaching in by lineWidth
    pub fn drawRect(self: *ShapeBatchQueue, dest: RectF, color: Color, lineWidth: u8) void {
        const lF = @as(f32, @floatFromInt(lineWidth));
        // Draw top rect
        const topRect = RectF{
            .l = dest.l,
            .t = dest.t,
            .r = dest.r,
            .b = dest.t+lF,
        };
        const leftRect = RectF{
            .l = dest.l,
            .t = dest.t+lF,
            .r = dest.l+lF,
            .b = dest.b-lF,
        };
        const rightRect = RectF{
            .l = dest.r-lF,
            .t = dest.t+lF,
            .r = dest.r,
            .b = dest.b-lF,
        };
        const bottomRect = RectF{
            .l = dest.l,
            .t = dest.b-lF,
            .r = dest.r,
            .b = dest.b,
        };

        self.drawFilledRect(topRect, color);
        self.drawFilledRect(leftRect, color);
        self.drawFilledRect(rightRect, color);
        self.drawFilledRect(bottomRect, color);
    }

    // This moves the outline of the rect to enclose the dest by lineWidth.
    pub fn drawEnclosingRect(self: *ShapeBatchQueue, dest: RectF, color: Color, lineWidth: u8) void {
        const lF = @as(f32, @floatFromInt(lineWidth));
        // Draw top rect
        const topRect = RectF{
            .l = dest.l-lF,
            .t = dest.t-lF,
            .r = dest.r+lF,
            .b = dest.t,
        };
        const leftRect = RectF{
            .l = dest.l-lF,
            .t = dest.t,
            .r = dest.l,
            .b = dest.b,
        };
        const rightRect = RectF{
            .l = dest.r,
            .t = dest.t,
            .r = dest.r+lF,
            .b = dest.b,
        };
        const bottomRect = RectF{
            .l = dest.l-lF,
            .t = dest.b,
            .r = dest.r+lF,
            .b = dest.b+lF,
        };

        self.drawFilledRect(topRect, color);
        self.drawFilledRect(leftRect, color);
        self.drawFilledRect(rightRect, color);
        self.drawFilledRect(bottomRect, color);
    }

    pub fn end(self: *ShapeBatchQueue) void {
        self.flush();
    }

    fn flush(self: *ShapeBatchQueue) void {
        gl.useProgram(self.shaderProgram);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&self.mvpArr[0]));

        gl.disable(gl.TEXTURE_2D);

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices); 
        // gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * self.currNumSprites), &self.vertices, gl.STATIC_DRAW);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.vertices, gl.STATIC_DRAW);
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

        gl.enableVertexAttribArray(self.attrColor);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboColorCoords); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(4 * 4 * @sizeOf(f32) * self.currNumSprites), &self.colorCoords, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            // attribute
            self.attrColor,
            // Num elems per vertex
            4, 
            gl.FLOAT, 
            gl.FALSE,
            // stride
            0, 
            null
        );

        // gl.disableVertexAttribArray(buffers.vboTexCoords);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        // gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * self.currNumSprites), &self.indices, gl.STATIC_DRAW);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.currNumSprites), &self.indices, gl.STATIC_DRAW);

        // gl.drawElements(gl.LINES, @intCast(6*self.currNumSprites), gl.UNSIGNED_SHORT, null);
        gl.drawElements(gl.TRIANGLES, @intCast(6 * self.currNumSprites), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrColor);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        self.currVert = 0;
        self.currColorCoord = 0;
        self.currIdx = 0;
        self.currNumSprites = 0;
    }
};

pub const Renderer = struct {

};

