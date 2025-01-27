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
const PixzigEngine = pixzig.PixzigEngine;

const States = enum {
    StateA,
    StateB,
    //StateC
};

const StateA = struct {
    delay: Delay = .{ .max = 100 },

    pub fn update(self: *StateA, eng: *PixzigEngine, delta: f64) bool {
        _ = delta;
        _ = eng;
        _ = self;
        return true;
    }

    pub fn render(self: *StateA, eng: *PixzigEngine) void {
        _ = eng;
        if (self.delay.update(1)) {
            std.debug.print("Rendering StateA.\n", .{});
        }
        //gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 1.0, 0.0, 1.0 });

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
    pub fn update(self: *ParamState, eng: *PixzigEngine, delta: f64) bool {
        _ = delta;
        _ = eng;
        _ = self;
        return true;
    }

    pub fn render(self: *ParamState, eng: *PixzigEngine) void {
        _ = eng;
        _ = self;
        std.debug.print("Rendering ParamState.\n", .{});
        //gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 1.0, 0.0, 0.0, 1.0 });
    }
};

const AppStateMgr = GameStateMgr(States, &[_]type{ StateA, ParamState });

pub const MyApp = struct {
    fps: FpsCounter,
    states: AppStateMgr,

    pub fn init(appStates: []*anyopaque) MyApp {
        return .{
            .fps = FpsCounter.init(),
            .states = AppStateMgr.init(appStates),
        };
    }

    pub fn update(self: *MyApp, eng: *pixzig.PixzigEngine, delta: f64) bool {
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

    pub fn render(self: *MyApp, eng: *pixzig.PixzigEngine) void {
        self.states.render(eng);
        self.fps.renderTick();
    }
};

const AppRunner = pixzig.PixzigApp(MyApp);
var g_AppRunner = AppRunner{};
var g_Eng: pixzig.PixzigEngine = undefined;
var g_App: MyApp = undefined;

export fn mainLoop() void {
    _ = g_AppRunner.gameLoopCore(&g_App, &g_Eng);
}

pub fn main() !void {
    std.log.info("Pixzig Sprite and Shape test!", .{});

    // var gpa_state = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
    // const gpa = gpa_state.allocator();

    g_Eng = try pixzig.PixzigEngine.init("Pixzig: Tile Render Test.", std.heap.c_allocator, EngOptions{});
    std.log.info("Pixzig engine initialized..\n", .{});

    std.debug.print("Initializing app.\n", .{});

    var StateAInst = StateA{};
    var ParamStateInst = ParamState{};
    var statesArr = [_]*anyopaque{ &StateAInst, &ParamStateInst };
    const states: []*anyopaque = statesArr[0..2];
    g_App = MyApp.init(states);

    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    if (builtin.target.os.tag == .emscripten) {
        pixzig.web.setMainLoop(mainLoop, null, false);
        std.log.debug("Set main loop.\n", .{});
    } else {
        g_AppRunner.gameLoop(&g_App, &g_Eng);
        std.log.info("Cleaning up...\n", .{});
        // g_App.deinit();
        g_Eng.deinit();
        // _ = gpa_state.deinit();
    }
}
