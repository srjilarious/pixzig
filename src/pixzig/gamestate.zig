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

    // Constrain the state enum keys to be the same size as the provided states,
    // with values 0..N-1 so each key indexes its state directly.
    const numStates = comp.numEnumFields(StateKeysType);
    if (numStates != States.len) {
        @compileError("Number of states in keys enum and provided list must match!");
    }
    for (@typeInfo(StateKeysType).@"enum".field_values, 0..) |value, idx| {
        if (value != idx) {
            @compileError("State keys enum values must be 0..N-1 in declaration order.");
        }
    }

    // Generate the GameState Manager
    return struct {
        currState: StateKeysType,
        states: StatePtrs,

        const Self = @This();

        /// A tuple of pointers to each state, in `States` order, e.g.
        /// `.{ &titleState, &playState }`.
        pub const StatePtrs = blk: {
            var ptrTypes: [States.len]type = undefined;
            for (States, 0..) |State, idx| ptrTypes[idx] = *State;
            break :blk @Tuple(&ptrTypes);
        };

        /// `states` holds one pointer per entry in `States`, in the same
        /// order; a missing, extra, or wrongly typed pointer is a compile
        /// error. The first state starts current.
        pub fn init(states: StatePtrs) Self {
            return .{ .currState = @enumFromInt(0), .states = states };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Sets the current state to the provided state key, calling
        /// deactivate on the old state and activate on the new state
        /// if those methods exist.
        pub fn setCurrState(self: *Self, state: StateKeysType) void {
            std.log.debug("oldState = {t}, currState = {t}", .{ self.currState, state });

            switch (self.currState) {
                inline else => |old| {
                    const statePtr = self.states[@intFromEnum(old)];
                    if (@hasDecl(@TypeOf(statePtr.*), "deactivate")) statePtr.deactivate();
                },
            }

            self.currState = state;
            switch (state) {
                inline else => |new| {
                    const statePtr = self.states[@intFromEnum(new)];
                    if (@hasDecl(@TypeOf(statePtr.*), "activate")) statePtr.activate();
                },
            }
        }

        /// Calls the update method on the current state, passing along the
        /// engine and delta time, and returns its result.
        pub fn update(self: *Self, eng: *Engine, deltaMs: f64) bool {
            switch (self.currState) {
                inline else => |curr| return self.states[@intFromEnum(curr)].update(eng, deltaMs),
            }
        }

        /// Calls the render method on the current state.
        pub fn render(self: *Self, eng: *Engine) void {
            switch (self.currState) {
                inline else => |curr| self.states[@intFromEnum(curr)].render(eng),
            }
        }
    };
}
