const std = @import("std");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
const shaders = pixzig.shaders;
const stbi = @import("zstbi");

const SpriteBatchQueue = pixzig.renderer.SpriteBatchQueue;
const RectF = pixzig.common.RectF;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const FrameSequence = pixzig.sprites.FrameSequence;
const FrameSequenceManager = pixzig.sprites.FrameSequenceManager;
const ActorState = pixzig.sprites.ActorState;

const FpsCounter = pixzig.utils.FpsCounter;
const Sprite = pixzig.sprites.Sprite;
const Actor = pixzig.sprites.Actor;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{ .gameScale = 8.0 });

pub const App = struct {
    alloc: std.mem.Allocator,
    spr: Sprite,
    actor: Actor,
    seqMgr: FrameSequenceManager,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        _ = try eng.resources.loadAtlas("assets/pac-tiles");

        var app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .spr = Sprite.create(try eng.resources.getTexture("player_right_1"), .{ .x = 16, .y = 16 }),
            .actor = try pixzig.sprites.Actor.init(alloc),
            .seqMgr = try FrameSequenceManager.init(alloc),
            .fps = FpsCounter.init(),
        };

        const fr1: Frame = .{
            .tex = try eng.resources.getTexture("player_right_1"),
            .frameTimeMs = 300,
            .flip = .none,
        };
        const fr2: Frame = .{
            .tex = try eng.resources.getTexture("player_right_2"),
            .frameTimeMs = 300,
            .flip = .none,
        };
        const fr3: Frame = .{
            .tex = try eng.resources.getTexture("player_right_3"),
            .frameTimeMs = 300,
            .flip = .none,
        };
        const frseq = try pixzig.sprites.FrameSequence.init(alloc, &[_]Frame{ fr1, fr2, fr3 });
        try app.seqMgr.addSeq("player_right", frseq);

        _ = try app.actor.addState(&.{ .name = "right", .sequence = app.seqMgr.getSeq("player_right").?, .flip = .none }, .{});
        _ = try app.actor.addState(&.{ .name = "left", .sequence = app.seqMgr.getSeq("player_right").?, .flip = .horz }, .{});

        return app;
    }

    pub fn deinit(self: *App) void {
        self.actor.deinit();
        // self.frseq_1.deinit();
        // self.frseq_2.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

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

        eng.renderer.begin(eng.projMat);
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
