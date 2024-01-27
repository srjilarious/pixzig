// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const zmath = @import("zmath"); 
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
const pixzig = @import("pixzig");
const freetype = @import("freetype");

const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Vec2I = pixzig.common.Vec2I;

const GameStateMgr = pixzig.gamestate.GameStateMgr;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;
const PixzigEngine = pixzig.PixzigEngine;

pub const TextPixelShader: pixzig.shaders.ShaderCode =
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
    tex: pixzig.Texture,
    spriteBatch: pixzig.renderer.SpriteBatchQueue,

    texShader: pixzig.shaders.Shader,
    alloc: std.mem.Allocator,

    pub fn init(fontFace: [:0]const u8, alloc: std.mem.Allocator) !TextRenderer {
        var chars = std.AutoHashMap(u32, Character).init(alloc);
        var texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &TextPixelShader
        );

        const spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(alloc, &texShader);

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

        for(0x21..128) |c| {
            
            try face.loadChar(@intCast(c), .{ .render = true });
            const glyph = face.glyph();
            const bitmap = glyph.bitmap();
            const bw = bitmap.width();
            const bh = bitmap.rows();

            if(bitmap.buffer() == null) {
                std.debug.print("Skipping char {}\n", .{c});
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
        };

    }

    pub fn deinit(self: *TextRenderer) void {
        self.characters.deinit();
    }


};

pub const MyApp = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    projMat: zmath.Mat,
    textRenderer: TextRenderer,

    pub fn init(eng: *PixzigEngine, alloc: std.mem.Allocator) !MyApp {
        _ = eng;

        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const textRenderer = try TextRenderer.init("assets/Roboto-Medium.ttf", alloc);
        
        // set texture options
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);  
        return .{ 
            .fps = FpsCounter.init(),
            .alloc = alloc,
            .projMat = projMat,
            .textRenderer = textRenderer
        };
    }

    pub fn deinit(self: *MyApp) void {
        self.textRenderer.deinit();
    }

    pub fn update(self: *MyApp, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();
        if(eng.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *MyApp, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        self.fps.renderTick();

        self.textRenderer.spriteBatch.begin(self.projMat);
        self.textRenderer.spriteBatch.drawSprite(&self.textRenderer.tex, 
            RectF.fromPosSize(32, 32, 512, 512), .{ .l=0, .t=0, .r=1, .b=1});
        self.textRenderer.spriteBatch.end();
    }
};



pub fn main() !void {

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Glfw Eng Mouse Test.", gpa, EngOptions{});
    defer eng.deinit();

    const AppRunner = pixzig.PixzigApp(MyApp);

    var app = try MyApp.init(&eng, gpa);

    eng.window.setInputMode(.cursor, .hidden);
    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
    app.deinit();
}


