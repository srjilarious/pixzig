const std = @import("std");
const pixzig = @import("pixzig");

const GameStateMgr = pixzig.gamestate.GameStateMgr;

const FpsCounter = pixzig.utils.FpsCounter;

const States = enum {
    StateA,
    StateB,
    //StateC
};

// The engine owns the action map, so every state reads the same
// `eng.actions` through the engine it's handed.
const Action = enum { show_a, show_b, quit };
const AppRunner = pixzig.AppRunner(App, .{ .actionOpts = .{ .Action = Action } });

const StateA = struct {
    pub fn update(self: *StateA, eng: *AppRunner.Engine, delta: f64) bool {
        _ = delta;
        _ = eng;
        _ = self;
        return true;
    }

    pub fn render(self: *StateA, eng: *AppRunner.Engine) void {
        _ = self;
        eng.renderer.clear(0, 255, 0, 255);
    }

    pub fn activate(self: *StateA) void {
        _ = self;
        std.log.info("State A activated!\n", .{});
    }

    pub fn deactivate(self: *StateA) void {
        _ = self;
        std.log.info("State A deactivated!\n", .{});
    }
};

const ParamState = struct {
    pub fn update(self: *ParamState, eng: *AppRunner.Engine, delta: f64) bool {
        _ = delta;
        _ = eng;
        _ = self;
        return true;
    }

    pub fn render(self: *ParamState, eng: *AppRunner.Engine) void {
        _ = self;
        eng.renderer.clear(255, 0, 0, 255);
    }
};

const AppStateMgr = GameStateMgr(AppRunner.Engine, States, &[_]type{ StateA, ParamState });

pub const App = struct {
    alloc: std.mem.Allocator,
    fps: FpsCounter,
    states: AppStateMgr,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine, appStates: AppStateMgr.StatePtrs) !*App {
        try eng.actions.bind(.show_a, .{ .key = .one });
        try eng.actions.bind(.show_b, .{ .key = .two });
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
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.actions.pressed(.show_a)) {
            std.log.info("one!\n", .{});
            self.states.setCurrState(.StateA);
        }
        if (eng.actions.pressed(.show_b)) {
            std.log.info("two!\n", .{});
            self.states.setCurrState(.StateB);
        }

        if (eng.actions.pressed(.quit)) {
            return false;
        }

        return self.states.update(eng, delta);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        self.states.render(eng);
        self.fps.renderTick();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig: Game State Example", init.gpa, .{});
    defer appRunner.deinit();

    var stateA = StateA{};
    var paramState = ParamState{};

    const app = try App.init(init.gpa, appRunner.engine, .{ &stateA, &paramState });
    defer app.deinit();

    appRunner.run(app);
}
