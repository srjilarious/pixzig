// First attempt at switching to GLFW from SDL.
// Currently just copy-paste of zig-gamedev minimal glfw w/ gui sample
const std = @import("std");

const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;

const pixzig = @import("pixzig");
const EngOptions = pixzig.PixzigEngineOptions;

const content_dir = "assets/"; //@import("build_options").content_dir;
const window_title = "zig-gamedev: minimal zgpu glfw opengl3";

pub fn main() !void {

    // Change current working directory to where the executable is located.
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.posix.chdir(path) catch {};
    }

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Glfw Eng Test.", gpa, EngOptions{});
    defer eng.deinit();

    std.debug.print("Engine initialize.\n", .{});
    _ = zgui.io.addFontFromFile(
        content_dir ++ "Roboto-Medium.ttf",
        std.math.floor(16.0 * eng.scaleFactor),
    );

    std.debug.print("font loaded.\n", .{});
    while (!eng.window.shouldClose() and eng.window.getKey(.escape) != .press) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0.1, 1.0 });

        const fb_size = eng.window.getFramebufferSize();

        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        // Set the starting window position and size to custom values
        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

        if (zgui.begin("My window", .{})) {
            if (zgui.button("Press me!", .{ .w = 200.0 })) {
                std.debug.print("Button pressed\n", .{});
            }
        }
        zgui.end();

        zgui.backend.draw();

        eng.window.swapBuffers();
    }
}
