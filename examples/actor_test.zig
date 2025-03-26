const std = @import("std");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
const shaders = pixzig.shaders;

const SpriteBatchQueue = pixzig.renderer.SpriteBatchQueue;
const RectF = pixzig.common.RectF;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const FpsCounter = pixzig.utils.FpsCounter;
const Sprite = pixzig.sprites.Sprite;
const Actor = pixzig.sprites.Actor;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    spr: Sprite,
    actor: Actor,
    frseq_1: pixzig.sprites.FrameSequence,
    frseq_2: pixzig.sprites.FrameSequence,
    projMat: zmath.Mat,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        var app = try alloc.create(App);

        const tex = try eng.textures.loadTexture("pacman_sprites", "assets/pac-tiles.png");

        const fr1: Frame = .{ .coords = RectF.fromCoords(96, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .none };
        const fr2: Frame = .{ .coords = RectF.fromCoords(112, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .none };
        const fr3: Frame = .{ .coords = RectF.fromCoords(96, 64, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .none };
        const frseq = try pixzig.sprites.FrameSequence.init("test", alloc, &[_]Frame{ fr1, fr2, fr3 });

        const fr1_2: Frame = .{ .coords = RectF.fromCoords(96, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .horz };
        const fr2_2: Frame = .{ .coords = RectF.fromCoords(112, 48, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .horz };
        const fr3_2: Frame = .{ .coords = RectF.fromCoords(96, 64, 16, 16, 128, 128), .frameTimeUs = 300, .flip = .horz };
        const frseq_2 = try pixzig.sprites.FrameSequence.init("test_left", alloc, &[_]Frame{ fr1_2, fr2_2, fr3_2 });

        app.* = .{
            .alloc = alloc,
            .spr = Sprite.create(tex, .{ .x = 16, .y = 16 }),
            .actor = try pixzig.sprites.Actor.init(alloc),
            .frseq_1 = frseq,
            .frseq_2 = frseq_2,
            .projMat = zmath.mul(zmath.scaling(4.0, 4.0, 1.0), zmath.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000)),
            .fps = FpsCounter.init(),
        };

        _ = try app.actor.addState(app.frseq_1, "right");
        _ = try app.actor.addState(app.frseq_2, "left");

        return app;
    }

    pub fn deinit(self: *App) void {
        self.actor.deinit();
        self.frseq_1.deinit();
        self.frseq_2.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        // std.log.debug("update: b\n",.{});
        eng.keyboard.update();

        self.actor.update(30, &self.spr);

        if (eng.keyboard.pressed(.up)) {
            self.spr.rotate = .rot90;
        }
        if (eng.keyboard.pressed(.down)) {
            self.spr.rotate = .rot270;
        }
        if (eng.keyboard.pressed(.left)) {
            std.log.debug("Left!\n", .{});
            self.spr.rotate = .flipHorz;
            // actor.setState("left");
        }
        if (eng.keyboard.pressed(.right)) {
            self.spr.rotate = .none;
            std.log.debug("Right!\n", .{});
            // actor.setState("right");
        }

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.2, 0, 0.2, 1);
        self.fps.renderTick();

        eng.renderer.begin(self.projMat);
        eng.renderer.drawSprite(&self.spr);
        eng.renderer.end();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Actor Example", .{});

    const alloc = std.heap.c_allocator;

    const appRunner = try AppRunner.init("Pixzig Actor Example.", alloc, .{});
    const app = try App.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}

// pub fn main() !void {
//     std.log.info("Pixzig Engine actor test!", .{});
//     var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa_state.deinit();
//     const gpa = gpa_state.allocator();

//     var eng = try pixzig.PixzigEngine.init("Pixzig Actor Test!", gpa, EngOptions{});
//     defer eng.deinit();

//     // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
//     // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

//     // Orthographic projection matrix
//     const projMat =

//     var texShader = try pixzig.shaders.Shader.init(&pixzig.shaders.TexVertexShader, &pixzig.shaders.TexPixelShader);
//     defer texShader.deinit();

//     var spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(gpa, &texShader);
//     defer spriteBatch.deinit();

//     // defer frseq_2.deinit();

//     var actor = gpa);
//     defer actor.deinit();

//     // actor.setState("test");

//     var spr = pixzig.sprites.
//     spr.setPos(32, 32);
//     fr1.apply(&spr);
//     fr2.apply(&spr);
//     fr3.apply(&spr);

//     std.debug.print("Starting main loop...\n", .{});
//     // Main loop
//     while (!eng.window.shouldClose() and eng.window.getKey(.escape) != .press) {
//         glfw.pollEvents();

//         eng.keyboard.update();

//         gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.0, 1.0 });

//         spriteBatch.begin(projMat);
//         actor.update(30, &spr);
//         spriteBatch.drawSprite(&spr);
//         spriteBatch.end();

//         eng.window.swapBuffers();
//     }
// }
