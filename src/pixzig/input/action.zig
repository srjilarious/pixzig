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

pub fn ActionMap(comptime Action: type) type {
    const DigitalBinding = struct {
        source: Source,
        action: Action,
    };

    const NumActions = comp.numEnumFields(Action);

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

    // The main typed ActionMap.
    return struct {
        alloc: std.mem.Allocator,
        digitalBindings: std.ArrayList(DigitalBinding),
        currIdx: usize,
        prevIdx: usize,
        digitalActionBuffers: [2]DigitalActionState,

        const Self = @This();

        pub fn init(
            alloc: std.mem.Allocator,
        ) !*Self {
            const actions = try alloc.create(Self);
            actions.* = .{
                .alloc = alloc,
                .digitalBindings = .empty,
                .prevIdx = 0,
                .currIdx = 1,
                .digitalActionBuffers = .{
                    DigitalActionState.init(),
                    DigitalActionState.init(),
                },
            };
            return actions;
        }

        pub fn deinit(self: *Self) void {
            self.digitalBindings.deinit(self.alloc);
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

        pub fn bind(self: *Self, action: Action, source: Source) !void {
            try self.digitalBindings.append(
                self.alloc,
                .{
                    .source = source,
                    .action = action,
                },
            );
        }

        pub fn update(self: *Self, kb: *const keyboard.Keyboard, mouse: *const Mouse) bool {
            const temp = self.currIdx;
            self.currIdx = self.prevIdx;
            self.prevIdx = temp;

            // Update the current keys
            var curr = self.currDigital_mut();
            curr.clear();

            for (self.digitalBindings.items) |binding| {
                var sourceDown: bool = false;
                switch (binding.source) {
                    .key => |k| {
                        sourceDown = kb.down(k);
                    },
                    .mouse_button => |m| {
                        sourceDown = mouse.down(m);
                    },
                    .gamepad_button => {
                        // TODO.
                    },
                }

                // Allow multiple bindings, and if any are pressed it triggers.
                if (sourceDown) {
                    curr.set(binding.action, true);
                }
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
