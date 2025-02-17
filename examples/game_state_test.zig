const std = @import("std");
const builtin = @import("builtin");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import("zstbi");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Delay = pixzig.utils.Delay;

const GameStateMgr = pixzig.gamestate.GameStateMgr;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;

const States = enum {
    StateA,
    StateB,
    //StateC
};

const AppRunner = pixzig.PixzigAppRunner(App, .{});

const StateA = struct {
    pub fn update(self: *StateA, eng: *AppRunner.Engine, delta: f64) bool {
        _ = delta;
        _ = eng;
        _ = self;
        return true;
    }

    pub fn render(self: *StateA, eng: *AppRunner.Engine) void {
        _ = self;
        eng.renderer.clear(0, 1, 0, 1);
    }

    pub fn activate(self: *StateA) void {
        _ = self;
        std.debug.print("State A activated!\n", .{});
    }

    pub fn deactivate(self: *StateA) void {
        _ = self;
        std.debug.print("State A deactivated!\n", .{});
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
        eng.renderer.clear(1, 0, 0, 1);
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
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) {
            std.debug.print("one!\n", .{});
            self.states.setCurrState(.StateA);
        }
        if (eng.keyboard.pressed(.two)) {
            std.debug.print("two!\n", .{});
            self.states.setCurrState(.StateB);
        }
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});

        if (eng.keyboard.pressed(.escape)) {
            return false;
        }

        return self.states.update(eng, delta);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        self.states.render(eng);
        self.fps.renderTick();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Game State test!", .{});

    const appRunner = try AppRunner.init("Pixzig: Tile Render Test.", std.heap.c_allocator, .{});

    std.log.debug("Initializing app.\n", .{});

    var StateAInst = StateA{};
    var ParamStateInst = ParamState{};
    var statesArr = [_]*anyopaque{ &StateAInst, &ParamStateInst };
    const states: []*anyopaque = statesArr[0..2];
    const app = try App.init(std.heap.c_allocator, states);

    glfw.swapInterval(0);
    appRunner.run(app);
}
