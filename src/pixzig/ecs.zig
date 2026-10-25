//! Thin flecs helpers for the code every game writes: building queries,
//! registering components, drawing `Sprite`s, updating and drawing
//! `Actor`s, and debug outlines. Not a framework: each helper owns a flecs
//! query and is called from the app's own `update`/`render`, so a game
//! mixes them freely with its own systems.
//!
//! ```zig
//! ecs.registerEngineComponents(world);
//! ecs.registerComponents(world, .{ Velocity, Player });
//! const moveQuery = try ecs.query(world, .{ Sprite, Velocity });
//!
//! var sprites = try ecs.SpriteSystem.init(world);
//! defer sprites.deinit();
//! ...
//! sprites.draw(&eng.renderer);
//! ```
const std = @import("std");
const flecs = @import("zflecs");
const common = @import("./common.zig");
const sprites = @import("./renderer/sprites.zig");
const camera = @import("./camera.zig");
const scripting = @import("./scripting.zig");
const ziglua = @import("ziglua");

const Sprite = sprites.Sprite;
const Actor = sprites.Actor;
const Color = common.Color;
const Vec2F = common.Vec2F;
const Camera2D = camera.Camera2D;

/// Marks an entity for `DebugOutlines`: its `Sprite` (or its `Actor`'s
/// sprite) gets a rectangle of `color` drawn around it.
pub const Outline = struct {
    color: Color,
};

/// Builds a query matching entities that have every type in `terms`, e.g.
/// `query(world, .{ Sprite, Velocity })`. `flecs.field(&it, T, i)` then
/// reads the `i`th type. An entry may also be a `flecs.term_t` for a term
/// a bare type can't say (`.oper = .Not`, a pair, ...). Free the result
/// with `flecs.query_fini`.
pub fn query(world: *flecs.world_t, terms: anytype) !*flecs.query_t {
    if (terms.len > flecs.FLECS_TERM_COUNT_MAX) {
        @compileError("ecs.query: more terms than flecs.FLECS_TERM_COUNT_MAX");
    }
    var desc: flecs.query_desc_t = .{
        .terms = flecs.array(flecs.term_t, flecs.FLECS_TERM_COUNT_MAX),
    };
    inline for (terms, 0..) |term, idx| {
        desc.terms[idx] = if (@TypeOf(term) == type) .{ .id = flecs.id(term) } else term;
    }
    return flecs.query_init(world, &desc);
}

/// Registers every type in `types` as a flecs component (zero-sized types
/// as tags). Registering a type twice is harmless.
pub fn registerComponents(world: *flecs.world_t, comptime types: anytype) void {
    inline for (types) |T| {
        if (@sizeOf(T) == 0) flecs.TAG(world, T) else flecs.COMPONENT(world, T);
    }
}

/// Registers the engine's own component types: `Sprite`, `Actor` and
/// `Outline`. The helpers here and `sequencer.MoveToStep` query both
/// `Sprite` and `Actor`, so register them even if a game only uses one.
pub fn registerEngineComponents(world: *flecs.world_t) void {
    registerComponents(world, .{ Sprite, Actor, Outline });
}

/// Draws every entity's `Sprite`.
pub const SpriteSystem = struct {
    world: *flecs.world_t,
    query: *flecs.query_t,

    /// Registers the engine components if needed and builds the query.
    pub fn init(world: *flecs.world_t) !SpriteSystem {
        registerEngineComponents(world);
        return .{ .world = world, .query = try query(world, .{Sprite}) };
    }

    pub fn deinit(self: *SpriteSystem) void {
        flecs.query_fini(self.query);
    }

    /// Draws each `Sprite` through `renderer` (an engine `Renderer`).
    pub fn draw(self: *SpriteSystem, renderer: anytype) void {
        var it = flecs.query_iter(self.world, self.query);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 0).?;
            for (spr) |*s| renderer.drawSprite(s);
        }
    }
};

/// Advances and draws every entity's `Actor`.
pub const ActorSystem = struct {
    world: *flecs.world_t,
    query: *flecs.query_t,

    /// Registers the engine components if needed and builds the query.
    pub fn init(world: *flecs.world_t) !ActorSystem {
        registerEngineComponents(world);
        return .{ .world = world, .query = try query(world, .{Actor}) };
    }

    pub fn deinit(self: *ActorSystem) void {
        flecs.query_fini(self.query);
    }

    /// Advances each actor's animation by `deltaMs`.
    pub fn update(self: *ActorSystem, deltaMs: f64) void {
        var it = flecs.query_iter(self.world, self.query);
        while (flecs.query_next(&it)) {
            const actors = flecs.field(&it, Actor, 0).?;
            for (actors) |*a| a.update(deltaMs);
        }
    }

    /// Draws each actor's current frame through `renderer`.
    pub fn draw(self: *ActorSystem, renderer: anytype) void {
        var it = flecs.query_iter(self.world, self.query);
        while (flecs.query_next(&it)) {
            const actors = flecs.field(&it, Actor, 0).?;
            for (actors) |*a| renderer.drawSprite(&a.sprite);
        }
    }
};

/// Draws a rectangle around every entity that has an `Outline` and either
/// a `Sprite` or an `Actor`. Starts disabled; flip `enabled`, call
/// `toggle`, or `bindConsole` a Lua function that toggles it.
pub const DebugOutlines = struct {
    world: *flecs.world_t,
    spriteQuery: *flecs.query_t,
    actorQuery: *flecs.query_t,
    enabled: bool = false,
    lineWidth: u8 = 1,

    /// Registers the engine components if needed and builds the queries.
    pub fn init(world: *flecs.world_t) !DebugOutlines {
        registerEngineComponents(world);
        const spriteQuery = try query(world, .{ Sprite, Outline });
        errdefer flecs.query_fini(spriteQuery);
        return .{
            .world = world,
            .spriteQuery = spriteQuery,
            .actorQuery = try query(world, .{ Actor, Outline }),
        };
    }

    pub fn deinit(self: *DebugOutlines) void {
        flecs.query_fini(self.spriteQuery);
        flecs.query_fini(self.actorQuery);
    }

    pub fn toggle(self: *DebugOutlines) void {
        self.enabled = !self.enabled;
    }

    /// Registers a global Lua function `name` (e.g. "toggleOutlines") that
    /// toggles the outlines, so the console can flip them. `self` must
    /// outlive the script engine's use of it.
    pub fn bindConsole(self: *DebugOutlines, scripts: *scripting.ScriptEngine, name: []const u8) !void {
        try scripts.registerMethod(DebugOutlines, self, name, luaToggle);
    }

    fn luaToggle(self: *DebugOutlines, _: *ziglua.Lua) i32 {
        self.toggle();
        std.log.info("Debug outlines {s}", .{if (self.enabled) "on" else "off"});
        return 0;
    }

    /// Draws the outlines through `renderer` when enabled. Needs
    /// `RendererOptions.shapeRendering`.
    pub fn draw(self: *DebugOutlines, renderer: anytype) void {
        if (!self.enabled) return;

        var it = flecs.query_iter(self.world, self.spriteQuery);
        while (flecs.query_next(&it)) {
            const spr = flecs.field(&it, Sprite, 0).?;
            const outline = flecs.field(&it, Outline, 1).?;
            for (spr, outline) |*s, o| renderer.drawEnclosingRect(s.dest, o.color, self.lineWidth);
        }

        var ait = flecs.query_iter(self.world, self.actorQuery);
        while (flecs.query_next(&ait)) {
            const actors = flecs.field(&ait, Actor, 0).?;
            const outline = flecs.field(&ait, Outline, 1).?;
            for (actors, outline) |*a, o| renderer.drawEnclosingRect(a.sprite.dest, o.color, self.lineWidth);
        }
    }
};

/// The centre of `entity`'s `Sprite`, or of its `Actor`'s sprite, or null
/// when it has neither.
pub fn spriteCenter(world: *flecs.world_t, entity: flecs.entity_t) ?Vec2F {
    if (flecs.get(world, entity, Sprite)) |s| return s.dest.centerF();
    if (flecs.get(world, entity, Actor)) |a| return a.sprite.dest.centerF();
    return null;
}

/// Moves `cam` toward the centre of `entity`'s sprite with
/// `Camera2D.follow`. Leaves the camera alone when the entity has no
/// `Sprite` or `Actor`.
pub fn followEntity(
    cam: *Camera2D,
    world: *flecs.world_t,
    entity: flecs.entity_t,
    deltaMs: f64,
    opts: Camera2D.FollowOptions,
) void {
    const target = spriteCenter(world, entity) orelse return;
    cam.follow(target, deltaMs, opts);
}
