const std = @import("std");
const comp = @import("comp.zig");

/// How a pushed state treats the states under it.
pub const PushOptions = struct {
    /// Draw the states below first, so this one renders over them (a pause
    /// menu over the paused game). False for a state that covers the
    /// whole screen.
    renderBelow: bool = true,
    /// Keep updating the states below (a HUD popup over a live game).
    /// False freezes them while this state is on top.
    updateBelow: bool = false,
};

/// A generic game state manager typed across an enum associated with a
/// list of state types. States form a stack: `setCurrState` replaces the
/// whole stack with one state, `push` lays another over the top (a pause
/// menu, an inventory) and `pop` removes it again. `update` and `render`
/// reach the top state and, depending on each push's `PushOptions`, the
/// ones beneath it.
///
/// Optional lifecycle hooks on a state, all taking only `self`:
///   - `activate` / `deactivate`: the state entered or left the stack.
///   - `pause` / `resume`: a push covered it, or a pop uncovered it. It
///     stays on the stack in between.
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

    for (States) |State| {
        comp.checkUpdateReturn(State, @typeName(State) ++ ".update");
        comp.checkRenderSignature(State, @typeName(State) ++ ".render");
    }

    // Generate the GameState Manager
    return struct {
        /// The stack, bottom first; `stack[len - 1]` is the top. Each state
        /// appears at most once, so `States.len` slots always suffice.
        stack: [States.len]Entry,
        len: usize,
        states: StatePtrs,

        const Self = @This();

        /// One stack slot: the state and the options it was pushed with.
        /// The bottom entry's options are unused.
        const Entry = struct {
            key: StateKeysType,
            opts: PushOptions,
        };

        /// A tuple of pointers to each state, in `States` order, e.g.
        /// `.{ &titleState, &playState }`.
        pub const StatePtrs = blk: {
            var ptrTypes: [States.len]type = undefined;
            for (States, 0..) |State, idx| ptrTypes[idx] = *State;
            break :blk @Tuple(&ptrTypes);
        };

        /// `states` holds one pointer per entry in `States`, in the same
        /// order; a missing, extra, or wrongly typed pointer is a compile
        /// error. The stack starts holding just the first state (its
        /// `activate` is not called).
        pub fn init(states: StatePtrs) Self {
            var self: Self = .{ .stack = undefined, .len = 1, .states = states };
            self.stack[0] = .{ .key = @fromBackingInt(@intCast(0)), .opts = .{} };
            return self;
        }

        /// Deactivates every state still on the stack, top first.
        pub fn deinit(self: *Self) void {
            while (self.len > 0) {
                self.len -= 1;
                self.callHook(self.stack[self.len].key, "deactivate");
            }
        }

        /// The state on top of the stack: the one taking input.
        pub fn current(self: *const Self) StateKeysType {
            return self.stack[self.len - 1].key;
        }

        /// How many states are on the stack (1 when nothing is pushed).
        pub fn depth(self: *const Self) usize {
            return self.len;
        }

        /// True when `state` is anywhere on the stack.
        pub fn isOnStack(self: *const Self, state: StateKeysType) bool {
            for (self.stack[0..self.len]) |entry| {
                if (entry.key == state) return true;
            }
            return false;
        }

        /// Replaces the whole stack with `state`: deactivates every state
        /// on it, top first, then activates `state`. Setting the state that
        /// is already current deactivates and reactivates it.
        pub fn setCurrState(self: *Self, state: StateKeysType) void {
            std.log.debug("oldState = {t}, currState = {t}", .{ self.current(), state });

            while (self.len > 0) {
                self.len -= 1;
                self.callHook(self.stack[self.len].key, "deactivate");
            }

            self.stack[0] = .{ .key = state, .opts = .{} };
            self.len = 1;
            self.callHook(state, "activate");
        }

        /// Lays `state` over the current one: pauses the current state and
        /// activates `state`. A state can only be on the stack once, so
        /// pushing one that already is returns `error.StateAlreadyOnStack`
        /// and changes nothing.
        pub fn push(self: *Self, state: StateKeysType, opts: PushOptions) error{StateAlreadyOnStack}!void {
            if (self.isOnStack(state)) return error.StateAlreadyOnStack;
            std.log.debug("push {t} over {t}", .{ state, self.current() });

            self.callHook(self.current(), "pause");
            self.stack[self.len] = .{ .key = state, .opts = opts };
            self.len += 1;
            self.callHook(state, "activate");
        }

        /// Removes the top state: deactivates it and resumes the one
        /// below. The bottom state can't be popped (use `setCurrState` to
        /// replace it); trying returns `error.LastState` and changes
        /// nothing.
        pub fn pop(self: *Self) error{LastState}!void {
            if (self.len <= 1) return error.LastState;
            const top = self.current();
            std.log.debug("pop {t}", .{top});

            self.len -= 1;
            self.callHook(top, "deactivate");
            self.callHook(self.current(), "resume");
        }

        /// Updates the top state, plus each state below it for as long as
        /// the state above was pushed with `updateBelow`. Lower states
        /// update first. A state's `update` returns `void` or `!void`; an
        /// error is logged and calls `eng.quit()`.
        pub fn update(self: *Self, eng: *Engine, deltaMs: f64) void {
            var first = self.len - 1;
            while (first > 0 and self.stack[first].opts.updateBelow) first -= 1;

            for (self.stack[first..self.len]) |entry| {
                switch (entry.key) {
                    inline else => |key| comp.callUpdate(self.states[@backingInt(key)], eng, deltaMs, @tagName(key) ++ " state update"),
                }
            }
        }

        /// Renders the top state, plus each state below it for as long as
        /// the state above was pushed with `renderBelow`. Lower states
        /// render first, so the top state draws over them. Passes along
        /// the interpolation `alpha` (see `AppRunner`).
        pub fn render(self: *Self, eng: *Engine, alpha: f32) void {
            var first = self.len - 1;
            while (first > 0 and self.stack[first].opts.renderBelow) first -= 1;

            for (self.stack[first..self.len]) |entry| {
                switch (entry.key) {
                    inline else => |key| self.states[@backingInt(key)].render(eng, alpha),
                }
            }
        }

        /// Calls the optional no-argument hook `name` on `state`, if its
        /// type declares one.
        fn callHook(self: *Self, state: StateKeysType, comptime name: []const u8) void {
            switch (state) {
                inline else => |key| {
                    const statePtr = self.states[@backingInt(key)];
                    if (@hasDecl(@TypeOf(statePtr.*), name)) @field(@TypeOf(statePtr.*), name)(statePtr);
                },
            }
        }
    };
}
