const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

// Minimal engine stub. GameStateMgr passes it by pointer to state methods,
// and calls `quit` when a state's update returns an error.
const MockEngine = struct {
    quitCalled: bool = false,

    pub fn quit(self: *MockEngine) void {
        self.quitCalled = true;
    }
};

// Module-level counters for lifecycle tracking.  Reset at the start of each test.
var activateCountA: i32 = 0;
var deactivateCountA: i32 = 0;
var activateCountB: i32 = 0;
var deactivateCountB: i32 = 0;
var lastUpdateState: usize = 99;
var lastRenderState: usize = 99;
var lastRenderAlpha: f32 = -1;

fn resetCounters() void {
    activateCountA = 0;
    deactivateCountA = 0;
    activateCountB = 0;
    deactivateCountB = 0;
    lastUpdateState = 99;
    lastRenderState = 99;
}

// StateA — has full lifecycle hooks. update keeps running.
const StateA = struct {
    pub fn activate(self: *StateA) void {
        _ = self;
        activateCountA += 1;
    }
    pub fn deactivate(self: *StateA) void {
        _ = self;
        deactivateCountA += 1;
    }
    pub fn update(self: *StateA, eng: *MockEngine, delta: f64) void {
        _ = self;
        _ = eng;
        _ = delta;
        lastUpdateState = 0;
    }
    pub fn render(self: *StateA, eng: *MockEngine, alpha: f32) void {
        _ = self;
        _ = eng;
        lastRenderState = 0;
        lastRenderAlpha = alpha;
    }
};

// StateB — has full lifecycle hooks. update returns false (signals exit).
const StateB = struct {
    pub fn activate(self: *StateB) void {
        _ = self;
        activateCountB += 1;
    }
    pub fn deactivate(self: *StateB) void {
        _ = self;
        deactivateCountB += 1;
    }
    pub fn update(self: *StateB, eng: *MockEngine, delta: f64) void {
        _ = self;
        _ = delta;
        lastUpdateState = 1;
        eng.quit();
    }
    pub fn render(self: *StateB, eng: *MockEngine, alpha: f32) void {
        _ = alpha;
        _ = self;
        _ = eng;
        lastRenderState = 1;
    }
};

// StateErr — update fails, which the manager turns into eng.quit().
const StateErr = struct {
    pub fn update(self: *StateErr, eng: *MockEngine, delta: f64) !void {
        _ = self;
        _ = eng;
        _ = delta;
        lastUpdateState = 3;
        return error.Boom;
    }
    pub fn render(self: *StateErr, eng: *MockEngine, alpha: f32) void {
        _ = alpha;
        _ = self;
        _ = eng;
    }
};

// StateC — no lifecycle hooks, so missing activate/deactivate is handled silently.
const StateC = struct {
    pub fn update(self: *StateC, eng: *MockEngine, delta: f64) void {
        _ = self;
        _ = eng;
        _ = delta;
        lastUpdateState = 2;
    }
    pub fn render(self: *StateC, eng: *MockEngine, alpha: f32) void {
        _ = alpha;
        _ = self;
        _ = eng;
        lastRenderState = 2;
    }
};

const States2 = enum { A, B };
const Mgr2 = pixzig.gamestate.GameStateMgr(MockEngine, States2, &[_]type{ StateA, StateB });

const States3 = enum { A, B, C };
const Mgr3 = pixzig.gamestate.GameStateMgr(MockEngine, States3, &[_]type{ StateA, StateB, StateC });

const StatesErr = enum { A, Err };
const MgrErr = pixzig.gamestate.GameStateMgr(MockEngine, StatesErr, &[_]type{ StateA, StateErr });

// setCurrState activates the newly selected state.
pub fn gameStateActivateCalledOnSetTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var mgr = Mgr2.init(.{ &stateA, &stateB });

    // Switching from the default index (0 = A) to B:
    // deactivates the previous slot (A), activates B.
    mgr.setCurrState(.B);

    try testz.expectEqual(activateCountB, 1);
    try testz.expectEqual(deactivateCountA, 1);
    // A was never activated, B was never deactivated.
    try testz.expectEqual(activateCountA, 0);
    try testz.expectEqual(deactivateCountB, 0);
}

// Switching states deactivates the old one and activates the new one.
pub fn gameStateSwitchDeactivatesOldActivatesNewTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var mgr = Mgr2.init(.{ &stateA, &stateB });

    // First switch: deactivate default slot (A), activate A.
    mgr.setCurrState(.A);
    try testz.expectEqual(deactivateCountA, 1);
    try testz.expectEqual(activateCountA, 1);

    // Second switch: deactivate A, activate B.
    mgr.setCurrState(.B);
    try testz.expectEqual(deactivateCountA, 2);
    try testz.expectEqual(activateCountB, 1);
    try testz.expectEqual(deactivateCountB, 0);
}

// update delegates to the active state and returns its result.
pub fn gameStateUpdateDelegatesToActiveStateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var mgr = Mgr2.init(.{ &stateA, &stateB });
    var eng = MockEngine{};

    mgr.setCurrState(.A);
    lastUpdateState = 99;
    mgr.update(&eng, 16.0);
    try testz.expectFalse(eng.quitCalled); // StateA keeps running
    try testz.expectEqual(lastUpdateState, 0);

    mgr.setCurrState(.B);
    lastUpdateState = 99;
    mgr.update(&eng, 16.0);
    try testz.expectTrue(eng.quitCalled); // StateB calls eng.quit()
    try testz.expectEqual(lastUpdateState, 1);
}

// A state whose update returns an error quits the engine.
pub fn gameStateUpdateErrorQuitsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    resetCounters();
    var stateA = StateA{};
    var stateErr = StateErr{};
    var mgr = MgrErr.init(.{ &stateA, &stateErr });
    var eng = MockEngine{};

    mgr.setCurrState(.Err);
    mgr.update(&eng, 16.0);
    try testz.expectEqual(lastUpdateState, 3);
    try testz.expectTrue(eng.quitCalled);
}

// render delegates to the active state.
pub fn gameStateRenderDelegatesToActiveStateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var mgr = Mgr2.init(.{ &stateA, &stateB });
    var eng = MockEngine{};

    mgr.setCurrState(.A);
    lastRenderState = 99;
    mgr.render(&eng, 0.25);
    try testz.expectEqual(lastRenderState, 0);
    try testz.expectEqual(lastRenderAlpha, 0.25);

    mgr.setCurrState(.B);
    lastRenderState = 99;
    mgr.render(&eng, 1.0);
    try testz.expectEqual(lastRenderState, 1);
}

// States without lifecycle hooks can be set and used without panicking.
pub fn gameStateNoLifecycleHooksTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var stateC = StateC{};
    var mgr = Mgr3.init(.{ &stateA, &stateB, &stateC });
    var eng = MockEngine{};

    // StateC has no activate/deactivate — this must not panic.
    mgr.setCurrState(.C);

    lastUpdateState = 99;
    mgr.update(&eng, 16.0);
    try testz.expectEqual(lastUpdateState, 2);

    lastRenderState = 99;
    mgr.render(&eng, 1.0);
    try testz.expectEqual(lastRenderState, 2);
}

// Switching back to a previously active state calls its lifecycle hooks again.
pub fn gameStateSwitchBackReinvokesLifecycleTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var mgr = Mgr2.init(.{ &stateA, &stateB });

    mgr.setCurrState(.A); // deactivate A(default), activate A
    mgr.setCurrState(.B); // deactivate A, activate B
    mgr.setCurrState(.A); // deactivate B, activate A

    try testz.expectEqual(activateCountA, 2);
    try testz.expectEqual(deactivateCountA, 2);
    try testz.expectEqual(activateCountB, 1);
    try testz.expectEqual(deactivateCountB, 1);
}
