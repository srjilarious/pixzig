const std = @import("std");
const builtin = @import("builtin");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const Delay = pixzig.utils.Delay;

const math = @import("zmath");
const FpsCounter = pixzig.utils.FpsCounter;

pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

// Colors cycled by gamepad buttons.
const Colors = struct {
    r: f32,
    g: f32,
    b: f32,
};

const ButtonColors = [_]struct { btn: glfw.Gamepad.Button, color: Colors }{
    .{ .btn = .a,             .color = .{ .r = 0.8, .g = 0.1, .b = 0.1 } }, // A  → red
    .{ .btn = .b,             .color = .{ .r = 0.1, .g = 0.8, .b = 0.1 } }, // B  → green
    .{ .btn = .x,             .color = .{ .r = 0.1, .g = 0.1, .b = 0.8 } }, // X  → blue
    .{ .btn = .y,             .color = .{ .r = 0.8, .g = 0.8, .b = 0.1 } }, // Y  → yellow
    .{ .btn = .left_bumper,   .color = .{ .r = 0.1, .g = 0.8, .b = 0.8 } }, // LB → cyan
    .{ .btn = .right_bumper,  .color = .{ .r = 0.8, .g = 0.1, .b = 0.8 } }, // RB → magenta
    .{ .btn = .start,         .color = .{ .r = 0.9, .g = 0.9, .b = 0.9 } }, // Start → white
    .{ .btn = .back,          .color = .{ .r = 0.2, .g = 0.2, .b = 0.2 } }, // Back  → dark gray
};

pub const App = struct {
    fps: FpsCounter,
    gamepad: pixzig.input.Gamepad,
    color: Colors,
    printDelay: Delay,

    pub fn init() App {
        return .{
            .fps = FpsCounter.init(),
            .gamepad = pixzig.input.Gamepad.init(0),
            .color = .{ .r = 0.0, .g = 0.0, .b = 0.5 },
            .printDelay = .{ .max = 60 },
        };
    }

    pub fn deinit(self: *App) void {
        _ = self;
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        self.gamepad.update();

        if (!self.gamepad.isConnected()) {
            if (self.printDelay.update(1)) {
                std.debug.print("No gamepad connected on joystick 0.\n", .{});
            }
        } else {
            // Apply the color for whichever button is held.
            for (ButtonColors) |entry| {
                if (self.gamepad.down(entry.btn)) {
                    self.color = entry.color;
                }
            }

            // Print axis values periodically.
            if (self.printDelay.update(1)) {
                std.debug.print(
                    "LStick ({d:.2}, {d:.2})  RStick ({d:.2}, {d:.2})  Triggers L={d:.2} R={d:.2}\n",
                    .{
                        self.gamepad.axis(.left_x),
                        self.gamepad.axis(.left_y),
                        self.gamepad.axis(.right_x),
                        self.gamepad.axis(.right_y),
                        self.gamepad.axis(.left_trigger),
                        self.gamepad.axis(.right_trigger),
                    },
                );
            }
        }

        if (eng.keyboard.pressed(.escape)) return false;
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(self.color.r, self.color.g, self.color.b, 1.0);
        self.fps.renderTick();
    }
};

pub fn main() !void {
    std.log.info("Pixzig Gamepad Test", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Pixzig: Gamepad Test", alloc, .{});
    var app = App.init();

    glfw.swapInterval(0);
    appRunner.run(&app);
}
