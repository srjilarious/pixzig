const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

const common = @import("../common.zig");
const shaders = @import("../renderer/shaders.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Shader = shaders.Shader;

pub const GridRenderer = struct {
    shader: *const Shader = undefined,
    color: Color = undefined,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboColorCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: []f32 = undefined,
    colorCoords: []f32 = undefined,
    indices: []u32 = undefined,
    alloc: std.mem.Allocator,
    attrCoord: c_uint = 0,
    attrColor: c_uint = 0,
    uniformMVP: c_int = 0,

    currVert: usize = 0,
    currColorCoord: usize = 0,
    currIdx: usize = 0,
    numRects: usize = 0,
    initialized: bool = false,

    pub fn init(alloc: std.mem.Allocator, shader: *const Shader, mapSize: Vec2I, tileSize: Vec2I, borderSize: usize, color: Color) !GridRenderer {
        var gr = GridRenderer{ .shader = shader, .color = color, .alloc = alloc };
        gl.genVertexArrays(1, &gr.vao);

        gl.genBuffers(1, &gr.vboVertices);
        gl.genBuffers(1, &gr.vboColorCoords);
        gl.genBuffers(1, &gr.vboIndices);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.TEXTURE_2D);

        gr.attrCoord = @intCast(gl.getAttribLocation(gr.shader.program, "coord3d"));
        gr.attrColor = @intCast(gl.getAttribLocation(gr.shader.program, "color"));
        gr.uniformMVP = @intCast(gl.getUniformLocation(gr.shader.program, "projectionMatrix"));

        try gr.recreateVertices(mapSize, tileSize, borderSize, color);
        return gr;
    }

    pub fn deinit(self: *GridRenderer) void {
        self.alloc.free(self.vertices);
        self.alloc.free(self.colorCoords);
        self.alloc.free(self.indices);

        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboColorCoords);
        gl.deleteBuffers(1, &self.vboIndices);
    }

    fn drawFilledRect(self: *GridRenderer, dest: RectF, color: Color) void {
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
        const currVertIdx: u32 = @intCast(self.currVert / 2);
        indices[0] = currVertIdx + 0;
        indices[1] = currVertIdx + 1;
        indices[2] = currVertIdx + 2;
        indices[3] = currVertIdx + 2;
        indices[4] = currVertIdx + 3;
        indices[5] = currVertIdx + 0;

        self.currVert += 8;
        self.currColorCoord += 16;
        self.currIdx += 6;

        self.numRects += 1;
    }

    fn drawVertLine(self: *GridRenderer, x: i32, w: i32, h: i32, color: Color) void {
        self.drawFilledRect(RectF.fromPosSize(x, 0, w, h), color);
    }

    fn drawHorzLine(self: *GridRenderer, y: i32, w: i32, h: i32, color: Color) void {
        self.drawFilledRect(RectF.fromPosSize(0, y, w, h), color);
    }

    pub fn recreateVertices(self: *GridRenderer, mapSize: Vec2I, tileSize: Vec2I, borderSize: usize, color: Color) !void {
        self.currVert = 0;
        self.currColorCoord = 0;
        self.currIdx = 0;
        self.numRects = 0;

        const tw: usize = @intCast(tileSize.x);
        const th: usize = @intCast(tileSize.y);
        const numHorz: usize = @as(usize, @intCast(mapSize.x)) + 1;
        const numVert: usize = @as(usize, @intCast(mapSize.y)) + 1;
        // const mapSize: i32 = @intCast(layerWidth*layerHeight);
        // _ = mapSize;

        // Check if we need to release previous buffers.
        if (self.initialized) {
            self.alloc.free(self.vertices);
            self.alloc.free(self.colorCoords);
            self.alloc.free(self.indices);
        }

        self.vertices = try self.alloc.alloc(f32, @intCast(2 * 4 * numHorz * numVert * 2));
        self.colorCoords = try self.alloc.alloc(f32, @intCast(4 * 4 * numHorz * numVert * 2));
        self.indices = try self.alloc.alloc(u32, @intCast(6 * numHorz * numVert * 2));
        self.initialized = true;

        std.log.info("Creating {} vertices\n", .{self.vertices.len});
        const gridWidth: i32 = @intCast((numHorz - 1) * tw);
        const gridHeight: i32 = @intCast((numVert - 1) * th);
        for (0..numVert) |yy| {
            for (0..numHorz) |xx| {
                self.drawHorzLine(@intCast(yy * th), gridWidth, @intCast(borderSize), color);
                self.drawVertLine(@intCast(xx * tw), @intCast(borderSize), gridHeight, color);
            }
        }
    }

    pub fn draw(self: *GridRenderer, mvp: zmath.Mat) !void {
        const mvpArr = zmath.matToArr(mvp);
        // const layerWidth: usize = @intCast(tiles.size.x);
        // const layerHeight: usize = @intCast(tiles.size.y);
        // const mapSize: i32 = @intCast(layerWidth*layerHeight);
        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&mvpArr[0]));

        gl.disable(gl.TEXTURE_2D);

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.numRects), &self.vertices[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrCoord, 2, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.enableVertexAttribArray(self.attrColor);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboColorCoords);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(4 * 4 * @sizeOf(f32) * self.numRects), &self.colorCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(self.attrColor, 4, // Num elems per vertex
            gl.FLOAT, gl.FALSE, 0, // stride
            null);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.numRects), &self.indices[0], gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(6 * self.numRects), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrColor);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    }
};
