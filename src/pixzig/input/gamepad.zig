const std = @import("std");
const sdl = @import("sdl3");
const keys = @import("./keys.zig");

pub const GamepadButton = keys.GamepadButton;
pub const GamepadAxis = keys.GamepadAxis;
pub const NumGamepadButtons = keys.NumGamepadButtons;
pub const NumGamepadAxes = keys.NumGamepadAxes;

/// Brings up SDL's gamepad subsystem. `InputManager.init` calls this only
/// when the app asked for at least one gamepad, so a keyboard-only game
/// pays nothing for it.
pub fn initSubsystem() void {
    if (!sdl.SDL_InitSubSystem(sdl.SDL_INIT_GAMEPAD)) {
        std.log.warn("SDL_InitSubSystem(GAMEPAD) failed: {s}", .{sdl.SDL_GetError()});
    }
}

/// Stores a snapshot of the gamepad state at a given time.
pub const GamepadState = struct {
    buttons: std.StaticBitSet(NumGamepadButtons),
    axes: [NumGamepadAxes]f32,

    /// Initializes a new GamepadState with all buttons unpressed and axes
    /// centered.
    pub fn init() GamepadState {
        return .{
            .buttons = std.StaticBitSet(NumGamepadButtons).empty,
            .axes = @splat(0.0),
        };
    }

    /// Returns true if the provided button is currently down in this state.
    pub fn buttonDown(self: *const GamepadState, btn: GamepadButton) bool {
        return self.buttons.isSet(@intFromEnum(btn));
    }

    /// Sets the provided button to the given value (true for down, false for
    /// up) in this state.
    pub fn setButton(self: *GamepadState, btn: GamepadButton, val: bool) void {
        if (val) {
            self.buttons.set(@intFromEnum(btn));
        } else {
            self.buttons.unset(@intFromEnum(btn));
        }
    }

    /// Returns the value of the provided axis in this state.
    pub fn getAxis(self: *const GamepadState, ax: GamepadAxis) f32 {
        return self.axes[@intFromEnum(ax)];
    }

    /// Clears the gamepad state by setting all buttons to unpressed and all
    /// axes to centered (0.0).
    pub fn clear(self: *GamepadState) void {
        self.buttons.setRangeValue(.{ .start = 0, .end = NumGamepadButtons }, false);
        self.axes = @splat(0.0);
    }
};

/// Manages the state of a gamepad across ticks, allowing for querying of
/// button presses, releases, and holds. It maintains two buffers of
/// GamepadState to track the current and previous state of the gamepad, and
/// provides methods to query button/axis values.
///
/// Gamepads stay polled rather than event-driven: SDL keeps each opened
/// gamepad's state current as part of the event pump, and reading it once
/// per tick keeps the double-buffered edge detection consistent with the
/// rest of input.
pub const Gamepad = struct {
    currIdx: usize,
    prevIdx: usize,
    stateBuffers: [2]GamepadState,
    connected: bool,
    /// Which connected gamepad this instance tracks: index 0 is the first
    /// one SDL lists.
    slot: usize,
    handle: ?*sdl.SDL_Gamepad,

    /// Initializes a new Gamepad instance for the given controller slot.
    pub fn init(slot: usize) Gamepad {
        return .{
            .currIdx = 0,
            .prevIdx = 1,
            .stateBuffers = .{ GamepadState.init(), GamepadState.init() },
            .connected = false,
            .slot = slot,
            .handle = null,
        };
    }

    /// Releases the SDL handle, if this slot ever had one.
    pub fn deinit(self: *Gamepad) void {
        if (self.handle) |gp| {
            sdl.SDL_CloseGamepad(gp);
            self.handle = null;
        }
    }

    /// Opens the gamepad sitting in this slot, if there is one. SDL's list
    /// is re-queried each time because pads come and go while the game
    /// runs; the handle is cached so this only happens while disconnected.
    fn acquire(self: *Gamepad) void {
        var count: c_int = 0;
        const ids = sdl.SDL_GetGamepads(&count) orelse return;
        defer sdl.SDL_free(ids);

        if (self.slot >= @as(usize, @intCast(@max(count, 0)))) return;
        self.handle = sdl.SDL_OpenGamepad(ids[self.slot]);
        if (self.handle == null) {
            std.log.warn("SDL_OpenGamepad failed for slot {d}: {s}", .{ self.slot, sdl.SDL_GetError() });
        }
    }

    /// Updates the gamepad state by swapping the state buffers and reading
    /// the current button and axis values. If no pad occupies this slot, it
    /// marks the gamepad as disconnected and clears the current state.
    pub fn update(self: *Gamepad) bool {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        if (self.handle) |gp| {
            if (!sdl.SDL_GamepadConnected(gp)) {
                sdl.SDL_CloseGamepad(gp);
                self.handle = null;
            }
        }
        if (self.handle == null) self.acquire();

        const gp = self.handle orelse {
            self.connected = false;
            self.currState_mut().clear();
            return false;
        };
        self.connected = true;

        var curr = self.currState_mut();
        var anyPressed: bool = false;
        inline for (@typeInfo(GamepadButton).@"enum".field_values) |field_value| {
            const btn: GamepadButton = @enumFromInt(field_value);
            const isDown = sdl.SDL_GetGamepadButton(gp, keys.toSdlGamepadButton(btn));
            curr.setButton(btn, isDown);
            anyPressed = anyPressed or isDown;
        }
        inline for (@typeInfo(GamepadAxis).@"enum".field_values) |field_value| {
            const ax: GamepadAxis = @enumFromInt(field_value);
            const raw = sdl.SDL_GetGamepadAxis(gp, keys.toSdlGamepadAxis(ax));
            curr.axes[field_value] = keys.axisValue(ax, raw);
        }

        return anyPressed;
    }

    fn currState(self: *const Gamepad) *const GamepadState {
        return &self.stateBuffers[self.currIdx];
    }

    fn currState_mut(self: *Gamepad) *GamepadState {
        return &self.stateBuffers[self.currIdx];
    }

    fn prevState(self: *const Gamepad) *const GamepadState {
        return &self.stateBuffers[self.prevIdx];
    }

    /// Returns true if the gamepad is currently connected, false otherwise.
    pub fn isConnected(self: *const Gamepad) bool {
        return self.connected;
    }

    /// Returns true if the specified button is currently down, false otherwise.
    pub fn down(self: *const Gamepad, btn: GamepadButton) bool {
        return self.currState().buttonDown(btn);
    }

    /// Returns true if the specified button is currently up, false otherwise.
    pub fn up(self: *const Gamepad, btn: GamepadButton) bool {
        return !self.currState().buttonDown(btn);
    }

    /// Returns true if the specified button was just pressed this tick (down
    ///  now, up last tick), false otherwise.
    pub fn pressed(self: *const Gamepad, btn: GamepadButton) bool {
        return self.currState().buttonDown(btn) and !self.prevState().buttonDown(btn);
    }

    /// Returns true if the specified button was just released this tick (up now,
    /// down last tick), false otherwise.
    pub fn released(self: *const Gamepad, btn: GamepadButton) bool {
        return !self.currState().buttonDown(btn) and self.prevState().buttonDown(btn);
    }

    /// Returns the value of the specified axis, which is a float in the
    /// range [-1.0, 1.0], where 0.0 is the centered position. If the gamepad
    /// is not connected, it returns 0.0.
    pub fn axis(self: *const Gamepad, ax: GamepadAxis) f32 {
        return self.currState().getAxis(ax);
    }
};
