const std = @import("std");
const pixzig = @import("pixzig");
const zmath = pixzig.zmath;
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Delay = pixzig.utils.Delay;

const GameStateMgr = pixzig.gamestate.GameStateMgr;

const math = @import("zmath");
const EngOptions = pixzig.EngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;

const States = enum {
    StateA,
    StateB,
    //StateC
};

const AppRunner = pixzig.AppRunner(App, .{});

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

    pub fn init(alloc: std.mem.Allocator, appStates: []*anyopaque) !*App {
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

        if (eng.inputs.keyboard.pressed(.one)) {
            std.log.info("one!\n", .{});
            self.states.setCurrState(.StateA);
        }
        if (eng.inputs.keyboard.pressed(.two)) {
            std.log.info("two!\n", .{});
            self.states.setCurrState(.StateB);
        }
        if (eng.inputs.keyboard.pressed(.three)) std.log.info("three!\n", .{});

        if (eng.inputs.keyboard.pressed(.escape)) {
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

    var StateAInst = StateA{};
    var ParamStateInst = ParamState{};
    var statesArr = [_]*anyopaque{ &StateAInst, &ParamStateInst };
    const states: []*anyopaque = statesArr[0..2];

    const app = try App.init(init.gpa, states);
    defer app.deinit();

    appRunner.run(app);
}
