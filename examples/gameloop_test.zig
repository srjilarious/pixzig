// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import ("zstbi");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;
const Delay = pixzig.utils.Delay;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;

pub const panic = pixzig.panic;
pub const std_options = std.Options{
    .logFn = pixzig.log,
};

pub const MyApp = struct {
    testVal: i32,
    fps: FpsCounter,
    delay: Delay = .{ .max = 120 },

    pub fn init(val: i32) MyApp {
        return .{ 
            .testVal = val, 
            .fps = FpsCounter.init() 
        };
    }

    pub fn update(self: *MyApp, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        // std.log.debug("update: b\n",.{});
        eng.keyboard.update();

        // std.log.debug("update: c\n",.{});
        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
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
        return true;
    }

    pub fn render(self: *MyApp, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        if(self.delay.update(1)) {
            std.debug.print("render tick!\n", .{});
        }

        gl.clearColor(0, 0, 1, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);
        self.fps.renderTick();
    }
};

const AppRunner =  pixzig.PixzigApp(MyApp);
var g_AppRunner = AppRunner{};
var g_Eng: pixzig.PixzigEngine = undefined;
var g_App: MyApp = undefined;

export fn mainLoop() void {
    _ = g_AppRunner.gameLoopCore(&g_App, &g_Eng);
}

pub fn main() !void {
    std.log.info("Game loop test start.", .{});
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();

    g_Eng = try pixzig.PixzigEngine.init("Glfw Game loop Test.", gpa, EngOptions{});

    g_AppRunner.begin();
    g_App = MyApp.init(123);

    _ = g_App.update(&g_Eng, 1);
    glfw.swapInterval(0);

    std.log.info("Starting main loop...\n", .{});

    if(builtin.target.os.tag == .emscripten) {
        pixzig.setMainLoop(mainLoop, null, false);
        std.log.debug("Set main loop.\n", .{});
    }
    else {
        g_AppRunner.gameLoop(&g_App, &g_Eng);
        std.log.info("Cleaning up...\n", .{});
        g_Eng.deinit();
        _ = gpa_state.deinit();
    }
}

