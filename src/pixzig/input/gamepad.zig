const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("../comp.zig");
const common = @import("../common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

const NumGamepadButtons = glfw.Gamepad.Button.count;
const NumGamepadAxes = glfw.Gamepad.Axis.count;

pub const GamepadState = struct {
    buttons: std.StaticBitSet(NumGamepadButtons),
    axes: [NumGamepadAxes]f32,

    pub fn init() GamepadState {
        return .{
            .buttons = std.StaticBitSet(NumGamepadButtons).initEmpty(),
            .axes = .{0.0} ** NumGamepadAxes,
        };
    }

    pub fn buttonDown(self: *const GamepadState, btn: glfw.Gamepad.Button) bool {
        return self.buttons.isSet(@intFromEnum(btn));
    }

    pub fn setButton(self: *GamepadState, btn: glfw.Gamepad.Button, val: bool) void {
        if (val) {
            self.buttons.set(@intFromEnum(btn));
        } else {
            self.buttons.unset(@intFromEnum(btn));
        }
    }

    pub fn getAxis(self: *const GamepadState, ax: glfw.Gamepad.Axis) f32 {
        return self.axes[@intFromEnum(ax)];
    }

    pub fn clear(self: *GamepadState) void {
        self.buttons.setRangeValue(.{ .start = 0, .end = NumGamepadButtons }, false);
        self.axes = .{0.0} ** NumGamepadAxes;
    }
};

pub const Gamepad = struct {
    currIdx: usize,
    prevIdx: usize,
    stateBuffers: [2]GamepadState,
    connected: bool,
    joystickId: c_int,

    pub fn init(joystickId: c_int) Gamepad {
        return .{
            .currIdx = 0,
            .prevIdx = 1,
            .stateBuffers = .{ GamepadState.init(), GamepadState.init() },
            .connected = false,
            .joystickId = joystickId,
        };
    }

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

    pub fn isConnected(self: *const Gamepad) bool {
        return self.connected;
    }

    pub fn down(self: *Gamepad, btn: glfw.Gamepad.Button) bool {
        return self.currState().buttonDown(btn);
    }

    pub fn up(self: *Gamepad, btn: glfw.Gamepad.Button) bool {
        return !self.currState().buttonDown(btn);
    }

    pub fn pressed(self: *Gamepad, btn: glfw.Gamepad.Button) bool {
        return self.currState().buttonDown(btn) and !self.prevState().buttonDown(btn);
    }

    pub fn released(self: *Gamepad, btn: glfw.Gamepad.Button) bool {
        return !self.currState().buttonDown(btn) and self.prevState().buttonDown(btn);
    }

    pub fn axis(self: *Gamepad, ax: glfw.Gamepad.Axis) f32 {
        return self.currState().getAxis(ax);
    }
};
