// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
const zmath = @import("zmath"); 
const flecs = @import("zflecs"); 
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2F = pixzig.common.Vec2F;
const FpsCounter = pixzig.utils.FpsCounter;
const Sprite = pixzig.sprites.Sprite;

pub const Player = struct{
    alive: bool
};
pub const DebugOutline = struct{
    color: Color
};

pub const Dot = struct{};

pub const App = struct {
    allocator: std.mem.Allocator,
    projMat: zmath.Mat,
    scrollOffset: Vec2F,
    spriteBatch: pixzig.renderer.SpriteBatchQueue,
    shapeBatch: pixzig.renderer.ShapeBatchQueue,
    tex: *pixzig.Texture,
    texShader: pixzig.shaders.Shader,
    colorShader: pixzig.shaders.Shader,
    fps: FpsCounter,
    world: *flecs.world_t,
    draw_query: *flecs.query_t,
    
    pub fn init(eng: *pixzig.PixzigEngine, alloc: std.mem.Allocator) !App {
        // Orthographic projection matrix
        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        var texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader
        );

        const tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");
       
        const spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(alloc, &texShader);

        var colorShader = try pixzig.shaders.Shader.init(
                &pixzig.shaders.ColorVertexShader,
                &pixzig.shaders.ColorPixelShader
            );

        const shapeBatch = try pixzig.renderer.ShapeBatchQueue.init(alloc, &colorShader);
        std.debug.print("Done creating tile renderering data.\n", .{});

        const world = flecs.init();

        flecs.COMPONENT(world, Player);
        flecs.COMPONENT(world, Sprite);
        flecs.COMPONENT(world, DebugOutline);

        const query = try flecs.query_init(world, &.{
            .filter = .{
                .terms = [_]flecs.term_t{
                    .{ .id = flecs.id(Sprite) },
                } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_DESC_MAX - 1),
            },
        });


        var app = App{
            .allocator = alloc,
            .projMat = projMat,
            .scrollOffset = .{ .x = 0, .y = 0}, 
            .spriteBatch = spriteBatch,
            .shapeBatch = shapeBatch,
            .tex = tex,
            .texShader = texShader,
            .colorShader = colorShader,
            .fps = FpsCounter.init(),
            .world = world,
            .draw_query = query,
        };

        app.spawn(1, 10, 50, true);
        app.spawn(6, 300, 210, false);
        app.spawn(11, 15, 320, false);
        app.spawn(23, 150, 480, true);

        return app;
    }

    pub fn deinit(self: *App) void {
        self.spriteBatch.deinit();
        self.shapeBatch.deinit();
        self.colorShader.deinit();
        self.texShader.deinit();

        flecs.query_fini(self.draw_query);
        _ = flecs.fini(self.world);
    }

    pub fn spawn(self: *App, which: usize, x: i32, y: i32, val: bool) void
    {
        const ent = flecs.new_id(self.world);
        const srcX: i32 = @intCast(32*@rem(which, 16));
        const srcY:i32 = @intCast(32*@divTrunc(which, 16));
        var spr = Sprite.create(
                self.tex, 
                .{ .x = 32, .y = 32}, 
                RectF.fromCoords(srcX, srcY, 32, 32, 512, 512));

        spr.setPos(x, y);
        _ = flecs.set(self.world, ent, Sprite, spr);

        
        if(val) {
            _ = flecs.set(self.world, ent, DebugOutline, .{ .color = Color.from(100, 255, 200, 220)});
        }
    }

    pub fn update(self: *App, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
        const ScrollAmount = 3;
        if (eng.keyboard.down(.left)) {
            self.scrollOffset.x += ScrollAmount;
        }
        if (eng.keyboard.down(.right)) {
            self.scrollOffset.x -= ScrollAmount;
        }
        if (eng.keyboard.down(.up)) {
            self.scrollOffset.y += ScrollAmount;
        }
        if (eng.keyboard.down(.down)) {
            self.scrollOffset.y -= ScrollAmount;
        }
        if(eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.2, 1.0 });
        self.fps.renderTick();
       
        self.spriteBatch.begin(self.projMat);
        self.shapeBatch.begin(self.projMat);

        var it = flecs.query_iter(self.world, self.draw_query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 1).?;
            //const debug = flecs.field(&it, DebugOutline, 2).?;

            const entities = it.entities();
            for (0..it.count()) |idx| {
                spr[idx].draw(&self.spriteBatch) catch {};
                const e = entities[idx];

                const outline = flecs.get(self.world, e, DebugOutline);
                if(outline != null) {
                    self.shapeBatch.drawEnclosingRect(spr[idx].dest, outline.?.color, 2);
                }
            }
        }

        self.spriteBatch.end();
        self.shapeBatch.end();
    }
};

pub fn main() !void {

    std.log.info("Pixzig Flecs test!", .{});

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Pixzig: Flecs Test.", gpa, EngOptions{});
    defer eng.deinit();

    const AppRunner = pixzig.PixzigApp(App);
    var app = try App.init(&eng, gpa);

    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
    app.deinit();
}





    // gl.enable(gl.BLEND);
    // gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    // gl.enable(gl.TEXTURE_2D);


