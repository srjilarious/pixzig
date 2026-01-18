const std = @import("std");
const testz = @import("testz");
const events = @import("pixzig").events;

fn basicEventCallback(ctxt: *anyopaque, event_data: *i32) void {
    _ = event_data;
    const called_ptr: *bool = @ptrCast(ctxt);
    called_ptr.* = true;
}

pub fn basicEventTest() !void {
    var bus = events.EventBus(i32).init(std.heap.page_allocator);
    defer bus.deinit();

    var called = false;

    try bus.subscribe(&called, basicEventCallback);

    var event_value: i32 = 42;
    bus.emit(&event_value);

    try testz.expectEqual(called, true);
}

const GameEvent = enum {
    A,
    B,
    C,
};

fn gameEventCallback(ctxt: *anyopaque, event_data: *GameEvent) void {
    const called_ptr: *i32 = @ptrCast(@alignCast(ctxt));

    switch (event_data.*) {
        .A => called_ptr.* = 10,
        .B => called_ptr.* = 20,
        .C => called_ptr.* = 30,
    }
}

pub fn gameEventTest() !void {
    var bus = events.EventBus(GameEvent).init(std.heap.page_allocator);
    defer bus.deinit();

    var ctxt: i32 = 0;

    try bus.subscribe(&ctxt, gameEventCallback);

    var event_value: GameEvent = .A;
    bus.emit(&event_value);
    try testz.expectEqual(ctxt, 10);

    event_value = .B;
    bus.emit(&event_value);
    try testz.expectEqual(ctxt, 20);

    event_value = .C;
    bus.emit(&event_value);
    try testz.expectEqual(ctxt, 30);
}
