const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import("zstbi");
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

const GridRenderer = tile.GridRenderer;
const CharToColor = pixzig.textures.CharToColor;
const Color8 = pixzig.Color8;
const Texture = pixzig.textures.Texture;

const NumTilesHorz = 4;
const NumTilesVert = 4;
const TileWidth = 8;
const TileHeight = 8;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    projMat: zmath.Mat,
    fps: FpsCounter,
    grid: GridRenderer,
    tex: *Texture,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const shader = try Shader.init(&shaders.ColorVertexShader, &shaders.ColorPixelShader);
        const grid = try GridRenderer.init(alloc, shader, .{ .x = 20, .y = 12 }, .{ .x = 32, .y = 32 }, 1, Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });

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

        const horzChars =
            \\        
            \\        
            \\########
            \\........
            \\........
            \\########
            \\        
            \\        
        ;

        const vertChars =
            \\  #..#  
            \\  #..#  
            \\  #..#  
            \\  #..#  
            \\  #..#  
            \\  #..#  
            \\  #..#  
            \\  #..#  
        ;

        const topRightChars =
            \\        
            \\        
            \\#####   
            \\.....#  
            \\.....#  
            \\###..#  
            \\  #..#  
            \\  #..#  
        ;

        const topLeftChars =
            \\        
            \\        
            \\   #####
            \\  #.....
            \\  #.....
            \\  #..###
            \\  #..#  
            \\  #..#  
        ;

        const bottomRightChars =
            \\  #..#  
            \\  #..#  
            \\###..#  
            \\.....#  
            \\.....#  
            \\#####   
            \\        
            \\        
        ;

        const bottomLeftChars =
            \\  #..#  
            \\  #..#  
            \\  #..###
            \\  #.....
            \\  #.....
            \\   #####
            \\        
            \\        
        ;

        const textureBuff: []u8 = try alloc.alloc(u8, (NumTilesHorz * NumTilesVert) * TileWidth * TileHeight * 4);
        defer alloc.free(textureBuff);

        const bufferSize = Vec2U{ .x = NumTilesHorz * TileWidth, .y = NumTilesVert * TileHeight };

        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, lockedChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 0, .y = 0 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, horzChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 8, .y = 0 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, vertChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 16, .y = 0 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, topLeftChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 24, .y = 0 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, topRightChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 0, .y = 8 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, bottomLeftChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 8, .y = 8 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, bottomRightChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 16, .y = 8 }, colorMap);
        // const wallTex = try eng.textures.createTextureFromChars("wall", 8, 8, lockedChars, );

        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        const tex = try eng.textures.loadTextureFromBuffer("a_star", bufferSize.x, bufferSize.y, textureBuff);
        app.* = .{
            .alloc = alloc,
            .projMat = projMat,
            .fps = FpsCounter.init(),
            .grid = grid,
            .tex = tex,
        };

        return app;
    }

    pub fn deinit(self: *App) void {
        self.grid.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();
        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        self.fps.renderTick();

        eng.renderer.begin(self.projMat);

        eng.renderer.clear(0.0, 0.0, 0.2, 1.0);
        eng.renderer.drawFullTexture(self.tex, .{ .x = 0, .y = 0 }, 8);

        eng.renderer.end();

        try self.grid.draw(self.projMat);
    }
};

pub fn main() !void {
    std.log.info("Pixzig A* path example!", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig A* Path Example.", alloc, .{});
    const app = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
