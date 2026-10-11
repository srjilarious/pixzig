# Entities and Events

Pixzig doesn't force a way to organize your game objects. For small games, a few arrays of structs in your app are plenty. When you want an entity component system, pixzig bundles [flecs](https://www.flecs.dev/) through the [zflecs](https://github.com/zig-gamedev/zflecs) bindings, re-exported as `pixzig.flecs`. For letting systems talk to each other without knowing about each other, there's a small `EventBus`.

## A flecs World

Create a world, register your component types, and add entities:

```zig
const flecs = pixzig.flecs;

pub const Velocity = struct { v: pixzig.Vec2F };

// In init:
self.world = flecs.init();
flecs.COMPONENT(self.world, pixzig.Sprite);
flecs.COMPONENT(self.world, Velocity);

const e = flecs.new_id(self.world);
var spr = try eng.resources.createSprite("guy");
spr.setPos(40, 40);
flecs.set(self.world, e, pixzig.Sprite, spr);
flecs.set(self.world, e, Velocity, .{ .v = .{ .x = 1, .y = 0.5 } });

// In deinit:
_ = flecs.fini(self.world);
```

Pixzig's own types work fine as components. `Sprite` and `Actor` are the common ones, and the [sequencer](page:sequences) looks for them on entities.

## Queries

A query finds every entity with a set of components. Create it once and iterate it each tick:

```zig
// In init:
self.moveQuery = try flecs.query_init(self.world, &.{
    .terms = [_]flecs.term_t{
        .{ .id = flecs.id(pixzig.Sprite) },
        .{ .id = flecs.id(Velocity) },
    } ++ flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX - 2),
});

// In update:
var it = flecs.query_iter(self.world, self.moveQuery);
while (flecs.query_next(&it)) {
    const sprites = flecs.field(&it, pixzig.Sprite, 0).?;
    const vels = flecs.field(&it, Velocity, 1).?;
    for (sprites, vels) |*spr, vel| {
        const p = spr.pos();
        spr.setPosF(p.x + vel.v.x, p.y + vel.v.y);
    }
}

// In deinit, before fini:
flecs.query_fini(self.moveQuery);
```

The field index matches the term's position in the query. Pad the terms array out to `FLECS_TERM_COUNT_MAX` as shown, subtracting the number of terms you used.

Drawing works the same way: a query over `Sprite`, and `eng.renderer.drawSprite(&sprites[i])` inside a `begin`/`end` pair. Use `flecs.get(world, entity, T)` to read a component on one entity, which returns null if it doesn't have one.

For everything else, like systems, pipelines and relationships, see the flecs and zflecs docs. `examples/flecs_ex.zig` moves and draws sprite entities.

## The Event Bus

An `EventBus` passes events to anyone who subscribed. The usual event type is a tagged union, one case per kind of event:

```zig
pub const GameEvent = union(enum) {
    power_dot_eaten: void,
    ghost_eaten: struct { ghost: flecs.entity_t },
    level_cleared: void,
};
pub const EventBus = pixzig.events.EventBus(GameEvent);
```

A subscriber registers a pointer to itself and a callback. The callback gets that pointer back as `*anyopaque`:

```zig
pub const GhostSystem = struct {
    pub fn onEvent(ctx: *anyopaque, event: *GameEvent) void {
        const self: *GhostSystem = @ptrCast(@alignCast(ctx));
        switch (event.*) {
            .power_dot_eaten => self.makeGhostsScared(),
            .ghost_eaten => |e| self.sendHome(e.ghost),
            else => {},
        }
    }
};

// In init:
self.bus = EventBus.init(alloc);
try self.bus.subscribe(&self.ghosts, GhostSystem.onEvent);

// Wherever something happens:
var ev: GameEvent = .power_dot_eaten;
self.bus.emit(&ev);

// In deinit:
self.bus.deinit();
```

`emit` calls every subscriber right away, in the order they subscribed. Subscribers get a pointer to the event, so one can fill in a reply for the code that emitted it. The subscriber has to outlive the bus, or at least every `emit`; there's no unsubscribe.
