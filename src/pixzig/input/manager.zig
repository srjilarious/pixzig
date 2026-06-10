const std = @import("std");
const glfw = @import("zglfw");
const windowing = @import("../window.zig");
const common = @import("../common.zig");
const Vec2F = common.Vec2F;
const Keyboard = @import("./keyboard.zig").Keyboard;
const Mouse = @import("./mouse.zig").Mouse;
const Gamepad = @import("./gamepad.zig").Gamepad;

/// Maximum number of gamepads that an InputManager can own.
pub const MaxGamepads: u8 = 4;

/// Runtime options for configuring which input subsystems the InputManager
/// owns and updates.  Passed to `InputManager.init()`.
pub const InputOptions = struct {
    /// Whether to update the Mouse each tick and expose logical coordinates.
    mouse: bool = true,
    /// Number of gamepads to own and update (joystick IDs 0..numGamepads-1).
    /// Clamped to MaxGamepads at init time.
    numGamepads: u8 = 0,
};

/// Owns and updates all input subsystems for a single player session.
/// Keyboard is always present.  Mouse and gamepads are activated via the
/// `opts` passed to `init()` and updated based on the runtime flags stored
/// in `mouse_enabled` and `num_gamepads`.
pub const InputManager = struct {
    mouse_enabled: bool,
    num_gamepads: u8,
    keyboard: Keyboard,
    mouse: Mouse,
    gamepads: [MaxGamepads]Gamepad,

    const Self = @This();

    pub fn init(opts: InputOptions) Self {
        const n = @min(opts.numGamepads, MaxGamepads);
        var result: Self = .{
            .mouse_enabled = opts.mouse,
            .num_gamepads = n,
            .keyboard = Keyboard.init(),
            .mouse = Mouse.init(),
            .gamepads = undefined,
        };
        for (0..MaxGamepads) |i| {
            result.gamepads[i] = Gamepad.init(@intCast(i));
        }
        return result;
    }

    /// Advances all active input subsystems by one tick.  Call after
    /// `glfw.pollEvents()` and before `app.update()`.
    ///
    /// `scale_factor` is `WindowState.scale_factor` (framebuffer/window
    /// ratio).  `viewport` is used to map the raw cursor position into
    /// logical game coordinates for `mouse.pos()`.
    pub fn update(
        self: *Self,
        window: *glfw.Window,
        scale_factor: Vec2F,
        viewport: *const windowing.Viewport,
    ) void {
        _ = self.keyboard.update(window);

        if (self.mouse_enabled) {
            self.mouse.update(window);
            const raw = self.mouse.rawPos();
            const fb = Vec2F{ .x = raw.x * scale_factor.x, .y = raw.y * scale_factor.y };
            self.mouse.curr_mut().logical_pos =
                viewport.framebufferToLogical(fb) orelse Vec2F{ .x = -1, .y = -1 };
        }

        for (0..self.num_gamepads) |i| {
            _ = self.gamepads[i].update();
        }
    }

    /// Returns a pointer to the gamepad at the given index.
    pub fn gamepad(self: *Self, idx: usize) *Gamepad {
        return &self.gamepads[idx];
    }
};
