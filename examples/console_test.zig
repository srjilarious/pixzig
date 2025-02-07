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

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const scripting = @import("pixzig").scripting;
const console = @import("pixzig").console;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, EngOptions{ .withGui = true });

pub const App = struct {
    fps: FpsCounter,
    script: *scripting.ScriptEngine,
    cons: *console.Console,
    delay: Delay = .{ .max = 120 },

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.PixEng) !App {

        _ = zgui.io.addFontFromFile("assets/Roboto-Medium.ttf",
            std.math.floor(16.0 * eng.scaleFactor),
        );

        const script = try alloc.create(scripting.ScriptEngine);
        script.* = try scripting.ScriptEngine.init(alloc);
        return .{
            .script = script,
            .cons = try console.Console.init(alloc, script, .{}),
            .fps = FpsCounter.init() 
        };
    }

    pub fn update(self: *App, eng: *AppRunner.PixEng, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.log.debug("FPS: {}\n", .{self.fps.fps()});
        }

        // std.log.debug("update: b\n",.{});
        eng.keyboard.update();

        if(eng.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.PixEng) void {
        gl.clearColor(0, 0, 1, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);

        const fb_size = eng.window.getFramebufferSize();
        // zgui.backend
        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        // Set the starting window position and size to custom values
        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

        if (zgui.begin("My window", .{})) {
            if (zgui.button("Press me!", .{ .w = 200.0 })) {
                std.log.debug("Button pressed\n", .{});
            }
        }
        zgui.end();

        self.cons.draw();

        zgui.backend.draw();

        eng.window.swapBuffers();

        self.fps.renderTick();
    }
};


var g_AppRunner: *AppRunner = undefined;
var g_App: App = undefined;

export fn mainLoop() void {
    _ = g_AppRunner.gameLoopCore(&g_App);
}

pub fn main() !void {
    std.log.info("Pixzig Console Test Example", .{});

    const alloc = std.heap.c_allocator;
    g_AppRunner = try AppRunner.init("Pixzig: Console Test Example.", alloc, .{});

    std.log.info("Initializing app.\n", .{});
    g_App = try App.init(alloc, &g_AppRunner.engine);

    glfw.swapInterval(0);

    std.log.info("Starting main loop...\n", .{});
    if (builtin.target.os.tag == .emscripten) {
        pixzig.web.setMainLoop(mainLoop, null, false);
    } else {
        g_AppRunner.gameLoop(&g_App);
        g_AppRunner.deinit();
    }
}



// const std = @import("std");

// const zgui = @import("zgui");
// const glfw = @import("zglfw");
// const gl = @import("zopengl").bindings;

// const pixzig = @import("pixzig");
// const EngOptions = pixzig.PixzigEngineOptions;

// pub fn main() !void {

//     // Change current working directory to where the executable is located.
//     // {
//     //     var buffer: [1024]u8 = undefined;
//     //     const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
//     //     std.posix.chdir(path) catch {};
//     // }

//     // var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
//     // defer _ = gpa_state.deinit();
//     // const gpa = gpa_state.allocator();

//     const gpa = std.heap.c_allocator;
//     var eng = try pixzig.PixzigEngine.init("Console GUI test", gpa, EngOptions{ .withGui = true });
//     defer eng.deinit();

//     std.log.info("Console a.", .{});
//     // Initialize the Lua vm
//     var script = try scripting.ScriptEngine.init(gpa);
//     defer script.deinit();

//     std.log.info("Console b.", .{});
//     const cons = try console.Console.init(gpa, &script, .{});
//     defer cons.deinit();

//     std.debug.print("Engine initialize.\n", .{});
//     _ = zgui.io.addFontFromFile(
//         content_dir ++ "Roboto-Medium.ttf",
//         std.math.floor(16.0 * eng.scaleFactor),
//     );

//     std.debug.print("font loaded.\n", .{});
//     while (!eng.window.shouldClose() and eng.window.getKey(.escape) != .press) {
//         std.log.info("Console c.", .{});
//         glfw.pollEvents();

//         // gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0.1, 1.0 });
//         gl.clearColor(0, 0, 0.2, 1);
//         gl.clear(gl.COLOR_BUFFER_BIT);

//         const fb_size = eng.window.getFramebufferSize();
//         // zgui.backend
//         std.log.info("Start new frame", .{});
//         zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

//         // Set the starting window position and size to custom values
//         std.log.info("Set position", .{});
//         zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
//         zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

//         std.log.info("begin window", .{});
//         if (zgui.begin("My window", .{})) {
//             if (zgui.button("Press me!", .{ .w = 200.0 })) {
//                 std.debug.print("Button pressed\n", .{});
//             }
//         }
//         std.log.info("end window", .{});
//         zgui.end();

//         cons.draw();
//         std.log.info("console draw.", .{});

//         zgui.backend.draw();
//         std.log.info("backend drew.", .{});

//         eng.window.swapBuffers();
//         std.log.info("swap buffers.", .{});
//     }
// }
