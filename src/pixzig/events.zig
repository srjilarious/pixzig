// An event bus for letting different systems communicate.
const std = @import("std");

pub fn EventBus(EventType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        subscriptions: std.ArrayList(Subscription),

        const Self = @This();
        const Callback = *const fn (ctxt: *anyopaque, event_data: *EventType) void;

        const Subscription = struct {
            ctxt: *anyopaque,
            callback: Callback,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .subscriptions = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.subscriptions.deinit(self.allocator);
        }

        pub fn subscribe(self: *Self, ctxt: *anyopaque, callback: Callback) !void {
            try self.subscriptions.append(self.allocator, .{ .ctxt = ctxt, .callback = callback });
        }

        pub fn emit(self: *Self, event_data: *EventType) void {
            for (self.subscriptions.items) |sub| {
                sub.callback(sub.ctxt, event_data);
            }
        }
    };
}
