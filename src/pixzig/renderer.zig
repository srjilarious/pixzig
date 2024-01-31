// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl");
const zmath = @import("zmath");
const freetype = @import("freetype");

const common = @import("./common.zig");
const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");

const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Color = common.Color;
const Texture = textures.Texture;
const Shader = shaders.Shader;

const MaxSprites = 1000;

pub const SpriteBatchQueue = struct {
    shader: *Shader = undefined,
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
    texture: ?*Texture = null,
    begun: bool = false,

    pub fn init(alloc: std.mem.Allocator, shader: *Shader) !SpriteBatchQueue {
    
        var batch = SpriteBatchQueue{
            .allocator = alloc,
            .shader = shader
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

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.TEXTURE_2D);
        
        batch.attrCoord = @intCast(gl.getAttribLocation(batch.shader.program, "coord3d"));
        batch.attrTexCoord = @intCast(gl.getAttribLocation(batch.shader.program, "texcoord"));
        batch.uniformMVP = @intCast(gl.getUniformLocation(batch.shader.program, "projectionMatrix"));

        return batch;
    }

    pub fn deinit(self: *SpriteBatchQueue) void {
        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboTexCoords);
        gl.deleteBuffers(1, &self.vboIndices);
    }

    pub fn begin(self: *SpriteBatchQueue, mvp: zmath.Mat) void {
        if(self.begun) {
            self.end();
        }
        self.begun = true;
        self.mvpArr = zmath.matToArr(mvp);
    }

    pub fn drawSprite(self: *SpriteBatchQueue, texture: *Texture, dest: RectF, srcCoords: RectF) void {
        std.debug.assert(self.begun);

        if(self.texture == null) {
            self.texture = texture;
        } 

        if(self.texture != texture) {
            self.flush();
            self.texture = texture;
        }

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
        self.begun = false;
    }

    fn flush(self: *SpriteBatchQueue) void {
        std.debug.assert(self.begun);

        if(self.currNumSprites == 0) return;

        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&self.mvpArr[0]));

        // Set 'tex' to use texture unit 0
        gl.activeTexture(gl.TEXTURE0); 
        gl.bindTexture(gl.TEXTURE_2D, self.texture.?.texture); 
        gl.uniform1i(gl.getUniformLocation(self.shader.program, "tex"), 0); 

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.vertices, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrCoord,
            2, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.enableVertexAttribArray(self.attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.texCoords, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrTexCoord,
            2, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.currNumSprites), &self.indices, gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(6 * self.currNumSprites), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrTexCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        self.currVert = 0;
        self.currTexCoord = 0;
        self.currIdx = 0;
        self.currNumSprites = 0;
        self.texture = null;
    }
};

pub const ShapeBatchQueue = struct {
    shader: *Shader = undefined,
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
    begun: bool = false,

    pub fn init(alloc: std.mem.Allocator, shader: *Shader) !ShapeBatchQueue {
    
        var batch = ShapeBatchQueue{
            .allocator = alloc,
            .shader = shader,
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
    }

    pub fn begin(self: *ShapeBatchQueue, mvp: zmath.Mat) void {
        if(self.begun) {
            self.end();
        }

        self.begun = true;
        self.mvpArr = zmath.matToArr(mvp);
    }

    pub fn drawFilledRect(self: *ShapeBatchQueue, dest: RectF, color: Color) void {
        std.debug.assert(self.begun);

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
        std.debug.assert(self.begun);

        const lF = @as(f32, @floatFromInt(lineWidth));
        // Draw top rect
        const topRect = RectF{
            .l = dest.l,
            .t = dest.t,
            .r = dest.r,
            .b = dest.t+lF,
        };
        self.drawFilledRect(topRect, color);
        
        // Draw the left rect
        const leftRect = RectF{
            .l = dest.l,
            .t = dest.t+lF,
            .r = dest.l+lF,
            .b = dest.b-lF,
        };
        self.drawFilledRect(leftRect, color);

        // Draw the right rect
        const rightRect = RectF{
            .l = dest.r-lF,
            .t = dest.t+lF,
            .r = dest.r,
            .b = dest.b-lF,
        };
        self.drawFilledRect(rightRect, color);

        // Draw the bottom rect
        const bottomRect = RectF{
            .l = dest.l,
            .t = dest.b-lF,
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
            .l = dest.l-lF,
            .t = dest.t-lF,
            .r = dest.r+lF,
            .b = dest.t,
        };
        self.drawFilledRect(topRect, color);

        // Draw the left rect
        const leftRect = RectF{
            .l = dest.l-lF,
            .t = dest.t,
            .r = dest.l,
            .b = dest.b,
        };
        self.drawFilledRect(leftRect, color);

        // Draw the right rect.
        const rightRect = RectF{
            .l = dest.r,
            .t = dest.t,
            .r = dest.r+lF,
            .b = dest.b,
        };
        self.drawFilledRect(rightRect, color);

        // Draw the bottom rect.
        const bottomRect = RectF{
            .l = dest.l-lF,
            .t = dest.b,
            .r = dest.r+lF,
            .b = dest.b+lF,
        };
        self.drawFilledRect(bottomRect, color);
    }

    pub fn end(self: *ShapeBatchQueue) void {
        self.flush();
        self.begun = false;
    }

    fn flush(self: *ShapeBatchQueue) void {
        std.debug.assert(self.begun);
        if(self.currNumSprites == 0) return;

        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&self.mvpArr[0]));

        gl.disable(gl.TEXTURE_2D);

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.vertices, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrCoord,
            2, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.enableVertexAttribArray(self.attrColor);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboColorCoords); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(4 * 4 * @sizeOf(f32) * self.currNumSprites), &self.colorCoords, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrColor,
            4, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.currNumSprites), &self.indices, gl.STATIC_DRAW);

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

pub const TextPixelShader: shaders.ShaderCode =
    \\ #version 330 core
    \\ in vec2 Texcoord; // Received from vertex shader
    \\ uniform sampler2D tex; // Texture sampler
    \\ out vec4 fragColor;
    \\ void main() {
    \\   fragColor = vec4(1.0, 1.0, 1.0, texture(tex, Texcoord).r); 
    \\ }
;
pub const Character = struct {
    coords: RectF,
    size: Vec2I,
    bearing: Vec2I,
    advance: u32
};


pub const TextRenderer = struct {
    characters: std.AutoHashMap(u32, Character),
    tex: Texture,
    spriteBatch: SpriteBatchQueue,
    maxY: i32,
    texShader: Shader,
    alloc: std.mem.Allocator,

    pub fn init(fontFace: [:0]const u8, alloc: std.mem.Allocator) !TextRenderer {
        var chars = std.AutoHashMap(u32, Character).init(alloc);
        var texShader = try shaders.Shader.init(
            &shaders.TexVertexShader,
            &TextPixelShader
        );

        const spriteBatch = try SpriteBatchQueue.init(alloc, &texShader);

        // Test font loading.
        const lib = try freetype.Library.init();
        defer lib.deinit();

        const face = try lib.createFace(fontFace, 0);
        try face.setCharSize(60 * 48, 0, 50, 0);
        // Generate a buffer for multiple glyphs
        const GlyphBufferWidth = 512;
        const GlyphBufferHeight = 512;
        var glyphBuffer = try alloc.alloc(u8, GlyphBufferWidth*GlyphBufferHeight);
        defer alloc.free(glyphBuffer);

        var currY: usize = 0;
        var currLineMaxY: usize = 0;
        var currLineX: usize = 0;
        var maxY: i32 = 0;

        for(0x20..128) |c| {
            
            try face.loadChar(@intCast(c), .{ .render = true });
            const glyph = face.glyph();
            const bitmap = glyph.bitmap();
            const bw = bitmap.width();
            const bh = bitmap.rows();

            if(bitmap.buffer() == null) {
                //std.debug.print("Skipping char {}\n", .{c});
                continue;
            }
            const buffer = bitmap.buffer().?;

            // Check to move glyph to next line
            if(currLineX + bw > GlyphBufferWidth) {
                currLineX = 0;
                currY += currLineMaxY;
                currLineMaxY = 0;
            }

            for(0..bh) |y| {
                for(0..bw) |x| {
                    glyphBuffer[(currY+y)*GlyphBufferWidth+currLineX+x] = buffer[y*bw+x];
                }
            }

            try chars.put(@intCast(c), .{
                .coords = RectF.fromCoords(
                    @intCast(currLineX), 
                    @intCast(currY), 
                    @intCast(bw), 
                    @intCast(bh), 
                    GlyphBufferWidth, GlyphBufferHeight),
                .size = .{ .x = @intCast(bw), .y = @intCast(bh) },
                .bearing = .{ .x = glyph.bitmapLeft(), .y = glyph.bitmapTop() },
                .advance = @intCast(glyph.advance().x)
            });

            if(bitmap.rows() > currLineMaxY) {
                currLineMaxY = bitmap.rows();
            }

            maxY = @max(glyph.bitmapTop(), maxY);

            currLineX += bitmap.width();
        }

        // generate texture
        var charTex: c_uint = undefined;
        gl.genTextures(1, &charTex);
        gl.bindTexture(gl.TEXTURE_2D, charTex);
        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RED,
            @intCast(GlyphBufferWidth),
            @intCast(GlyphBufferHeight),
            0,
            gl.RED,
            gl.UNSIGNED_BYTE,
            @ptrCast(glyphBuffer)
        );

        return .{ 
            .alloc = alloc,
            .characters = chars,
            .spriteBatch = spriteBatch,
            .tex = .{ 
                .texture = charTex, 
                .size = .{ 
                    .x = @intCast(GlyphBufferWidth), 
                    .y = @intCast(GlyphBufferHeight)
                },
                .name = null
            },
            .texShader = texShader,
            .maxY = maxY,
        };

    }

    pub fn deinit(self: *TextRenderer) void {
        self.characters.deinit();
    }

    pub fn drawString(self: *TextRenderer, text: []const u8, pos: Vec2I) Vec2I {
        var currX: i32 = pos.x;

        const posY = pos.y + self.maxY;

        var drawSize: Vec2I = .{ .x = 0, .y = 0 };
        for(text) |c| {
            const charDataPtr = self.characters.get(@intCast(c));
            if(charDataPtr == null) continue;

            const charData = charDataPtr.?;

            self.spriteBatch.drawSprite(
                &self.tex, 
                RectF.fromPosSize(currX, posY - charData.bearing.y, charData.size.x, charData.size.y), 
                charData.coords);
            const adv: i32 = @intCast(charData.advance/64);
            currX += adv;
            drawSize.x += adv;
            drawSize.y = @max(drawSize.y, charData.size.y);
        }

        return drawSize;
    }

};

pub fn Renderer(NumExpectedTextures: usize) type {

    return struct {
        batches: [NumExpectedTextures]SpriteBatchQueue,
        shapes: ShapeBatchQueue,
        text: TextRenderer,

        // pub fn init(alloc: std.mem.Allocator) @This() {
        //     
        // }
    };
}

