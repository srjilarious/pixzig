const std = @import("std");
const glfw = @import("zglfw");
const windowing = @import("./window.zig");
const common = @import("./common.zig");
const Vec2F = common.Vec2F;

pub const keyboard = @import("./input/keyboard.zig");
pub const charFromKey = keyboard.charFromKey;
pub const KeyModifier = keyboard.KeyModifier;
pub const KeyboardState = keyboard.KeyboardState;
pub const Keyboard = keyboard.Keyboard;

pub const mouse = @import("./input/mouse.zig");
pub const MouseState = mouse.MouseState;
pub const Mouse = mouse.Mouse;

pub const gamepad = @import("./input/gamepad.zig");
pub const GamepadState = gamepad.GamepadState;
pub const Gamepad = gamepad.Gamepad;

pub const keychord = @import("./input/keychord.zig");
pub const KeyChord = keychord.KeyChord;
pub const KeyChordPiece = keychord.KeyChordPiece;
pub const ChordUpdateResult = keychord.ChordUpdateResult;
pub const ChordTree = keychord.ChordTree;
pub const KeyMap = keychord.KeyMap;

pub const action = @import("./input/action.zig");
pub const ActionMap = action.ActionMap;
pub const ActionState = action.ActionState;
pub const Binding = action.Binding;

/// Compile-time options controlling which input subsystems the InputManager owns.
pub const InputOptions = struct {
    /// Whether to own and update a Mouse instance.
    mouse: bool = false,
    /// Number of gamepads to own and update (mapped to joystick IDs 0..numGamepads-1).
    numGamepads: u8 = 0,
};

/// Returns an InputManager type parameterized by the given options.  The
/// manager always owns a Keyboard, and conditionally owns a Mouse and/or an
/// array of Gamepads based on the options.  Call `update` once per tick to
/// advance all owned subsystems.
pub fn InputManager(comptime opts: InputOptions) type {
    return struct {
        keyboard: Keyboard,
        mouse: if (opts.mouse) Mouse else void,
        gamepads: if (opts.numGamepads > 0) [opts.numGamepads]Gamepad else void,

        const Self = @This();

        pub fn init() Self {
            var result: Self = undefined;
            result.keyboard = Keyboard.init();
            if (opts.mouse) {
                result.mouse = Mouse.init();
            }
            if (opts.numGamepads > 0) {
                for (0..opts.numGamepads) |i| {
                    result.gamepads[i] = Gamepad.init(@intCast(i));
                }
            }
            return result;
        }

        /// Advances all owned input subsystems by one tick.  Call after
        /// glfw.pollEvents() and before app.update().
        ///
        /// `scale_factor` is WindowState.scale_factor (framebuffer/window ratio).
        /// `viewport` is the current engine Viewport used to map raw cursor
        /// positions into logical game coordinates for mouse.pos().
        pub fn update(
            self: *Self,
            window: *glfw.Window,
            scale_factor: Vec2F,
            viewport: *const windowing.Viewport,
        ) void {
            _ = self.keyboard.update(window);
            if (opts.mouse) {
                self.mouse.update(window);
                // Convert raw GLFW window coords to logical game coords.
                const raw = self.mouse.rawPos();
                const fb = Vec2F{ .x = raw.x * scale_factor.x, .y = raw.y * scale_factor.y };
                self.mouse.curr_mut().logical_pos =
                    viewport.framebufferToLogical(fb) orelse Vec2F{ .x = -1, .y = -1 };
            }
            if (opts.numGamepads > 0) {
                for (&self.gamepads) |*gp| {
                    _ = gp.update();
                }
            }
        }

        /// Returns a pointer to the gamepad at the given index.  Calling this
        /// when numGamepads is 0 is a compile error.
        pub fn gamepad(self: *Self, idx: usize) *Gamepad {
            if (comptime opts.numGamepads == 0) @compileError("No gamepads configured; set inputOpts.numGamepads > 0");
            return &self.gamepads[idx];
        }
    };
}
