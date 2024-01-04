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

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

pub const MyApp = struct {
    testVal: i32,

    pub fn init(val: i32) MyApp {
        return .{ .testVal = val };
    }

    pub fn update(self: *MyApp, eng: *pixzig.PixzigEngine, delta: f64) bool {
        _ = delta;
        eng.keyboard.update();

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
        return false;
    }

    pub fn render(self: *MyApp, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        _ = self;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.0, 1.0 });
    }
};

pub fn main() !void {

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Glfw Eng Test.", gpa, EngOptions{});
    defer eng.deinit();

    const AppRunner = pixzig.PixzigApp(MyApp);
    var app = MyApp.init(123);

    std.debug.print("Starting main loop...\n", .{});
    AppRunner.gameLoop(&app, &eng);

    std.debug.print("Cleaning up...\n", .{});
}

