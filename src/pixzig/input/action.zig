const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("../comp.zig");
const gamepad = @import("./gamepad.zig");
const keyboard = @import("./keyboard.zig");
const KeyModifier = keyboard.KeyModifier;
const Mouse = @import("./mouse.zig").Mouse;

pub const Source = union(enum) {
    key: glfw.Key,
    // key_with_mods: struct {
    //     key: glfw.Key,
    //     mods: KeyModifier,
    // },
    // chord: []const KeyChordPiece,
    mouse_button: glfw.MouseButton,
    // mouse_axis: MouseAxis,
    gamepad_button: glfw.Gamepad.Button,
    // gamepad_axis: struct {
    //     // id: GamepadId = .any,
    //     axis: glfw.Gamepad.Axis,
    //     deadzone: f32 = 0.18,
    //     scale: f32 = 1.0,
    //     invert: bool = false,
    // },
};

pub const AxisSource = union(enum) {
    buttons: struct {
        negative: Source,
        positive: Source,
    },
    gamepad_axis: struct {
        axis: glfw.Gamepad.Axis,
        deadzone: f32 = 0.18,
    },
};

pub fn ActionMap(comptime Action: type, comptime Axes: type) type {
    const DigitalBinding = struct {
        source: Source,
        action: Action,
    };

    const AnalogBinding = struct {
        source: AxisSource,
        axis: Axes,
    };

    const NumActions = comp.numEnumFields(Action);
    const NumAxes = comp.numEnumFields(Axes);

    const helpers = struct {
        // Gets the index of the action in our bitset.
        fn getIndexForAction(action: Action) usize {
            const enumTypeInfo = @typeInfo(Action).@"enum";
            comptime var keyIdx: usize = 0;
            inline for (enumTypeInfo.fields) |field| {
                const fieldKey = @field(Action, field.name);
                if (action == fieldKey) return keyIdx;
                keyIdx += 1;
            }

            return 0;
        }

        fn getIndexForAxis(ax: Axes) usize {
            const enumTypeInfo = @typeInfo(Axes).@"enum";
            comptime var keyIdx: usize = 0;
            inline for (enumTypeInfo.fields) |field| {
                const fieldKey = @field(Axes, field.name);
                if (ax == fieldKey) return keyIdx;
                keyIdx += 1;
            }

            return 0;
        }
    };

    // Represents the state of the actions
    const DigitalActionState = struct {
        actions: std.StaticBitSet(NumActions),

        const InnerSelf = @This();

        /// Initializes a new KeyboardState with all keys up.
        pub fn init() InnerSelf {
            const actions = std.StaticBitSet(NumActions).initEmpty();
            return .{ .actions = actions };
        }

        /// Returns true if the provided key is currently up in this state.
        pub fn up(self: *const InnerSelf, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return !self.actions.isSet(actionIdx);
        }

        /// Returns true if the provided key is currently down in this state.
        pub fn down(self: *const InnerSelf, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return self.actions.isSet(actionIdx);
        }

        /// Returns true if the provided key index is currently down in this state.
        pub fn downIdx(self: *const InnerSelf, actionIdx: usize) bool {
            const res = self.keys.isSet(actionIdx);
            return res;
        }

        /// Sets the provided key to the given value (true for down, false for
        /// up) in this state.  This is used for testing.
        pub fn set(self: *InnerSelf, action: Action, val: bool) void {
            const actionIdx = helpers.getIndexForAction(action);
            self.setIdx(actionIdx, val);
        }

        /// Sets the provided key index to the given value (true for down, false
        /// for up) in this state.  This is used for testing.
        pub fn setIdx(self: *InnerSelf, actionIdx: usize, val: bool) void {
            if (val) {
                self.actions.set(actionIdx);
            } else {
                self.actions.unset(actionIdx);
            }
        }

        /// Clears the keyboard state by setting all keys to up.
        pub fn clear(self: *InnerSelf) void {
            self.actions.setRangeValue(.{ .start = 0, .end = NumActions }, false);
        }
    };

    const AxisActionState = struct {
        axes: [NumAxes]f32,

        const InnerSelf = @This();

        /// Initializes a new AxisActionState with all Axes set to 0.
        pub fn init() InnerSelf {
            return .{ .axes = std.mem.zeroes([NumAxes]f32) };
        }

        /// Sets the provided key to the given value (true for down, false for
        /// up) in this state.  This is used for testing.
        pub fn set(self: *InnerSelf, axis: Axes, val: f32) void {
            const axisIdx = helpers.getIndexForAxis(axis);
            self.setIdx(axisIdx, val);
        }

        /// Sets the provided key index to the given value (true for down, false
        /// for up) in this state.  This is used for testing.
        pub fn setIdx(self: *InnerSelf, axisIdx: usize, val: f32) void {
            self.axes[axisIdx] = val;
        }

        /// Clears the keyboard state by setting all keys to up.
        pub fn clear(self: *InnerSelf) void {
            for (0..NumAxes) |axisIdx| {
                self.axes[axisIdx] = 0;
            }
        }
    };

    // The main typed ActionMap.
    return struct {
        alloc: std.mem.Allocator,
        digitalBindings: std.ArrayList(DigitalBinding),
        axisBindings: std.ArrayList(AnalogBinding),
        currIdx: usize,
        prevIdx: usize,
        digitalActionBuffers: [2]DigitalActionState,
        axisActionBuffers: [2]AxisActionState,

        const Self = @This();

        pub fn init(
            alloc: std.mem.Allocator,
        ) !*Self {
            const actions = try alloc.create(Self);
            actions.* = .{
                .alloc = alloc,
                .digitalBindings = .empty,
                .axisBindings = .empty,
                .prevIdx = 0,
                .currIdx = 1,
                .digitalActionBuffers = .{
                    DigitalActionState.init(),
                    DigitalActionState.init(),
                },
                .axisActionBuffers = .{
                    AxisActionState.init(),
                    AxisActionState.init(),
                },
            };
            return actions;
        }

        pub fn deinit(self: *Self) void {
            self.digitalBindings.deinit(self.alloc);
            self.axisBindings.deinit(self.alloc);
            self.alloc.destroy(self);
        }

        /// Returns a pointer to the current KeyboardState buffer, which
        /// represents the state of the keyboard in the current frame.
        pub fn currDigital(self: *const Self) *const DigitalActionState {
            return &self.digitalActionBuffers[self.currIdx];
        }

        pub fn currDigital_mut(self: *Self) *DigitalActionState {
            return &self.digitalActionBuffers[self.currIdx];
        }

        /// Returns a pointer to the previous KeyboardState buffer, which
        /// represents the state of the keyboard in the previous frame.
        pub fn prevDigital(self: *const Self) *const DigitalActionState {
            return &self.digitalActionBuffers[self.prevIdx];
        }

        pub fn currAnalog(self: *const Self) *const AxisActionState {
            return &self.axisActionBuffers[self.currIdx];
        }

        pub fn currAxis_mut(self: *Self) *AxisActionState {
            return &self.axisActionBuffers[self.currIdx];
        }

        pub fn bind(self: *Self, action: Action, source: Source) !void {
            try self.digitalBindings.append(
                self.alloc,
                .{
                    .source = source,
                    .action = action,
                },
            );
        }

        pub fn bindAxis(self: *Self, ax: Axes, source: AxisSource) !void {
            try self.axisBindings.append(
                self.alloc,
                .{
                    .source = source,
                    .axis = ax,
                },
            );
        }

        fn isSourceDown(source: Source, kb: *const keyboard.Keyboard, mouse: *const Mouse) bool {
            switch (source) {
                .key => |k| {
                    return kb.down(k);
                },
                .mouse_button => |m| {
                    return mouse.down(m);
                },
                .gamepad_button => {
                    // TODO.
                    return false;
                },
            }
        }

        pub fn update(self: *Self, kb: *const keyboard.Keyboard, mouse: *const Mouse) bool {
            const temp = self.currIdx;
            self.currIdx = self.prevIdx;
            self.prevIdx = temp;

            // Update the current keys
            var curr = self.currDigital_mut();
            curr.clear();

            for (self.digitalBindings.items) |binding| {
                const sourceDown = isSourceDown(binding.source, kb, mouse);

                // Allow multiple bindings, and if any are pressed it triggers.
                if (sourceDown) {
                    curr.set(binding.action, true);
                }
            }

            var currAxes = self.currAxis_mut();
            currAxes.clear();

            for (self.axisBindings.items) |binding| {
                var val: f32 = 0.0;
                switch (binding.source) {
                    .buttons => |b| {
                        const neg = isSourceDown(b.negative, kb, mouse);
                        const pos = isSourceDown(b.positive, kb, mouse);
                        if (neg and !pos) {
                            val = -1.0;
                        } else if (!neg and pos) {
                            val = 1.0;
                        }
                    },
                    .gamepad_axis => |ga| {
                        _ = ga;
                        // TODO
                    },
                }

                currAxes.set(binding.axis, val);
            }

            return false;
        }

        /// Returns true if the provided key is currently up in the current state.
        pub fn up(self: *const Self, action: Action) bool {
            return self.currDigital().up(action) == false;
        }

        /// Returns true if the provided key is currently down in the current state.
        pub fn down(self: *const Self, action: Action) bool {
            return self.currDigital().down(action);
        }

        pub fn axis(self: *const Self, ax: Axes) f32 {
            const axisIdx = helpers.getIndexForAxis(ax);
            return self.currAnalog().axes[axisIdx];
        }

        /// Returns true if the provided key was pressed in the current frame
        /// (i.e., it is down in the current state but was up in the previous state).
        pub fn pressed(self: *const Self, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return (self.currDigital().downIdx(actionIdx) and !self.prevDigital().downIdx(actionIdx));
        }

        /// Returns true if the provided key was released in the current frame
        /// (i.e., it is up in the current state but was down in the previous state).
        pub fn released(self: *const Self, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return (!self.currDigital().downIdx(actionIdx) and self.prevDigital().downIdx(actionIdx));
        }
    };
}
