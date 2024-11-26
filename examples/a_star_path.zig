// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import ("zstbi");
const zmath = @import("zmath"); 
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const shaders = pixzig.shaders;
const Shader = shaders.Shader;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const Vec2U = pixzig.common.Vec2U;
const FpsCounter = pixzig.utils.FpsCounter;

const Renderer = pixzig.renderer.Renderer(.{});
const GridRenderer = tile.GridRenderer;
const CharToColor = pixzig.textures.CharToColor;
const Color8 = pixzig.Color8;
const Texture = pixzig.textures.Texture;

const NumTilesHorz = 4;
const NumTilesVert = 4;
const TileWidth = 8;
const TileHeight = 8;

pub const App = struct {
    allocator: std.mem.Allocator,
    projMat: zmath.Mat,
    renderer: Renderer,
    fps: FpsCounter,
    grid: GridRenderer,
    tex: *Texture,

    pub fn init(eng: *pixzig.PixzigEngine, alloc: std.mem.Allocator) !App {
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const renderer = try Renderer.init(alloc, .{});

        const shader = try Shader.init(
                &shaders.ColorVertexShader,
                &shaders.ColorPixelShader
            );
        const grid = try GridRenderer.init(alloc, shader, .{ .x = 20, .y = 12}, .{ .x = 32, .y = 32}, 1);

        // Create a texture for the path tiles.
        const colorMap = &[_]CharToColor{
            .{ .char = '#', .color = Color8.from(180, 180, 180, 255) },
            .{ .char = '-', .color = Color8.from(80, 80, 80, 255) },
            .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
            .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
            .{ .char = '@', .color = Color8.from(30, 30, 30, 255) },
            .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
        };

        const lockedChars =
        \\=------=
        \\-######-
        \\-#####=-
        \\-#####=-
        \\-#####=-
        \\-#####=-
        \\-##===@-
        \\=------=
        ;
    
        
        const textureBuff: []u8 = try alloc.alloc(u8, (NumTilesHorz*NumTilesVert)*TileWidth*TileHeight*4);
        defer alloc.free(textureBuff);

        const bufferSize = Vec2U{.x = NumTilesHorz*TileWidth, .y=NumTilesVert*TileHeight};

        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, lockedChars, .{.x=TileWidth, .y=TileHeight}, .{.x=0, .y=0}, colorMap);
        // const wallTex = try eng.textures.createTextureFromChars("wall", 8, 8, lockedChars, );

        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        const tex = try eng.textures.loadTextureFromBuffer("a_star", bufferSize.x, bufferSize.y, textureBuff);
        return .{
            .allocator = alloc,
            .projMat = projMat,
            // .scrollOffset = .{ .x = 0, .y = 0}, 
            .renderer = renderer,
            .fps = FpsCounter.init(),
            .grid = grid,
            .tex= tex,
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.grid.deinit();
    }

    pub fn update(self: *App, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
        // const ScrollAmount = 3;
        // if (eng.keyboard.down(.left)) {
        //     self.scrollOffset.x += ScrollAmount;
        // }
        // if (eng.keyboard.down(.right)) {
        //     self.scrollOffset.x -= ScrollAmount;
        // }
        // if (eng.keyboard.down(.up)) {
        //     self.scrollOffset.y += ScrollAmount;
        // }
        // if (eng.keyboard.down(.down)) {
        //     self.scrollOffset.y -= ScrollAmount;
        // }
        if(eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        self.fps.renderTick();
      
        

        self.renderer.begin(self.projMat);
        self.renderer.drawFullTexture(self.tex, .{.x=10, .y=10}, 8);
        // 
        // for(0..3) |idx| {
        //     self.renderer.draw(self.tex, self.dest[idx], self.srcCoords[idx]);
        // }
        // 
        // 
        // // Draw sprite outlines.
        // for(0..3) |idx| {
        //     self.renderer.drawRect(self.dest[idx], Color.from(255,255,0,200), 2);
        // }
        // for(0..3) |idx| {
        //     self.renderer.drawEnclosingRect(self.dest[idx], Color.from(255,0,255,200), 2);
        // }
        // for(0..3) |idx| {
        //     self.renderer.drawFilledRect(self.destRects[idx], self.colorRects[idx]);
        // }
        //
        self.renderer.end();
        // try self.grid.draw(self.projMat);
 
    }
};

pub fn main() !void {

    std.log.info("Pixzig Grid Render Example", .{});

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Pixzig: Grid Render Example", gpa, EngOptions{});
    defer eng.deinit();

    const AppRunner = pixzig.PixzigApp(App);
    var app = try App.init(&eng, gpa);

    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
    app.deinit();
}

