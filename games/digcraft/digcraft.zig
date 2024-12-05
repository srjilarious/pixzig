// zig fmt: off
// DigCraft - A 2d Minecraft-inspired game.

// TODO list:
// - Change to real texture
// - Change to 16x16 blocks
// - camera and larger world.
// - different blocks
// - world seeding
// - world simulation steps
// - 

const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import ("zstbi");
const zmath = @import("zmath"); 
const pixzig = @import("pixzig");
const flecs = @import("zflecs"); 

const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const shaders = pixzig.shaders;
const Shader = shaders.Shader;
const Sprite = pixzig.sprites.Sprite;

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

const entities = @import("./entities.zig");
const Player = entities.Player;
const Mover = entities.Mover;

const C = @import("./constants.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    projMat: zmath.Mat,
    renderer: Renderer,
    fps: FpsCounter,
    mouse: pixzig.input.Mouse,
    grid: GridRenderer,
    tex: *Texture,
    map: tile.TileMap,
    mapRenderer: tile.TileMapRenderer,
    texShader: pixzig.shaders.Shader,
    colorShader: pixzig.shaders.Shader,
    world: *flecs.world_t,
    update_query: *flecs.query_t,
    draw_query: *flecs.query_t,

    pub fn init(eng: *pixzig.PixzigEngine, alloc: std.mem.Allocator) !App {
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        const renderer = try Renderer.init(alloc, .{});

        const colorShader = try Shader.init(
                &shaders.ColorVertexShader,
                &shaders.ColorPixelShader
            );
        const grid = try GridRenderer.init(alloc, colorShader, .{ .x = C.MapWidth, .y = C.MapHeight}, .{ .x = C.TileWidth*C.Scale, .y = C.TileHeight*C.Scale}, 1, Color{.r=0.5, .g=0.0, .b=0.5, .a=1});

        // Create a texture for the path tiles.
        const colorMap = &[_]CharToColor{
            .{ .char = '#', .color = Color8.from(180, 180, 180, 255) },
            .{ .char = '-', .color = Color8.from(80, 80, 80, 255) },
            .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
            .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
            .{ .char = '@', .color = Color8.from(30, 30, 30, 255) },
            .{ .char = 'h', .color = Color8.from(200, 150, 60, 255) },
            .{ .char = 'e', .color = Color8.from(50, 150, 255, 255) },
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
        \\                
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
        \\=--------------=
        \\-##############-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-#############=-
        \\-##########===@-
        \\=--------------=
        ;
 
    
        
        const textureBuff: []u8 = try alloc.alloc(u8, (C.NumTilesHorz*C.NumTilesVert)*C.TileWidth*C.TileHeight*4);
        defer alloc.free(textureBuff);

        const bufferSize = Vec2U{.x = C.NumTilesHorz*C.TileWidth, .y=C.NumTilesVert*C.TileHeight};

        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, emptyChars, .{.x=C.TileWidth, .y=C.TileHeight}, .{.x=0, .y=0}, colorMap);
        pixzig.textures.drawBufferFromChars(textureBuff, bufferSize, lockedChars, .{.x=C.TileWidth, .y=C.TileHeight}, .{.x=16, .y=0}, colorMap);


        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        const tex = try eng.textures.loadTextureFromBuffer("a_star", bufferSize.x, bufferSize.y, textureBuff);

        // Create base map and renderer
        const texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader
        );

        var map = try tile.TileMap.init(alloc);
        const tileset = try tile.TileSet.initEmpty(alloc, .{ .x = C.TileWidth, .y = C.TileHeight }, .{ .x=C.NumTilesHorz*C.TileWidth, .y=C.NumTilesVert*C.TileHeight}, C.NumTilesHorz*C.NumTilesVert);
        const layer = try tile.TileLayer.initEmpty(alloc, .{ .x=C.MapWidth, .y=C.MapHeight}, .{.x=C.TileWidth, .y=C.TileHeight});
        try map.layers.append(layer);
        try map.tilesets.append(tileset);
        map.layers.items[0].tileset = &map.tilesets.items[0];

        var mapRender = try tile.TileMapRenderer.init(std.heap.page_allocator, texShader);

        // Create some tiles for the tile set
        const WallIdx = 1;
        map.tilesets.items[0].tile(WallIdx).?.* = .{.core = tile.BlocksAll, .properties = null, .alloc = alloc};

        const idxs = [_]usize{0, 1, 2, 12, 45, 23, 140, 213, 313, 480};
        for(idxs) |idx| {
            map.layers.items[0].tiles.items[idx] = WallIdx;
        }

        for(0..C.MapWidth) |idx| {
            map.layers.items[0].tiles.items[(C.MapHeight-1)*C.MapWidth+idx] = WallIdx;
        }

        
        try mapRender.recreateVertices(&map.tilesets.items[0], &map.layers.items[0]);
        
        // Setup world and entities
        const world = flecs.init();
        entities.setupEntities(world);

        const update_query = try flecs.query_init(world, &.{
            .filter = .{
                .terms = [_]flecs.term_t{
                    .{ .id = flecs.id(Sprite) },
                    .{ .id = flecs.id(Mover) },
                } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_DESC_MAX - 2),
            },
        });

        const draw_query = try flecs.query_init(world, &.{
            .filter = .{
                .terms = [_]flecs.term_t{
                    .{ .id = flecs.id(Sprite) },
                } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_DESC_MAX - 1),
            },
        });


        const playerTex = eng.textures.loadTexture("player", "assets/remi.png") catch unreachable;

        entities.spawn(world, .Player, playerTex, 8);

        map.layers.items[0].dumpLayer();
        
        // Create application.
        return .{
            .allocator = alloc,
            .projMat = projMat,
            // .scrollOffset = .{ .x = 0, .y = 0}, 
            .renderer = renderer,
            .fps = FpsCounter.init(),
            .grid = grid,
            .mouse = pixzig.input.Mouse.init(eng.window, eng.allocator),
            .tex= tex,
            .texShader = texShader,
            .colorShader = colorShader,
            .map = map,
            .mapRenderer = mapRender,
            .world = world,
            .update_query = update_query,
            .draw_query = draw_query,
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.grid.deinit();
        self.map.deinit();
        self.mapRenderer.deinit();
        self.colorShader.deinit();
        self.texShader.deinit();
        _ = flecs.fini(self.world);
        // TODO: deinit queries too.
    }

    pub fn update(self: *App, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();
        self.mouse.update();

        var it = flecs.query_iter(self.world, self.update_query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 1).?;
            const vel = flecs.field(&it, Mover, 2).?;

            //const entities = it.entities();
            for (0..it.count()) |idx| {

                var v: *Mover = &vel[idx];
                var sp: *Sprite = &spr[idx];
                v.speed.y += 0.08;
                if(v.speed.y > 4.0) {
                    v.speed.y = 4.0;
                }

                if(v.speed.y > 0) {
                    if(pixzig.tile.Mover.moveDown(&sp.dest, v.speed.y, &self.map.layers.items[0], pixzig.tile.BlocksAll)) {
                        v.speed.y = 0;
                        v.inAir = false;
                    }
                    else {
                        v.inAir = true;
                    }
                }
                else {
                    if(pixzig.tile.Mover.moveUp(&sp.dest, -v.speed.y, &self.map.layers.items[0], pixzig.tile.BlocksAll)) {
                        v.speed.y = 0;
                    }
                }

                if(!v.inAir and eng.keyboard.down(.up)) {
                    std.debug.print("YEET!\n", .{});
                    v.speed.y = -3;
                    v.inAir = true;
                }

                // Handle guy movement.
                if (eng.keyboard.down(.left)) {
                    _ = pixzig.tile.Mover.moveLeft(&sp.dest, 2, &self.map.layers.items[0], pixzig.tile.BlocksAll);
                }
                if (eng.keyboard.down(.right)) {
                    _ = pixzig.tile.Mover.moveRight(&sp.dest, 2, &self.map.layers.items[0], pixzig.tile.BlocksAll);
                }

                if(self.mouse.down(.left)) {
                    v.speed.y = 0;
                    const mousePos = self.mouse.pos().asVec2I();
                    sp.setPos(
                        @divFloor(mousePos.x,C.Scale), 
                        @divFloor(mousePos.y,C.Scale)
                    );
                }
                sp.dest.ensureSize(@as(i32, @intFromFloat(sp.size.x)), @as(i32, @intFromFloat(sp.size.y)));

                //spr[idx].draw(&self.spriteBatch) catch {};

                //const e = entities[idx];

                // const outline = flecs.get(self.world, e, DebugOutline);
                // if(outline != null) {
                //     self.shapeBatch.drawEnclosingRect(spr[idx].dest, outline.?.color, 2);
                // }
            }
        }
        


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
      
        const mvp = zmath.mul(zmath.scaling(C.Scale, C.Scale, 1.0), self.projMat);
        try self.mapRenderer.draw(self.tex, &self.map.layers.items[0], mvp);

        try self.grid.draw(self.projMat);

        self.renderer.begin(mvp);

        var it = flecs.query_iter(self.world, self.draw_query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 1).?;
            //const debug = flecs.field(&it, DebugOutline, 2).?;

            // const ents = it.entities();
            for (0..it.count()) |idx| {
                self.renderer.drawSprite(&spr[idx]);
                self.renderer.drawEnclosingRect(spr[idx].dest, Color.from(255, 0, 255, 255), 1);

                // spr[idx].draw(&self.spriteBatch) catch {};
                // const e = ents[idx];

                // const outline = flecs.get(self.world, e, DebugOutline);
                // if(outline != null) {
                //     self.renderer.drawEnclosingRect(spr[idx].dest, outline.?.color, 2);
                // }
            }
        }

        self.renderer.end();
 
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

