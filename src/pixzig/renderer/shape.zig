const std = @import("std");
const builtin = @import("builtin");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

const common = @import("../common.zig");

const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");
const Sprite = @import("./sprites.zig").Sprite;
const C = @import("./constants.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Rotate = common.Rotate;
const Texture = textures.Texture;
const Shader = shaders.Shader;

const NumColorCoords = 4 * 4 * C.MaxSprites;

pub const ShapeBatchQueue = struct {
    shader: *Shader = undefined,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboColorCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: []f32 = undefined,
    colorCoords: []f32 = undefined,
    indices: []u16 = undefined,
    allocator: std.mem.Allocator = undefined,

    attrCoord: c_uint = 0,
    attrColor: c_uint = 0,
    uniformMVP: c_int = 0,

    currVert: usize = 0,
    currColorCoord: usize = 0,
    currIdx: usize = 0,
    currNumSprites: usize = 0,
    mvpArr: [16]f32 = undefined,
    begun: bool = false,

    pub fn init(alloc: std.mem.Allocator, shader: *Shader) !ShapeBatchQueue {
        var batch = ShapeBatchQueue{
            .allocator = alloc,
            .shader = shader,
        };

        batch.vertices = try alloc.alloc(f32, C.NumVerts);
        batch.colorCoords = try alloc.alloc(f32, NumColorCoords);
        batch.indices = try alloc.alloc(u16, C.NumIndices);

        gl.genVertexArrays(1, &batch.vao);
        gl.bindVertexArray(batch.vao);

        gl.genBuffers(1, &batch.vboVertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * C.NumVerts, &batch.vertices[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboColorCoords);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboColorCoords);
        gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * NumColorCoords, &batch.colorCoords[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboIndices);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, batch.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, C.NumIndices * @sizeOf(u16), &batch.indices[0], gl.DYNAMIC_DRAW);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.TEXTURE_2D);

        batch.attrCoord = @intCast(gl.getAttribLocation(batch.shader.program, "coord3d"));
        batch.attrColor = @intCast(gl.getAttribLocation(batch.shader.program, "color"));
        batch.uniformMVP = @intCast(gl.getUniformLocation(batch.shader.program, "projectionMatrix"));

        return batch;
    }

    pub fn deinit(self: *ShapeBatchQueue) void {
        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboColorCoords);
        gl.deleteBuffers(1, &self.vboIndices);
        self.allocator.free(self.vertices);
        self.allocator.free(self.colorCoords);
        self.allocator.free(self.indices);
    }

    pub fn begin(self: *ShapeBatchQueue, mvp: zmath.Mat) void {
        if (self.begun) {
            self.end();
        }

        self.begun = true;
        self.mvpArr = zmath.matToArr(mvp);
    }

    pub fn drawFilledRect(self: *ShapeBatchQueue, dest: RectF, color: Color) void {
        std.debug.assert(self.begun);

        const verts = self.vertices[self.currVert .. self.currVert + 8];
        verts[0] = dest.l;
        verts[1] = dest.b;

        verts[2] = dest.l;
        verts[3] = dest.t;

        verts[4] = dest.r;
        verts[5] = dest.t;

        verts[6] = dest.r;
        verts[7] = dest.b;

        const colorCoords = self.colorCoords[self.currColorCoord .. self.currColorCoord + 16];
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

        const indices = self.indices[self.currIdx .. self.currIdx + 6];
        const currVertIdx: u16 = @intCast(self.currVert / 2);
        indices[0] = currVertIdx + 0;
        indices[1] = currVertIdx + 1;
        indices[2] = currVertIdx + 2;
        indices[3] = currVertIdx + 2;
        indices[4] = currVertIdx + 3;
        indices[5] = currVertIdx + 0;

        self.currVert += 8;
        self.currColorCoord += 16;
        self.currIdx += 6;

        self.currNumSprites += 1;
    }

    // This draw a rect with the bounds being dest with it encroaching in by lineWidth
    pub fn drawRect(self: *ShapeBatchQueue, dest: RectF, color: Color, lineWidth: u8) void {
        std.debug.assert(self.begun);

        const lF = @as(f32, @floatFromInt(lineWidth));
        // Draw top rect
        const topRect = RectF{
            .l = dest.l,
            .t = dest.t,
            .r = dest.r,
            .b = dest.t + lF,
        };
        self.drawFilledRect(topRect, color);

        // Draw the left rect
        const leftRect = RectF{
            .l = dest.l,
            .t = dest.t + lF,
            .r = dest.l + lF,
            .b = dest.b - lF,
        };
        self.drawFilledRect(leftRect, color);

        // Draw the right rect
        const rightRect = RectF{
            .l = dest.r - lF,
            .t = dest.t + lF,
            .r = dest.r,
            .b = dest.b - lF,
        };
        self.drawFilledRect(rightRect, color);

        // Draw the bottom rect
        const bottomRect = RectF{
            .l = dest.l,
            .t = dest.b - lF,
            .r = dest.r,
            .b = dest.b,
        };
        self.drawFilledRect(bottomRect, color);
    }

    // This moves the outline of the rect to enclose the dest by lineWidth.
    pub fn drawEnclosingRect(self: *ShapeBatchQueue, dest: RectF, color: Color, lineWidth: u8) void {
        std.debug.assert(self.begun);

        const lF = @as(f32, @floatFromInt(lineWidth));
        // Draw top rect
        const topRect = RectF{
            .l = dest.l - lF,
            .t = dest.t - lF,
            .r = dest.r + lF,
            .b = dest.t,
        };
        self.drawFilledRect(topRect, color);

        // Draw the left rect
        const leftRect = RectF{
            .l = dest.l - lF,
            .t = dest.t,
            .r = dest.l,
            .b = dest.b,
        };
        self.drawFilledRect(leftRect, color);

        // Draw the right rect.
        const rightRect = RectF{
            .l = dest.r,
            .t = dest.t,
            .r = dest.r + lF,
            .b = dest.b,
        };
        self.drawFilledRect(rightRect, color);

        // Draw the bottom rect.
        const bottomRect = RectF{
            .l = dest.l - lF,
            .t = dest.b,
            .r = dest.r + lF,
            .b = dest.b + lF,
        };
        self.drawFilledRect(bottomRect, color);
    }

    pub fn end(self: *ShapeBatchQueue) void {
        self.flush();
        self.begun = false;
    }

    fn flush(self: *ShapeBatchQueue) void {
        std.debug.assert(self.begun);
        if (self.currNumSprites == 0) return;

        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&self.mvpArr[0]));

        //gl.disable(gl.TEXTURE_2D);

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.vertices[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrCoord, 2, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.enableVertexAttribArray(self.attrColor);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboColorCoords);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(4 * 4 * @sizeOf(f32) * self.currNumSprites), &self.colorCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrColor, 4, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.currNumSprites), &self.indices[0], gl.STATIC_DRAW);

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
