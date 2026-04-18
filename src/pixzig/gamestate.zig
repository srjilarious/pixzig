const std = @import("std");
const comp = @import("comp.zig");

/// A generic game state manager that can be typed across an enum associated
/// with a list of state types.  It provides methods for setting the current
/// state, updating, and rendering.  When the state is changed, it checks for
/// and calls `deactivate` on the old state and `activate` on the new state
/// if those methods exist.  The update and render methods also check for and
/// call the corresponding method on the current state.
pub fn GameStateMgr(
    comptime Engine: type,
    comptime StateKeysType: type,
    comptime States: []const type,
) type {

    // Contrain the state enum keys to be the same size as the provided states.
    const numStates = comp.numEnumFields(StateKeysType);
    if (numStates != States.len) {
        @compileError("Number of states in keys enum and provided list must match!");
    }

    // Generate the GameState Manager
    return struct {
        currStateIdx: usize,
        states: []*anyopaque,

        const Self = @This();

        pub fn init(states: []*anyopaque) Self {

            // const enumTypeInfo = @typeInfo(StateKeysType);

            return .{ .currStateIdx = 0, .states = states };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Sets the current state to the provided state key, calling
        /// deactivate on the old state and activate on the new state
        /// if those methods exist.
        pub fn setCurrState(self: *Self, state: StateKeysType) void {
            const oldState = self.currStateIdx;
            self.currStateIdx = @intFromEnum(state);

            std.log.debug("oldState = {}, currState = {}", .{ oldState, self.currStateIdx });

            // Check to deactivate the old state.
            inline for (0..States.len) |idx| {
                if (oldState == idx) {
                    const stateType = States[idx];
                    std.log.debug("Deactivating state: {}", .{idx});
                    if (@hasDecl(stateType, "deactivate")) {
                        const statePtr: *stateType = @ptrCast(@alignCast(self.states[oldState]));
                        statePtr.deactivate();
                    }
                }
            }

            // Check to activate the new state.
            inline for (0..States.len) |idx| {
                if (self.currStateIdx == idx) {
                    const stateType = States[idx];
                    std.log.debug("Activating state: {}", .{idx});
                    if (@hasDecl(stateType, "activate")) {
                        const statePtr: *stateType = @ptrCast(@alignCast(self.states[self.currStateIdx]));
                        statePtr.activate();
                    }
                }
            }
        }

        /// Calls the update method on the current state if it exists, passing
        /// along the engine and delta time.  Returns true if the update was
        /// handled by the current state, false otherwise.
        pub fn update(self: *Self, eng: *Engine, deltaMs: f64) bool {
            inline for (0..States.len) |idx| {
                if (self.currStateIdx == idx) {
                    const stateType = States[idx];
                    const statePtr: *stateType = @ptrCast(@alignCast(self.states[idx]));
                    return statePtr.update(eng, deltaMs);
                }
            }
            return false;
        }

        /// Calls the render method on the current state if it exists.
        pub fn render(self: *Self, eng: *Engine) void {
            inline for (0..States.len) |idx| {
                if (self.currStateIdx == idx) {
                    const stateType = States[idx];
                    const statePtr: *stateType = @ptrCast(@alignCast(self.states[idx]));
                    return statePtr.render(eng);
                }
            }
        }
    };
}
