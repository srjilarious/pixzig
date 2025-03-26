const std = @import("std");
const pixzig = @import("pixzig");
const gl = pixzig.gl;
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const shaders = pixzig.shaders;
const Shader = shaders.Shader;

const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const Vec2U = pixzig.common.Vec2U;
const Vec2I = pixzig.common.Vec2I;
const FpsCounter = pixzig.utils.FpsCounter;

const GridRenderer = tile.GridRenderer;
const CharToColor = pixzig.textures.CharToColor;
const Color8 = pixzig.Color8;
const Texture = pixzig.textures.Texture;

const Path = pixzig.a_star.Path;
const AStarPathFinder = pixzig.a_star.AStarPathFinder;
const TileLayer = pixzig.tile.TileLayer;
const TileSet = pixzig.tile.TileSet;
const Tile = pixzig.tile.Tile;
const TileMapRenderer = pixzig.tile.TileMapRenderer;

const NumTilesHorz = 4;
const NumTilesVert = 4;
const TileWidth = 8;
const TileHeight = 8;

const BasicTileMapPathChecker = pixzig.a_star.BasicTileMapPathChecker;

const MapWidth = 24;
const MapHeight = 18;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    projMat: zmath.Mat,
    fps: FpsCounter,
    grid: GridRenderer,
    path: Path,
    layer: TileLayer,
    pathLayer: TileLayer,
    pathLayerRenderer: TileMapRenderer,
    tileSet: TileSet,
    checker: BasicTileMapPathChecker,
    pathFinder: AStarPathFinder(BasicTileMapPathChecker),
    tex: *Texture,
    cursorPos: Vec2I = .{ .x = 0, .y = 0 },
    startPos: Vec2I = .{ .x = 2, .y = 2 },
    endPos: Vec2I = .{ .x = 6, .y = 8 },

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        // Orthographic projection matrix
        const projMat = zmath.orthographicOffCenterLhGl(0, 200, 0, 150, -0.1, 1000);

        const shader = try Shader.init(&shaders.ColorVertexShader, &shaders.ColorPixelShader);
        const grid = try GridRenderer.init(alloc, shader, .{ .x = MapWidth, .y = MapHeight }, .{ .x = TileWidth, .y = TileHeight }, 1, Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });

        // Create a texture for the path tiles.
        const colorMap = &[_]CharToColor{
            .{ .char = '#', .color = Color8.from(180, 180, 180, 255) },
            .{ .char = '-', .color = Color8.from(80, 80, 80, 255) },
            .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
            .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
            .{ .char = '@', .color = Color8.from(30, 30, 30, 255) },
            .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
        };

        const emptyChars =
            \\        
            \\        
            \\        
            \\        
            \\        
            \\        
            \\        
            \\        
        ;
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

        const bottomLeftChars =
            \\        
            \\        
            \\#####   
            \\.....#  
            \\.....#  
            \\###..#  
            \\  #..#  
            \\  #..#  
        ;

        const bottomRightChars =
            \\        
            \\        
            \\   #####
            \\  #.....
            \\  #.....
            \\  #..###
            \\  #..#  
            \\  #..#  
        ;

        const topLeftChars =
            \\  #..#  
            \\  #..#  
            \\###..#  
            \\.....#  
            \\.....#  
            \\#####   
            \\        
            \\        
        ;

        const topRightChars =
            \\  #..#  
            \\  #..#  
            \\  #..###
            \\  #.....
            \\  #.....
            \\   #####
            \\        
            \\        
        ;

        const startChars =
            \\        
            \\   ###  
            \\  #..#  
            \\  #..#  
            \\  #..#  
            \\  #..#  
            \\   ##   
            \\        
        ;

        const endChars =
            \\        
            \\#      #
            \\ #    # 
            \\  ####  
            \\  ####  
            \\ #    # 
            \\#      #
            \\        
        ;

        const textureBuff: []u8 = try alloc.alloc(u8, (NumTilesHorz * NumTilesVert) * TileWidth * TileHeight * 4);
        defer alloc.free(textureBuff);

        const bufferSize = Vec2U{ .x = NumTilesHorz * TileWidth, .y = NumTilesVert * TileHeight };

        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, emptyChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 0, .y = 0 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, lockedChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 8, .y = 0 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, horzChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 16, .y = 0 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, vertChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 24, .y = 0 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, bottomLeftChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 0, .y = 8 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, topRightChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 8, .y = 8 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, topLeftChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 16, .y = 8 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, bottomRightChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 24, .y = 8 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, startChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 0, .y = 16 }, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, endChars, .{ .x = TileWidth, .y = TileHeight }, .{ .x = 8, .y = 16 }, colorMap);
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
            .path = Path.init(alloc),
            .layer = undefined,
            .pathLayer = undefined,
            .pathLayerRenderer = undefined,
            .tileSet = undefined,
            .checker = undefined,
            .pathFinder = undefined,
        };

        app.tileSet = try TileSet.initEmpty(alloc, .{ .x = 8, .y = 8 }, .{ .x = 32, .y = 32 }, 10);
        app.tileSet.tile(0).?.* = Tile{ .core = pixzig.tile.Clear, .properties = null, .alloc = alloc };
        app.tileSet.tile(1).?.* = Tile{ .core = pixzig.tile.BlocksAll, .properties = null, .alloc = alloc };

        app.layer = try TileLayer.initEmpty(alloc, .{ .x = MapWidth, .y = MapHeight }, .{ .x = TileWidth, .y = TileHeight });
        app.layer.tileset = &app.tileSet;

        app.layer.setTileData(1, 0, 1);
        app.layer.setTileData(2, 2, 1);
        app.layer.setTileData(3, 4, 1);
        app.layer.setTileData(5, 5, 1);
        app.layer.setTileData(5, 6, 1);
        app.layer.setTileData(4, 6, 1);
        app.layer.setTileData(7, 7, 1);

        app.pathLayer = try TileLayer.initEmpty(alloc, .{ .x = MapWidth, .y = MapHeight }, .{ .x = TileWidth, .y = TileHeight });
        app.pathLayer.tileset = &app.tileSet;

        app.pathLayerRenderer = try tile.TileMapRenderer.init(alloc, eng.renderer.impl.texShader);
        // TODO: Change to pathLayer and make wall layer renderer.
        try app.pathLayerRenderer.recreateVertices(&app.tileSet, &app.layer);

        app.checker = BasicTileMapPathChecker.init(&app.layer);
        app.pathFinder = try AStarPathFinder(BasicTileMapPathChecker).init(app.checker, alloc, .{ .x = MapWidth, .y = MapHeight });
        return app;
    }

    pub fn deinit(self: *App) void {
        self.grid.deinit();
        self.alloc.destroy(self);
    }

    fn updatePathOnMap(self: *App) !void {

        // Clear out the old path tiles.
        for (0..MapHeight) |yu| {
            for (0..MapWidth) |xu| {
                const x: i32 = @intCast(xu);
                const y: i32 = @intCast(yu);
                // 1 is the wall tile, higher are path tiles.
                if (self.layer.tileData(x, y) > 1) {
                    self.layer.setTileData(x, y, 0);
                }
            }
        }

        if (self.path.items.len > 0) {
            const first = self.path.items[0];
            self.layer.setTileData(first.x, first.y, 8);
        }

        if (self.path.items.len > 1) {
            const end = self.path.items[self.path.items.len - 1];
            self.layer.setTileData(end.x, end.y, 9);
        }

        for (1..self.path.items.len - 1) |i| {
            const prev = self.path.items[i - 1];
            const curr = self.path.items[i];
            const next = self.path.items[i + 1];

            if (curr.x < 0 or curr.y < 0) {
                break;
            }

            if (prev.x == curr.x and curr.x == next.x) {
                // Vertical line
                self.layer.setTileData(curr.x, curr.y, 3);
            } else if (prev.y == curr.y and curr.y == next.y) {
                // Horizontal line
                self.layer.setTileData(curr.x, curr.y, 2);
            } else if ((prev.isAbove(curr) and next.isRightOf(curr)) or
                (next.isAbove(curr) and prev.isRightOf(curr)))
            {
                // Top right bend
                self.layer.setTileData(curr.x, curr.y, 5);
            } else if ((prev.isLeftOf(curr) and next.isBelow(curr)) or
                (next.isLeftOf(curr) and prev.isBelow(curr)))
            {
                // Bottom left bend
                self.layer.setTileData(curr.x, curr.y, 4);
            } else if ((prev.isAbove(curr) and next.isLeftOf(curr)) or
                (next.isAbove(curr) and prev.isLeftOf(curr)))
            {
                // Top left bend
                self.layer.setTileData(curr.x, curr.y, 6);
            } else if ((prev.isBelow(curr) and next.isRightOf(curr)) or
                (next.isBelow(curr) and prev.isRightOf(curr)))
            {
                // Bottom Right bend
                self.layer.setTileData(curr.x, curr.y, 7);
            }
        }

        try self.pathLayerRenderer.recreateVertices(&self.tileSet, &self.layer);
    }

    fn refreshPath(self: *App) void {
        self.pathFinder.findPath(
            .{ .x = self.startPos.x, .y = self.startPos.y },
            .{ .x = self.endPos.x, .y = self.endPos.y },
            &self.path,
        ) catch {
            std.log.err("Unable to calculate the path!", .{});
        };

        self.updatePathOnMap() catch {
            std.log.err("Unable to render the path!", .{});
        };
        std.log.info("Path is {} nodes long", .{self.path.items.len});
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();
        if (eng.keyboard.pressed(.space)) {
            self.refreshPath();
        }

        if (eng.keyboard.pressed(.s)) {
            self.startPos = self.cursorPos;
            self.refreshPath();
        }

        if (eng.keyboard.pressed(.e)) {
            self.endPos = self.cursorPos;
            self.refreshPath();
        }

        if (eng.keyboard.pressed(.x)) {
            self.layer.setTileData(self.cursorPos.x, self.cursorPos.y, 1);
            self.refreshPath();
        }

        if (eng.keyboard.pressed(.left)) {
            if (self.cursorPos.x > 0) {
                self.cursorPos.x -= 1;
            }
        }
        if (eng.keyboard.pressed(.right)) {
            if (self.cursorPos.x < MapWidth - 1) {
                self.cursorPos.x += 1;
            }
        }
        if (eng.keyboard.pressed(.up)) {
            if (self.cursorPos.y > 0) {
                self.cursorPos.y -= 1;
            }
        }
        if (eng.keyboard.pressed(.down)) {
            if (self.cursorPos.x < MapHeight - 1) {
                self.cursorPos.y += 1;
            }
        }

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        self.fps.renderTick();

        eng.renderer.begin(self.projMat);

        eng.renderer.clear(0.0, 0.0, 0.2, 1.0);
        //eng.renderer.drawFullTexture(self.tex, .{ .x = 0, .y = 0 }, 8);

        eng.renderer.drawFilledRect(
            RectF.fromPosSize(self.cursorPos.x * TileWidth, self.cursorPos.y * TileHeight, TileWidth, TileHeight),
            Color.from(255, 255, 0, 255),
        );
        eng.renderer.end();

        try self.pathLayerRenderer.draw(self.tex, &self.layer, self.projMat);

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
