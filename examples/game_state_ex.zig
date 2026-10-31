const std = @import("std");
const pixzig = @import("pixzig");

const GameStateMgr = pixzig.gamestate.GameStateMgr;
const Color = pixzig.Color;
const RectF = pixzig.RectF;

const FpsCounter = pixzig.utils.FpsCounter;

// 1 and 2 switch between two scenes (replacing the whole stack). P pushes
// a pause overlay over whichever scene is showing: the scene keeps
// rendering underneath, dimmed, but stops updating until P pops it.
const States = enum {
    StateA,
    StateB,
    Pause,
};

// The engine owns the action map, so every state reads the same
// `eng.actions` through the engine it's handed.
const Action = enum { show_a, show_b, pause, quit };
const AppRunner = pixzig.AppRunner(App, .{ .actionOpts = .{ .Action = Action } });

/// A scene with a box sliding across it, so it's visible when updates stop.
const StateA = struct {
    x: f32 = 0,

    pub fn update(self: *StateA, eng: *AppRunner.Engine, delta: f64) void {
        _ = eng;
        self.x = @mod(self.x + @as(f32, @floatCast(delta)) * 0.2, 800);
    }

    pub fn render(self: *StateA, eng: *AppRunner.Engine, alpha: f32) void {
        _ = alpha;
        eng.renderer.clear(0, 160, 0, 255);
        eng.renderer.begin(.logical);
        eng.renderer.drawFilledRect(RectF.fromPosSize(self.x, 280, 40, 40), Color.white);
        _ = eng.renderer.drawString("State A", .{ .x = 20, .y = 20 });
        eng.renderer.end();
    }

    pub fn activate(self: *StateA) void {
        _ = self;
        std.log.info("State A activated", .{});
    }

    pub fn deactivate(self: *StateA) void {
        _ = self;
        std.log.info("State A deactivated", .{});
    }

    pub fn pause(self: *StateA) void {
        _ = self;
        std.log.info("State A paused", .{});
    }

    pub fn @"resume"(self: *StateA) void {
        _ = self;
        std.log.info("State A resumed", .{});
    }
};

const ParamState = struct {
    pub fn update(self: *ParamState, eng: *AppRunner.Engine, delta: f64) void {
        _ = delta;
        _ = eng;
        _ = self;
    }

    pub fn render(self: *ParamState, eng: *AppRunner.Engine, alpha: f32) void {
        _ = alpha;
        _ = self;
        eng.renderer.clear(255, 0, 0, 255);
        eng.renderer.begin(.logical);
        _ = eng.renderer.drawString("State B", .{ .x = 20, .y = 20 });
        eng.renderer.end();
    }
};

/// Pushed over a scene: dims it and draws a label. It has no update work
/// of its own; the manager simply stops updating the scene below.
const PauseState = struct {
    pub fn update(self: *PauseState, eng: *AppRunner.Engine, delta: f64) void {
        _ = delta;
        _ = eng;
        _ = self;
    }

    pub fn render(self: *PauseState, eng: *AppRunner.Engine, alpha: f32) void {
        _ = alpha;
        _ = self;
        eng.renderer.fade(Color.black, 0.6);
        eng.renderer.begin(.logical);
        _ = eng.renderer.drawText("PAUSED - press P", .{ .x = 400, .y = 290 }, .{ .@"align" = .center });
        eng.renderer.end();
    }
};

const AppStateMgr = GameStateMgr(AppRunner.Engine, States, &[_]type{ StateA, ParamState, PauseState });

pub const App = struct {
    alloc: std.mem.Allocator,
    fps: FpsCounter,
    states: AppStateMgr,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine, appStates: AppStateMgr.StatePtrs) !*App {
        try eng.actions.bind(.show_a, .{ .key = .one });
        try eng.actions.bind(.show_b, .{ .key = .two });
        try eng.actions.bind(.pause, .{ .key = .p });
        try eng.actions.bind(.quit, .{ .key = .escape });

        const app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .fps = FpsCounter.init(),
            .states = AppStateMgr.init(appStates),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.states.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) void {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.actions.pressed(.show_a)) self.states.setCurrState(.StateA);
        if (eng.actions.pressed(.show_b)) self.states.setCurrState(.StateB);

        if (eng.actions.pressed(.pause)) {
            if (self.states.current() == .Pause) {
                self.states.pop() catch unreachable; // Pause is never the bottom state here
            } else {
                // Render the scene underneath, but freeze it.
                self.states.push(.Pause, .{ .renderBelow = true, .updateBelow = false }) catch unreachable;
            }
        }

        if (eng.actions.pressed(.quit)) {
            eng.quit();
            return;
        }

        self.states.update(eng, delta);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine, alpha: f32) void {
        self.states.render(eng, alpha);
        self.fps.renderTick();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig: Game State Example", init.gpa, .{});
    defer appRunner.deinit();

    var stateA = StateA{};
    var paramState = ParamState{};
    var pauseState = PauseState{};

    const app = try App.init(init.gpa, appRunner.engine, .{ &stateA, &paramState, &pauseState });
    defer app.deinit();

    appRunner.run(app);
}
