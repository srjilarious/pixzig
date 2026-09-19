const std = @import("std");
const pixzig = @import("pixzig");
const Delay = pixzig.utils.Delay;

const math = @import("zmath");
const FpsCounter = pixzig.utils.FpsCounter;

pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{ .inputOpts = .{ .numGamepads = 1 } });

// Colors cycled by gamepad buttons.
const Colors = struct {
    r: u8,
    g: u8,
    b: u8,
};

const ButtonColors = [_]struct { btn: pixzig.GamepadButton, color: Colors }{
    .{ .btn = .a, .color = .{ .r = 204, .g = 26, .b = 26 } }, // A  -> red
    .{ .btn = .b, .color = .{ .r = 26, .g = 204, .b = 26 } }, // B  -> green
    .{ .btn = .x, .color = .{ .r = 26, .g = 26, .b = 204 } }, // X  -> blue
    .{ .btn = .y, .color = .{ .r = 204, .g = 204, .b = 26 } }, // Y  -> yellow
    .{ .btn = .left_bumper, .color = .{ .r = 26, .g = 204, .b = 204 } }, // LB -> cyan
    .{ .btn = .right_bumper, .color = .{ .r = 204, .g = 26, .b = 204 } }, // RB -> magenta
    .{ .btn = .start, .color = .{ .r = 230, .g = 230, .b = 230 } }, // Start -> white
    .{ .btn = .back, .color = .{ .r = 51, .g = 51, .b = 51 } }, // Back  -> dark gray
};

pub const App = struct {
    fps: FpsCounter,
    color: Colors,
    printDelay: Delay,

    pub fn init() App {
        return .{
            .fps = FpsCounter.init(),
            .color = .{ .r = 0, .g = 0, .b = 128 },
            .printDelay = .{ .max = 60 },
        };
    }

    pub fn deinit(self: *App) void {
        _ = self;
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        const gp = eng.inputs.gamepad(0);

        if (!gp.isConnected()) {
            if (self.printDelay.update(1)) {
                std.log.warn("No gamepad connected on joystick 0.", .{});
            }
        } else {
            // Apply the color for whichever button is held.
            for (ButtonColors) |entry| {
                if (gp.down(entry.btn)) {
                    self.color = entry.color;
                }
            }

            // Print axis values periodically.
            if (self.printDelay.update(1)) {
                std.log.debug(
                    "LStick ({d:.2}, {d:.2})  RStick ({d:.2}, {d:.2})  Triggers L={d:.2} R={d:.2}",
                    .{
                        gp.axis(.left_x),
                        gp.axis(.left_y),
                        gp.axis(.right_x),
                        gp.axis(.right_y),
                        gp.axis(.left_trigger),
                        gp.axis(.right_trigger),
                    },
                );
            }
        }

        if (eng.inputs.keyboard.pressed(.escape)) return false;
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(self.color.r, self.color.g, self.color.b, 255);
        self.fps.renderTick();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Gamepad Example", .{});

    const appRunner = try AppRunner.init("Pixzig: Gamepad Example", init.gpa, .{});
    var app = App.init();

    appRunner.run(&app);
}
