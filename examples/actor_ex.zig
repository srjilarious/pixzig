const std = @import("std");
const pixzig = @import("pixzig");

const Frame = pixzig.sprites.Frame;
const FrameSequence = pixzig.sprites.FrameSequence;
const FrameSequenceManager = pixzig.sprites.FrameSequenceManager;

const FpsCounter = pixzig.utils.FpsCounter;
const Sprite = pixzig.sprites.Sprite;
const Actor = pixzig.sprites.Actor;

// The engine owns the action map (`eng.actions`) and updates it each tick.
const Action = enum { face_up, face_down, face_left, face_right, chomp, quit };
const AppRunner = pixzig.AppRunner(App, .{ .actionOpts = .{ .Action = Action }, .screenshotHook = true });

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

        try eng.actions.bind(.face_up, .{ .key = .up });
        try eng.actions.bind(.face_down, .{ .key = .down });
        try eng.actions.bind(.face_left, .{ .key = .left });
        try eng.actions.bind(.face_right, .{ .key = .right });
        try eng.actions.bind(.chomp, .{ .key = .space });
        try eng.actions.bind(.quit, .{ .key = .escape });

        var app = try alloc.create(App);

        app.* = .{
            .alloc = alloc,
            .eng = eng,
            .actor = Actor.init(alloc, Sprite.create(try eng.resources.getTexture("player_right_1"))),
            .seqMgr = try FrameSequenceManager.init(alloc),
            .fps = FpsCounter.init(),
            .facingLeft = false,
        };

        const fr1: Frame = .{ .tex = try eng.resources.getTexture("player_right_1"), .frameTimeMs = 300 };
        const fr2: Frame = .{ .tex = try eng.resources.getTexture("player_right_2"), .frameTimeMs = 300 };
        const fr3: Frame = .{ .tex = try eng.resources.getTexture("player_right_3"), .frameTimeMs = 300 };
        const frseq = try pixzig.sprites.FrameSequence.init(alloc, &[_]Frame{ fr1, fr2, fr3 });
        try app.seqMgr.addSeq("player_right", frseq);

        // A quick play-once bite on the same frames. Its states name a
        // `nextState`, so the actor drops back to walking when it ends.
        var chomp = try pixzig.sprites.FrameSequence.init(alloc, &[_]Frame{
            .{ .tex = try eng.resources.getTexture("player_right_3"), .frameTimeMs = 400 },
            .{ .tex = try eng.resources.getTexture("player_right_2"), .frameTimeMs = 400 },
            .{ .tex = try eng.resources.getTexture("player_right_1"), .frameTimeMs = 400 },
            .{ .tex = try eng.resources.getTexture("player_right_2"), .frameTimeMs = 400 },
            .{ .tex = try eng.resources.getTexture("player_right_3"), .frameTimeMs = 400 },
        });
        chomp.mode = .once;
        try app.seqMgr.addSeq("player_chomp", chomp);

        // States are shared data: register them once with the manager, and
        // actors point at them.
        const walkSeq = app.seqMgr.getSeq("player_right").?;
        const chompSeq = app.seqMgr.getSeq("player_chomp").?;
        try app.seqMgr.addState(.{ .name = "right", .sequence = walkSeq });
        try app.seqMgr.addState(.{ .name = "left", .sequence = walkSeq, .flipX = true });
        try app.seqMgr.addState(.{ .name = "chomp_right", .sequence = chompSeq });
        try app.seqMgr.addState(.{ .name = "chomp_left", .sequence = chompSeq, .flipX = true });
        for ([_][]const u8{ "right", "left", "chomp_right", "chomp_left" }) |name| {
            _ = try app.actor.addState(app.seqMgr.getState(name).?, .{});
        }

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

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) void {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        self.actor.update(30);

        const spr = &self.actor.sprite;
        const actions = eng.actions;
        if (actions.pressed(.face_up)) {
            spr.rotate = .rot90;
        }
        if (actions.pressed(.face_down)) {
            spr.rotate = .rot270;
        }
        if (actions.pressed(.face_left)) {
            spr.rotate = .none;
            self.facingLeft = true;
            self.actor.setState("left", .{}) catch unreachable;
        }
        if (actions.pressed(.face_right)) {
            spr.rotate = .none;
            self.facingLeft = false;
            self.actor.setState("right", .{}) catch unreachable;
        }
        if (actions.pressed(.chomp)) {
            self.actor.setState(if (self.facingLeft) "chomp_left" else "chomp_right", .{ .reset = true }) catch unreachable;
        }

        if (actions.pressed(.quit)) {
            eng.quit();
            return;
        }
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
