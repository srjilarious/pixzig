const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

// Minimal engine stub — GameStateMgr only passes it by pointer to state methods.
const MockEngine = struct {};

// Module-level counters for lifecycle tracking.  Reset at the start of each test.
var activateCountA: i32 = 0;
var deactivateCountA: i32 = 0;
var activateCountB: i32 = 0;
var deactivateCountB: i32 = 0;
var lastUpdateState: usize = 99;
var lastRenderState: usize = 99;

fn resetCounters() void {
    activateCountA = 0;
    deactivateCountA = 0;
    activateCountB = 0;
    deactivateCountB = 0;
    lastUpdateState = 99;
    lastRenderState = 99;
}

// StateA — has full lifecycle hooks. update returns true.
const StateA = struct {
    pub fn activate(self: *StateA) void {
        _ = self;
        activateCountA += 1;
    }
    pub fn deactivate(self: *StateA) void {
        _ = self;
        deactivateCountA += 1;
    }
    pub fn update(self: *StateA, eng: *MockEngine, delta: f64) bool {
        _ = self;
        _ = eng;
        _ = delta;
        lastUpdateState = 0;
        return true;
    }
    pub fn render(self: *StateA, eng: *MockEngine) void {
        _ = self;
        _ = eng;
        lastRenderState = 0;
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
    pub fn update(self: *StateB, eng: *MockEngine, delta: f64) bool {
        _ = self;
        _ = eng;
        _ = delta;
        lastUpdateState = 1;
        return false;
    }
    pub fn render(self: *StateB, eng: *MockEngine) void {
        _ = self;
        _ = eng;
        lastRenderState = 1;
    }
};

// StateC — no lifecycle hooks, so missing activate/deactivate is handled silently.
const StateC = struct {
    pub fn update(self: *StateC, eng: *MockEngine, delta: f64) bool {
        _ = self;
        _ = eng;
        _ = delta;
        lastUpdateState = 2;
        return true;
    }
    pub fn render(self: *StateC, eng: *MockEngine) void {
        _ = self;
        _ = eng;
        lastRenderState = 2;
    }
};

const States2 = enum { A, B };
const Mgr2 = pixzig.gamestate.GameStateMgr(MockEngine, States2, &[_]type{ StateA, StateB });

const States3 = enum { A, B, C };
const Mgr3 = pixzig.gamestate.GameStateMgr(MockEngine, States3, &[_]type{ StateA, StateB, StateC });

fn makeMgr2() struct { mgr: Mgr2, a: StateA, b: StateB } {
    var r: struct { mgr: Mgr2, a: StateA, b: StateB } = undefined;
    r.a = StateA{};
    r.b = StateB{};
    return r;
}

// setCurrState activates the newly selected state.
pub fn gameStateActivateCalledOnSetTest() !void {
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var arr = [_]*anyopaque{ @ptrCast(&stateA), @ptrCast(&stateB) };
    var mgr = Mgr2.init(arr[0..]);

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
pub fn gameStateSwitchDeactivatesOldActivatesNewTest() !void {
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var arr = [_]*anyopaque{ @ptrCast(&stateA), @ptrCast(&stateB) };
    var mgr = Mgr2.init(arr[0..]);

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
pub fn gameStateUpdateDelegatesToActiveStateTest() !void {
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var arr = [_]*anyopaque{ @ptrCast(&stateA), @ptrCast(&stateB) };
    var mgr = Mgr2.init(arr[0..]);
    var eng = MockEngine{};

    mgr.setCurrState(.A);
    lastUpdateState = 99;
    const resultA = mgr.update(&eng, 16.0);
    try testz.expectTrue(resultA); // StateA.update returns true
    try testz.expectEqual(lastUpdateState, 0);

    mgr.setCurrState(.B);
    lastUpdateState = 99;
    const resultB = mgr.update(&eng, 16.0);
    try testz.expectFalse(resultB); // StateB.update returns false
    try testz.expectEqual(lastUpdateState, 1);
}

// render delegates to the active state.
pub fn gameStateRenderDelegatesToActiveStateTest() !void {
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var arr = [_]*anyopaque{ @ptrCast(&stateA), @ptrCast(&stateB) };
    var mgr = Mgr2.init(arr[0..]);
    var eng = MockEngine{};

    mgr.setCurrState(.A);
    lastRenderState = 99;
    mgr.render(&eng);
    try testz.expectEqual(lastRenderState, 0);

    mgr.setCurrState(.B);
    lastRenderState = 99;
    mgr.render(&eng);
    try testz.expectEqual(lastRenderState, 1);
}

// States without lifecycle hooks can be set and used without panicking.
pub fn gameStateNoLifecycleHooksTest() !void {
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var stateC = StateC{};
    var arr = [_]*anyopaque{ @ptrCast(&stateA), @ptrCast(&stateB), @ptrCast(&stateC) };
    var mgr = Mgr3.init(arr[0..]);
    var eng = MockEngine{};

    // StateC has no activate/deactivate — this must not panic.
    mgr.setCurrState(.C);

    lastUpdateState = 99;
    _ = mgr.update(&eng, 16.0);
    try testz.expectEqual(lastUpdateState, 2);

    lastRenderState = 99;
    mgr.render(&eng);
    try testz.expectEqual(lastRenderState, 2);
}

// Switching back to a previously active state calls its lifecycle hooks again.
pub fn gameStateSwitchBackReinvokesLifecycleTest() !void {
    resetCounters();
    var stateA = StateA{};
    var stateB = StateB{};
    var arr = [_]*anyopaque{ @ptrCast(&stateA), @ptrCast(&stateB) };
    var mgr = Mgr2.init(arr[0..]);

    mgr.setCurrState(.A); // deactivate A(default), activate A
    mgr.setCurrState(.B); // deactivate A, activate B
    mgr.setCurrState(.A); // deactivate B, activate A

    try testz.expectEqual(activateCountA, 2);
    try testz.expectEqual(deactivateCountA, 2);
    try testz.expectEqual(activateCountB, 1);
    try testz.expectEqual(deactivateCountB, 1);
}
