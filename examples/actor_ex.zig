const std = @import("std");
const pixzig = @import("pixzig");

const Frame = pixzig.sprites.Frame;
const FrameSequence = pixzig.sprites.FrameSequence;
const FrameSequenceManager = pixzig.sprites.FrameSequenceManager;

const FpsCounter = pixzig.utils.FpsCounter;
const Sprite = pixzig.sprites.Sprite;
const Actor = pixzig.sprites.Actor;
const AppRunner = pixzig.AppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    eng: *AppRunner.Engine,
    /// Owns the sprite it animates; move and draw it through `actor.sprite`.
    actor: Actor,
    seqMgr: FrameSequenceManager,
    fps: FpsCounter,
    facingLeft: bool,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        _ = try eng.resources.loadAtlas("assets/pac-tiles");

        var app = try alloc.create(App);

        app.* = .{
            .alloc = alloc,
            .eng = eng,
            .actor = Actor.init(alloc, Sprite.create(try eng.resources.getTexture("player_right_1"))),
            .seqMgr = try FrameSequenceManager.init(alloc),
            .fps = FpsCounter.init(),
            .facingLeft = false,
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

        // A quick play-once bite on the same frames. Its states name a
        // `nextState`, so the actor drops back to walking when it ends.
        var chomp = try pixzig.sprites.FrameSequence.init(alloc, &[_]Frame{
            .{ .tex = try eng.resources.acquireTexture("player_right_3"), .frameTimeMs = 60, .flip = .none },
            .{ .tex = try eng.resources.acquireTexture("player_right_2"), .frameTimeMs = 60, .flip = .none },
            .{ .tex = try eng.resources.acquireTexture("player_right_1"), .frameTimeMs = 60, .flip = .none },
            .{ .tex = try eng.resources.acquireTexture("player_right_2"), .frameTimeMs = 60, .flip = .none },
            .{ .tex = try eng.resources.acquireTexture("player_right_3"), .frameTimeMs = 60, .flip = .none },
        });
        chomp.ownsHandles = true;
        chomp.mode = .once;
        try app.seqMgr.addSeq("player_chomp", chomp);

        const walkSeq = app.seqMgr.getSeq("player_right").?;
        const chompSeq = app.seqMgr.getSeq("player_chomp").?;
        _ = try app.actor.addState(&.{ .name = "right", .sequence = walkSeq, .flip = .none }, .{});
        _ = try app.actor.addState(&.{ .name = "left", .sequence = walkSeq, .flip = .horz }, .{});
        _ = try app.actor.addState(&.{ .name = "chomp_right", .nextState = "right", .sequence = chompSeq, .flip = .none }, .{});
        _ = try app.actor.addState(&.{ .name = "chomp_left", .nextState = "left", .sequence = chompSeq, .flip = .horz }, .{});

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
            self.facingLeft = true;
            self.actor.setState("left") catch unreachable;
        }
        if (eng.inputs.keyboard.pressed(.right)) {
            spr.rotate = .none;
            self.facingLeft = false;
            self.actor.setState("right") catch unreachable;
        }
        if (eng.inputs.keyboard.pressed(.space)) {
            self.actor.setState(if (self.facingLeft) "chomp_left" else "chomp_right") catch unreachable;
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
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
