const std = @import("std");

/// A generic event bus system for letting different systems witin an
/// application communicate ina decoupled fashion.
///
/// Each subscriber calls `EventBus.subscribe` with a callback and a context pointer. The callback is called with the context pointer and the event data when an event is emitted.  Generally the event type is a union(enum) so that different events can have different data associated with them. The context pointer is used to allow the callback to have some state, such as a pointer to the system that is subscribing to the event.
///
/// Here's an example of how you can use the event bus:
/// ```zig
/// pub const GhostEatenData = struct {
///     ghost_entity: flecs.entity_t,
/// };
///
/// pub const GameEvent = union(enum) {
///     PowerDotEaten: void,
///     PowerDotFinished: void,
///     GhostEaten: GhostEatenData,
/// };
///
/// pub const GameEventBus = pixzig.events.EventBus(GameEvent);
/// ```
///
/// Then, to subscribe to an event:
/// ```zig
/// pub const GhostSystem  = struct {
/// pub fn onGameEvent(selfAO: *anyopaque, event: *GameEvent) void {
///         const self: *Self = @ptrCast(@alignCast(selfAO));
///         switch (event.*) {
///             .PowerDotEaten => {
///                 std.log.info("GhostControl handling PowerDotEaten event!", .{});
///                 // ...
///             },
///             .PowerDotFinished => {
///                 std.log.info("Ghost control handling PowerDotFinished event!", .{});
///                 // ...
///             },
///             .GhostEaten => |ge| {
///                 std.log.info("Ghost control handling GhostEaten event for entity: {}", .{ge.ghost_entity});
///                 const ghost_ent = ge.ghost_entity;
///
///                 // ...
///             },
///             // else => {}, // In this case we handled all the game events.
///         }
///     }
/// }
/// ```
pub fn EventBus(EventType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        subscriptions: std.ArrayList(Subscription),

        const Self = @This();

        /// The callback type for event subscribers. It takes a context pointer
        /// and a pointer to the event data.
        pub const Callback = *const fn (ctxt: *anyopaque, event_data: *EventType) void;

        const Subscription = struct {
            ctxt: *anyopaque,
            callback: Callback,
        };

        /// Initializes the event bus with the provided allocator.
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .subscriptions = .{},
            };
        }

        /// Deinitializes the event bus, freeing the subscriptions list.
        pub fn deinit(self: *Self) void {
            self.subscriptions.deinit(self.allocator);
        }

        /// Subscribes to the event bus with a context pointer and a callback
        /// function. The callback will be called with the context pointer and
        /// the event data when an event is emitted.
        pub fn subscribe(self: *Self, ctxt: *anyopaque, callback: Callback) !void {
            try self.subscriptions.append(self.allocator, .{ .ctxt = ctxt, .callback = callback });
        }

        /// Emits an event to all subscribed listeners. The event data is
        /// passed to each subscriber's callback function along with their
        /// context pointer.
        pub fn emit(self: *Self, event_data: *EventType) void {
            for (self.subscriptions.items) |sub| {
                sub.callback(sub.ctxt, event_data);
            }
        }
    };
}
