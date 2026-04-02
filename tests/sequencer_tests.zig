const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const seq = pixzig.sequencer;

// A single WaitStep should not be done before its duration elapses.
pub fn waitStepNotDoneBeforeDurationTest() !void {
    const alloc = std.heap.page_allocator;
    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);

    try sequence.add(alloc, try seq.WaitStep.init(alloc, 100.0));

    try testz.expectFalse(sequence.update(50.0));
    try testz.expectFalse(sequence.done);
}

// A single WaitStep should be done once its full duration has elapsed.
pub fn waitStepDoneAfterDurationTest() !void {
    const alloc = std.heap.page_allocator;
    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);

    try sequence.add(alloc, try seq.WaitStep.init(alloc, 100.0));

    _ = sequence.update(50.0);
    try testz.expectTrue(sequence.update(50.0));
    try testz.expectTrue(sequence.done);
}

// An empty sequence should complete immediately.
pub fn emptySequenceIsDoneImmediatelyTest() !void {
    const alloc = std.heap.page_allocator;
    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);

    try testz.expectTrue(sequence.update(16.0));
    try testz.expectTrue(sequence.done);
}

// Two sequential waits should run one after the other.
pub fn twoWaitStepsRunSequentiallyTest() !void {
    const alloc = std.heap.page_allocator;
    var sequence = seq.Sequence.init(alloc);
    defer sequence.deinit(alloc);

    try sequence.add(alloc, try seq.WaitStep.init(alloc, 100.0));
    try sequence.add(alloc, try seq.WaitStep.init(alloc, 100.0));

    // First step not done yet.
    try testz.expectFalse(sequence.update(50.0));

    // First step finishes; second step starts but isn't done.
    try testz.expectFalse(sequence.update(50.0));

    // Second step not done yet.
    try testz.expectFalse(sequence.update(50.0));

    // Second step finishes; sequence done.
    try testz.expectTrue(sequence.update(50.0));
    try testz.expectTrue(sequence.done);
}
