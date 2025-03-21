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

const core = @import("./core.zig");

const FpsCounter = pixzig.utils.FpsCounter;

const AppRunner = pixzig.PixzigAppRunner(App, core.EngOptions);

const AtlasState = @import("./atlas_state.zig").AtlasState;
const AnimationState = @import("./animation_state.zig").AnimationState;

const AppStateMgr = GameStateMgr(AppRunner.Engine, core.AppStates, &[_]type{ AtlasState, AnimationState });

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
            self.states.setCurrState(.AtlasState);
        }
        if (eng.keyboard.pressed(.two)) {
            std.debug.print("two!\n", .{});
            self.states.setCurrState(.AnimationState);
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
    std.log.info("Pixzig Spritez Editor", .{});

    const appRunner = try AppRunner.init("Pixzig - Spritez", std.heap.c_allocator, .{});

    std.log.debug("Initializing app.\n", .{});

    var AtlasStateInst = AtlasState{};
    var AnimStateInst = AnimationState{};
    var statesArr = [_]*anyopaque{ &AtlasStateInst, &AnimStateInst };
    const states: []*anyopaque = statesArr[0..2];
    const app = try App.init(std.heap.c_allocator, states);

    glfw.swapInterval(0);
    appRunner.run(app);
}
