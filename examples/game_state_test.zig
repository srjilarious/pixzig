// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

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

    pub fn update(self: *StateA, eng: *PixzigEngine, delta: f64) bool {
        _ = delta;
        _ = eng;
        _ = self;
        return true;
    }

    pub fn render(self: *StateA, eng: *PixzigEngine) void {
        _ = eng;
        _ = self;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 1.0, 0.0, 1.0 });

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
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 1.0, 0.0, 0.0, 1.0 });
    }
};



const AppStateMgr = GameStateMgr(States, &[_]type{StateA, ParamState});

pub const MyApp = struct {
    testVal: i32,
    fps: FpsCounter,
    states: AppStateMgr,

    pub fn init(val: i32, appStates: []*anyopaque) MyApp {
        return .{ 
            .testVal = val, 
            .fps = FpsCounter.init(),
            .states = AppStateMgr.init(appStates),
        };
    }

    pub fn update(self: *MyApp, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
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
        if (eng.keyboard.pressed(.left)) {
            std.debug.print("Left!\n", .{});
            self.testVal -= 1;
        }
        if (eng.keyboard.pressed(.right)) {
            std.debug.print("Right!\n", .{});
            self.testVal += 1;
        }
        if( eng.keyboard.pressed(.space)) {
            std.debug.print("Context: {}\n", .{self.testVal});
        }
        if(eng.keyboard.pressed(.escape)) {
            return false;
        }

        return self.states.update(eng, delta);
    }

    pub fn render(self: *MyApp, eng: *pixzig.PixzigEngine) void {
        self.states.render(eng);
        self.fps.renderTick();
    }
};



pub fn main() !void {

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Glfw Eng Test.", gpa, EngOptions{});
    defer eng.deinit();


    const AppRunner = pixzig.PixzigApp(MyApp);

    var StateAInst = StateA{};
    var ParamStateInst = ParamState{};
    var statesArr = [_]*anyopaque {&StateAInst, &ParamStateInst};
    const states: []*anyopaque = statesArr[0..2];
    var app = MyApp.init(123, states);

    glfw.swapInterval(0);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
}

