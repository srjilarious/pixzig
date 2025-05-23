// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");
const freetype = @import("freetype");

const common = @import("./common.zig");
const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");

const Sprite = @import("./sprites.zig").Sprite;
const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Rotate = common.Rotate;
const Texture = textures.Texture;
const Shader = shaders.Shader;

const MaxSprites = 1000;


const NumVerts = 2 * 4 * MaxSprites;
const NumIndices = 6 * MaxSprites;
pub const SpriteBatchQueue = struct {
    shader: *Shader,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboTexCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: []f32 = undefined,
    texCoords: []f32 = undefined,
    indices: []u16 = undefined,
    allocator: std.mem.Allocator,

    attrCoord: c_uint = 0,
    attrTexCoord: c_uint = 0,
    uniformMVP: c_int = 0,

    currVert: usize = 0,
    currTexCoord: usize = 0,
    currIdx: usize = 0,
    currNumSprites: usize = 0,

    mvpArr: [16]f32 = .{0} ** 16,
    texture: ?*Texture = null,
    begun: bool = false,

    pub fn init(alloc: std.mem.Allocator, shader: *Shader) !SpriteBatchQueue {
    
        var batch = SpriteBatchQueue{
            .allocator = alloc,
            .shader = shader
        };

        batch.vertices = try alloc.alloc(f32, NumVerts);
        batch.texCoords = try alloc.alloc(f32, NumVerts);
        batch.indices = try alloc.alloc(u16, NumIndices);

        gl.genVertexArrays(1, &batch.vao);
        gl.bindVertexArray(batch.vao);

        gl.genBuffers(1, &batch.vboVertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &batch.vertices[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboTexCoords);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * MaxSprites, &batch.texCoords[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboIndices);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, batch.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 6 * MaxSprites, &batch.indices[0], gl.DYNAMIC_DRAW);

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
        self.allocator.free(self.vertices);
        self.allocator.free(self.texCoords);
        self.allocator.free(self.indices);
    }

    pub fn begin(self: *SpriteBatchQueue, mvp: zmath.Mat) void {
        if(self.begun) {
            self.end();
        }
        self.begun = true;
        self.mvpArr = zmath.matToArr(mvp);
    }

    pub fn drawSprite(self: *SpriteBatchQueue, sprite: *Sprite) void {
        self.draw(sprite.texture, sprite.dest, sprite.src_coords, sprite.rotate);
    }

    pub fn draw(self: *SpriteBatchQueue, texture: *Texture, dest: RectF, srcCoords: RectF,
        rot: Rotate) void {
        std.debug.assert(self.begun);

        if(self.texture == null) {
            self.texture = texture;
        } 

        if(self.texture.?.texture != texture.texture) {
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
        switch(rot) {
            .none => {
                texCoords[0] = srcCoords.l;
                texCoords[1] = srcCoords.b;

                texCoords[2] = srcCoords.l;
                texCoords[3] = srcCoords.t;
                
                texCoords[4] = srcCoords.r;
                texCoords[5] = srcCoords.t;
                
                texCoords[6] = srcCoords.r;
                texCoords[7] = srcCoords.b;
            },
            .rot90 => {
                texCoords[0] = srcCoords.l;
                texCoords[1] = srcCoords.t;
                
                texCoords[2] = srcCoords.r;
                texCoords[3] = srcCoords.t;
                
                texCoords[4] = srcCoords.r;
                texCoords[5] = srcCoords.b;

                texCoords[6] = srcCoords.l;
                texCoords[7] = srcCoords.b;
            },
            .rot180 => {
                texCoords[0] = srcCoords.r;
                texCoords[1] = srcCoords.t;
                
                texCoords[2] = srcCoords.r;
                texCoords[3] = srcCoords.b;

                texCoords[4] = srcCoords.l;
                texCoords[5] = srcCoords.b;

                texCoords[6] = srcCoords.l;
                texCoords[7] = srcCoords.t;
            },
            .rot270 => {
                texCoords[0] = srcCoords.r;
                texCoords[1] = srcCoords.b;

                texCoords[2] = srcCoords.l;
                texCoords[3] = srcCoords.b;

                texCoords[4] = srcCoords.l;
                texCoords[5] = srcCoords.t;
                
                texCoords[6] = srcCoords.r;
                texCoords[7] = srcCoords.t;
            },
            .flipHorz => {
                texCoords[0] = srcCoords.r;
                texCoords[1] = srcCoords.b;

                texCoords[2] = srcCoords.r;
                texCoords[3] = srcCoords.t;
                
                texCoords[4] = srcCoords.l;
                texCoords[5] = srcCoords.t;
                
                texCoords[6] = srcCoords.l;
                texCoords[7] = srcCoords.b;
            },
            .flipVert => {
                texCoords[0] = srcCoords.l;
                texCoords[1] = srcCoords.t;

                texCoords[2] = srcCoords.l;
                texCoords[3] = srcCoords.b;
                
                texCoords[4] = srcCoords.r;
                texCoords[5] = srcCoords.b;
                
                texCoords[6] = srcCoords.r;
                texCoords[7] = srcCoords.t;
            },

        }

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
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.vertices[0], gl.STATIC_DRAW);
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
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.texCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrTexCoord,
            2, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.currNumSprites), &self.indices[0], gl.STATIC_DRAW);

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

const NumColorCoords = 4 * 4 * MaxSprites;

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

        batch.vertices = try alloc.alloc(f32, NumVerts);
        batch.colorCoords = try alloc.alloc(f32, NumColorCoords);
        batch.indices = try alloc.alloc(u16, NumIndices);

        gl.genVertexArrays(1, &batch.vao);
        gl.bindVertexArray(batch.vao);

        gl.genBuffers(1, &batch.vboVertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * NumVerts, &batch.vertices[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboColorCoords);
        gl.bindBuffer(gl.ARRAY_BUFFER, batch.vboColorCoords);
        gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(f32)*NumColorCoords, &batch.colorCoords[0], gl.DYNAMIC_DRAW);

        gl.genBuffers(1, &batch.vboIndices);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, batch.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, NumIndices * @sizeOf(u16), &batch.indices[0], gl.DYNAMIC_DRAW);

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
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.currNumSprites), &self.vertices[0], gl.STATIC_DRAW);
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
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(4 * 4 * @sizeOf(f32) * self.currNumSprites), &self.colorCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrColor,
            4, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

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
                .src = . { .l = 0, .t = 0, .r = 1, .b = 1 },
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

            self.spriteBatch.draw(
                &self.tex, 
                RectF.fromPosSize(currX, posY - charData.bearing.y, charData.size.x, charData.size.y), 
                charData.coords,
                .none);
            const adv: i32 = @intCast(charData.advance/64);
            currX += adv;
            drawSize.x += adv;
            drawSize.y = @max(drawSize.y, charData.size.y);
        }

        return drawSize;
    }

};

pub const RendererOptions = struct {
    numSpriteTextures: u8 = 1,
    shapeRendering: bool = true,
    textRenderering: bool = false,
};

pub const RendererInitOpts = struct {
    fontFace: ?[:0]const u8 = null,
};

pub fn Renderer(opts: RendererOptions) type {

    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        impl: *Impl,

        const Impl = struct {
            batches: [opts.numSpriteTextures]SpriteBatchQueue,
            texShader: Shader,

            shapes: ShapeBatchQueue = undefined,
            colorShader: Shader = undefined,
            
            text: TextRenderer = undefined,

        };

        pub fn init(alloc: std.mem.Allocator, initOpts: RendererInitOpts) !@This() {
            var rend = try alloc.create(Impl);

            rend.texShader = try Shader.init(
                &shaders.TexVertexShader,
                &shaders.TexPixelShader
            );

            std.log.info("Setting up {} sprite batch queues.", .{opts.numSpriteTextures});
            for(0..opts.numSpriteTextures) |idx| {
                const sbq = try SpriteBatchQueue.init(alloc, &rend.texShader);
                rend.batches[idx] = sbq;
            }

            if(opts.shapeRendering) {
                std.log.info("Setting up shaders for shape renderering.", .{});
                rend.colorShader = try shaders.Shader.init(
                    &shaders.ColorVertexShader,
                    &shaders.ColorPixelShader
                );
                
                rend.shapes = try ShapeBatchQueue.init(alloc, &rend.colorShader);
            }


            if(opts.textRenderering) {
                std.log.info("Setting up text renderering.\n", .{});
                std.debug.assert(initOpts.fontFace != null);
                rend.text = try TextRenderer.init(initOpts.fontFace.?, alloc);
            }

            // set texture options
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
            gl.enable(gl.BLEND);
            gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

            return .{ 
                .alloc = alloc,
                .impl = rend
            };
        }

        pub fn deinit(self: *Self) void {
            for(0..self.impl.batches.len) |idx| {
                self.impl.batches[idx].deinit();
            }

            self.impl.texShader.deinit();

            if(opts.shapeRendering) {
                self.impl.colorShader.deinit();
                self.impl.shapes.deinit();
            }

            if(opts.textRenderering) {
                self.impl.text.deinit();
            }

            self.alloc.destroy(self.impl);
        }

        pub fn begin(self: *Self, mvp: zmath.Mat) void {
            for(0..self.impl.batches.len) |idx| {
                self.impl.batches[idx].begin(mvp);
            }

            if(opts.shapeRendering) {
                self.impl.shapes.begin(mvp);
            }

            if(opts.textRenderering) {
                self.impl.text.spriteBatch.begin(mvp);
            }
        }

        pub fn end(self: *Self) void {
            for(0..self.impl.batches.len) |idx| {
                self.impl.batches[idx].end();
            }

            if(opts.shapeRendering) {
                self.impl.shapes.end();
            }

            if(opts.textRenderering) {
                self.impl.text.spriteBatch.end();
            }
        }
        
        pub fn clear(self: *const Self, r: f32, g: f32, b: f32, a:f32) void {
            _ = self;
            gl.clearColor(r, g, b, a);
            gl.clear(gl.COLOR_BUFFER_BIT);
        }

        pub fn draw(self: *Self, texture: *Texture, dest: RectF, srcCoords: RectF) void {
            // TODO: Handle multiple batches
            self.impl.batches[0].draw(texture, dest, srcCoords, .none);
        }

        pub fn drawSprite(self: *Self, sprite: *Sprite) void
        {
            // TODO: Handle batches
            self.impl.batches[0].drawSprite(sprite);
        }

        pub fn drawTexture(self: *Self, texture: *Texture, dest: RectF, srcCoords: RectF) void {
             self.impl.batches[0].draw(texture, dest, srcCoords, .none);
        }

        pub fn drawFullTexture(self: *Self, texture: *Texture, pos: Vec2I, scale: f32) void {
            const tsx = @as(f32, @floatFromInt(texture.size.x))*scale;
            const tsy = @as(f32, @floatFromInt(texture.size.y))*scale;
            self.impl.batches[0].draw(
                texture, 
                RectF.fromPosSize(pos.x, pos.y, @intFromFloat(tsx), @intFromFloat(tsy)),
                texture.src,
                .none
            );
        }

        pub fn drawFilledRect(self: *Self, dest: RectF, color: Color) void {
            std.debug.assert(opts.shapeRendering);
            self.impl.shapes.drawFilledRect(dest, color);
        }

        pub fn drawRect(self: *Self, dest: RectF, color: Color, lineWidth: u8) void {
            std.debug.assert(opts.shapeRendering);
            self.impl.shapes.drawRect(dest, color, lineWidth);
        }

        // This moves the outline of the rect to enclose the dest by lineWidth.
        pub fn drawEnclosingRect(self: *Self, dest: RectF, color: Color, lineWidth: u8) void {
            std.debug.assert(opts.shapeRendering);
            self.impl.shapes.drawEnclosingRect(dest, color, lineWidth);
        }

        pub fn drawString(self: *Self, text: []const u8, pos: Vec2I) Vec2I {
            std.debug.assert(opts.textRenderering);
            return self.impl.text.drawString(text, pos);
        }
    };
}

