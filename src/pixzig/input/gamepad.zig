const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("../comp.zig");
const common = @import("../common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

const NumGamepadButtons = glfw.Gamepad.Button.count;
const NumGamepadAxes = glfw.Gamepad.Axis.count;

/// Stores a snapshot of the gamepad state at a given time.
pub const GamepadState = struct {
    buttons: std.StaticBitSet(NumGamepadButtons),
    axes: [NumGamepadAxes]f32,

    /// Initializes a new GamepadState with all buttons unpressed and axes
    /// centered.
    pub fn init() GamepadState {
        return .{
            .buttons = std.StaticBitSet(NumGamepadButtons).initEmpty(),
            .axes = .{0.0} ** NumGamepadAxes,
        };
    }

    /// Returns true if the provided button is currently down in this state.
    pub fn buttonDown(self: *const GamepadState, btn: glfw.Gamepad.Button) bool {
        return self.buttons.isSet(@intFromEnum(btn));
    }

    /// Sets the provided button to the given value (true for down, false for
    /// up) in this state.
    pub fn setButton(self: *GamepadState, btn: glfw.Gamepad.Button, val: bool) void {
        if (val) {
            self.buttons.set(@intFromEnum(btn));
        } else {
            self.buttons.unset(@intFromEnum(btn));
        }
    }

    /// Returns the value of the provided axis in this state.
    pub fn getAxis(self: *const GamepadState, ax: glfw.Gamepad.Axis) f32 {
        return self.axes[@intFromEnum(ax)];
    }

    /// Clears the gamepad state by setting all buttons to unpressed and all
    /// axes to centered (0.0).
    pub fn clear(self: *GamepadState) void {
        self.buttons.setRangeValue(.{ .start = 0, .end = NumGamepadButtons }, false);
        self.axes = .{0.0} ** NumGamepadAxes;
    }
};

/// Manages the state of a gamepad across frames, allowing for querying of button
/// presses, releases, and holds. It maintains two buffers of GamepadState to
/// track the current and previous state of the gamepad, and provides methods to
/// query button/axis values.
pub const Gamepad = struct {
    currIdx: usize,
    prevIdx: usize,
    stateBuffers: [2]GamepadState,
    connected: bool,
    joystickId: c_int,

    /// Initializes a new Gamepad instance for the given joystick ID.
    pub fn init(joystickId: c_int) Gamepad {
        return .{
            .currIdx = 0,
            .prevIdx = 1,
            .stateBuffers = .{ GamepadState.init(), GamepadState.init() },
            .connected = false,
            .joystickId = joystickId,
        };
    }

    /// Updates the gamepad state by polling the current state of the
    /// joystick. It swaps the current and previous state buffers, checks
    /// if the joystick is present and a gamepad, and updates the current
    /// state buffer with the latest button and axis values. If the joystick
    /// is not present or not a gamepad, it marks the gamepad as disconnected
    /// and clears the current state.
    pub fn update(self: *Gamepad) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        const joy: glfw.Joystick = @enumFromInt(self.joystickId);
        if (!joy.isPresent() or !joy.isGamepad()) {
            self.connected = false;
            self.currState().clear();
            return;
        }
        self.connected = true;

        const gp = joy.asGamepad().?;
        const state = gp.getState() catch {
            self.connected = false;
            self.currState().clear();
            return;
        };

        var curr = self.currState();
        for (state.buttons, 0..) |btn_action, i| {
            if (btn_action == .press) {
                curr.buttons.set(i);
            } else {
                curr.buttons.unset(i);
            }
        }
        curr.axes = state.axes;
    }

    fn currState(self: *Gamepad) *GamepadState {
        return &self.stateBuffers[self.currIdx];
    }

    fn prevState(self: *Gamepad) *GamepadState {
        return &self.stateBuffers[self.prevIdx];
    }

    /// Returns true if the gamepad is currently connected, false otherwise.
    pub fn isConnected(self: *const Gamepad) bool {
        return self.connected;
    }

    /// Returns true if the specified button is currently down, false otherwise.
    pub fn down(self: *Gamepad, btn: glfw.Gamepad.Button) bool {
        return self.currState().buttonDown(btn);
    }

    /// Returns true if the specified button is currently up, false otherwise.
    pub fn up(self: *Gamepad, btn: glfw.Gamepad.Button) bool {
        return !self.currState().buttonDown(btn);
    }

    /// Returns true if the specified button was just pressed this frame (down
    ///  now, up last frame), false otherwise.
    pub fn pressed(self: *Gamepad, btn: glfw.Gamepad.Button) bool {
        return self.currState().buttonDown(btn) and !self.prevState().buttonDown(btn);
    }

    /// Returns true if the specified button was just released this frame (up now,
    /// down last frame), false otherwise.
    pub fn released(self: *Gamepad, btn: glfw.Gamepad.Button) bool {
        return !self.currState().buttonDown(btn) and self.prevState().buttonDown(btn);
    }

    /// Returns the value of the specified axis, which is a float typically in the
    /// range [-1.0, 1.0], where 0.0 is the centered position. If the gamepad
    /// is not connected, it returns 0.0.
    pub fn axis(self: *Gamepad, ax: glfw.Gamepad.Axis) f32 {
        return self.currState().getAxis(ax);
    }
};
