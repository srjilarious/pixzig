const std = @import("std");
const pixzig = @import("pixzig");
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

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    eng: *AppRunner.Engine,
    /// Owns the sprite it animates; move and draw it through `actor.sprite`.
    actor: Actor,
    seqMgr: FrameSequenceManager,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        _ = try eng.resources.loadAtlas("assets/pac-tiles");

        var app = try alloc.create(App);

        app.* = .{
            .alloc = alloc,
            .eng = eng,
            .actor = Actor.init(alloc, Sprite.create(try eng.resources.getTexture("player_right_1"))),
            .seqMgr = try FrameSequenceManager.init(alloc),
            .fps = FpsCounter.init(),
        };

        const fr1: Frame = .{
            .tex = try eng.resources.acquireTexture("player_right_1"),
            .frameTimeMs = 300,
            .flip = .none,
        };
        const fr2: Frame = .{
            .tex = try eng.resources.acquireTexture("player_right_2"),
            .frameTimeMs = 300,
            .flip = .none,
        };
        const fr3: Frame = .{
            .tex = try eng.resources.acquireTexture("player_right_3"),
            .frameTimeMs = 300,
            .flip = .none,
        };
        var frseq = try pixzig.sprites.FrameSequence.init(alloc, &[_]Frame{ fr1, fr2, fr3 });
        frseq.ownsHandles = true;
        try app.seqMgr.addSeq("player_right", frseq);

        _ = try app.actor.addState(&.{ .name = "right", .sequence = app.seqMgr.getSeq("player_right").?, .flip = .none }, .{});
        _ = try app.actor.addState(&.{ .name = "left", .sequence = app.seqMgr.getSeq("player_right").?, .flip = .horz }, .{});

        // Pivot on the frame's center and park it mid-screen, so flips and
        // rotations turn in place.
        app.actor.sprite.setOriginCentered();
        app.actor.sprite.setPos(50, 30);

        return app;
    }

    pub fn deinit(self: *App) void {
        self.actor.deinit();
        self.seqMgr.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        self.actor.update(30);

        const spr = &self.actor.sprite;
        if (eng.inputs.keyboard.pressed(.up)) {
            spr.rotate = .rot90;
        }
        if (eng.inputs.keyboard.pressed(.down)) {
            spr.rotate = .rot270;
        }
        if (eng.inputs.keyboard.pressed(.left)) {
            spr.rotate = .none;
            self.actor.setState("left");
        }
        if (eng.inputs.keyboard.pressed(.right)) {
            spr.rotate = .none;
            self.actor.setState("right");
        }

        if (eng.inputs.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(51, 0, 51, 255);
        self.fps.renderTick();

        eng.renderer.begin(.logical);
        eng.renderer.drawSprite(&self.actor.sprite);
        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Actor Example", .{});

    const appRunner = try AppRunner.init("Pixzig Actor Example.", init.gpa, .{ .logicalSize = .{ .x = 100, .y = 60 } });
    const app = try App.init(init.gpa, appRunner.engine);

    appRunner.run(app);
}
