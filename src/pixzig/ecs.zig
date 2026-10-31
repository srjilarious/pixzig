//! Thin flecs helpers for the code every game writes: building queries,
//! registering components, drawing `Sprite`s, updating and drawing
//! `Actor`s, and debug outlines. Not a framework: each helper owns a flecs
//! query and is called from the app's own `update`/`render`, so a game
//! mixes them freely with its own systems.
//!
//! The draw helpers sort by `ZOrder` (lower z first) and, inside a
//! `.camera` pass, skip whatever lies outside the camera's view.
//!
//! ```zig
//! ecs.registerEngineComponents(world);
//! ecs.registerComponents(world, .{ Velocity, Player });
//! const moveQuery = try ecs.query(world, .{ Sprite, Velocity });
//!
//! var draws = try ecs.DrawSystem.init(alloc, world);
//! defer draws.deinit();
//! ...
//! flecs.set(world, player, ecs.ZOrder, .{ .z = 10 });
//! ...
//! eng.renderer.begin(.{ .camera = &cam });
//! draws.draw(&eng.renderer);
//! eng.renderer.end();
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
const RectF = common.RectF;
const Camera2D = camera.Camera2D;

/// Draw order for an entity's `Sprite` or `Actor`. The draw helpers draw
/// lower `z` first, so higher `z` lands on top; entities without a
/// `ZOrder` draw at z 0. Ties go by entity id, so the order holds when a
/// component is added or removed (which moves the entity to another flecs
/// archetype).
pub const ZOrder = struct {
    z: i32 = 0,
};

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

/// Registers the engine's own component types: `Sprite`, `Actor`,
/// `ZOrder` and `Outline`. The helpers here and `sequencer.MoveToStep`
/// query both `Sprite` and `Actor`, so register them even if a game only
/// uses one.
pub fn registerEngineComponents(world: *flecs.world_t) void {
    registerComponents(world, .{ Sprite, Actor, ZOrder, Outline });
}

/// One sprite waiting to be drawn, with the key it sorts by.
const DrawItem = struct {
    z: i32,
    id: flecs.entity_t,
    sprite: *const Sprite,

    fn lessThan(_: void, a: DrawItem, b: DrawItem) bool {
        if (a.z != b.z) return a.z < b.z;
        return a.id < b.id;
    }
};

/// The per-frame scratch list behind the draw helpers: gathers sprites
/// from one or more queries, drops the ones outside the view, sorts by
/// `ZOrder` and submits them. Keeps its capacity between frames, so a
/// steady scene stops allocating after its first frame.
const DrawList = struct {
    alloc: std.mem.Allocator,
    items: std.ArrayList(DrawItem) = .empty,
    /// Sprites submitted by the last draw.
    drawn: usize = 0,
    /// Sprites the last draw skipped because they were outside the view.
    culled: usize = 0,
    /// Set once the list has failed to grow, so the error logs once.
    warnedOom: bool = false,

    fn deinit(self: *DrawList) void {
        self.items.deinit(self.alloc);
    }

    fn reset(self: *DrawList) void {
        self.items.clearRetainingCapacity();
        self.drawn = 0;
        self.culled = 0;
    }

    /// Adds every match of `q` that overlaps `view` (null keeps
    /// everything). `q` is a `drawQuery` for `C`, which is `Sprite` or
    /// `Actor`. If the list can't grow, the sprite is drawn straight away
    /// instead, out of order.
    fn gather(
        self: *DrawList,
        comptime C: type,
        world: *flecs.world_t,
        q: *flecs.query_t,
        view: ?RectF,
        renderer: anytype,
    ) void {
        var it = flecs.query_iter(world, q);
        while (flecs.query_next(&it)) {
            const comps = flecs.field(&it, C, 0).?;
            // Null when this archetype has no ZOrder (the term is optional).
            const zorders = flecs.field(&it, ZOrder, 1);
            const ids = it.entities();
            for (comps, 0..) |*c, idx| {
                const spr: *const Sprite = if (C == Actor) &c.sprite else c;
                if (view) |v| {
                    if (!spr.dest.intersects(&v)) {
                        self.culled += 1;
                        continue;
                    }
                }
                const item: DrawItem = .{
                    .z = if (zorders) |zs| zs[idx].z else 0,
                    .id = ids[idx],
                    .sprite = spr,
                };
                self.items.append(self.alloc, item) catch {
                    if (!self.warnedOom) {
                        std.log.err("ecs: out of memory sorting sprites; drawing unsorted", .{});
                        self.warnedOom = true;
                    }
                    renderer.drawSprite(spr);
                    self.drawn += 1;
                };
            }
        }
    }

    /// Sorts what was gathered and draws it through `renderer`.
    fn submit(self: *DrawList, renderer: anytype) void {
        std.sort.pdq(DrawItem, self.items.items, {}, DrawItem.lessThan);
        for (self.items.items) |item| renderer.drawSprite(item.sprite);
        self.drawn += self.items.items.len;
    }
};

/// The query the draw helpers use: `C` plus an optional `ZOrder`.
fn drawQuery(world: *flecs.world_t, comptime C: type) !*flecs.query_t {
    return query(world, .{ C, flecs.term_t{ .id = flecs.id(ZOrder), .oper = .Optional } });
}

/// Draws every entity's `Sprite`, sorted by `ZOrder` and culled to the
/// camera. To interleave sprites with actors, draw with `DrawSystem`.
pub const SpriteSystem = struct {
    world: *flecs.world_t,
    query: *flecs.query_t,
    list: DrawList,

    /// Registers the engine components if needed and builds the query.
    /// `alloc` backs the per-frame sort list.
    pub fn init(alloc: std.mem.Allocator, world: *flecs.world_t) !SpriteSystem {
        registerEngineComponents(world);
        return .{ .world = world, .query = try drawQuery(world, Sprite), .list = .{ .alloc = alloc } };
    }

    pub fn deinit(self: *SpriteSystem) void {
        flecs.query_fini(self.query);
        self.list.deinit();
    }

    /// Draws each `Sprite` through `renderer` (an engine `Renderer`),
    /// lowest `ZOrder` first. Inside a `.camera` pass, sprites outside
    /// `renderer.viewRect()` are skipped.
    pub fn draw(self: *SpriteSystem, renderer: anytype) void {
        self.list.reset();
        self.list.gather(Sprite, self.world, self.query, renderer.viewRect(), renderer);
        self.list.submit(renderer);
    }

    /// Sprites drawn by the last `draw`.
    pub fn lastDrawn(self: *const SpriteSystem) usize {
        return self.list.drawn;
    }

    /// Sprites the last `draw` skipped as off camera.
    pub fn lastCulled(self: *const SpriteSystem) usize {
        return self.list.culled;
    }
};

/// Advances and draws every entity's `Actor`. Drawing is sorted by
/// `ZOrder` and culled to the camera; to interleave actors with plain
/// sprites, draw with `DrawSystem` and use this only for `update`.
pub const ActorSystem = struct {
    world: *flecs.world_t,
    query: *flecs.query_t,
    list: DrawList,

    /// Registers the engine components if needed and builds the query.
    /// `alloc` backs the per-frame sort list.
    pub fn init(alloc: std.mem.Allocator, world: *flecs.world_t) !ActorSystem {
        registerEngineComponents(world);
        return .{ .world = world, .query = try drawQuery(world, Actor), .list = .{ .alloc = alloc } };
    }

    pub fn deinit(self: *ActorSystem) void {
        flecs.query_fini(self.query);
        self.list.deinit();
    }

    /// Advances each actor's animation by `deltaMs`. Off-camera actors
    /// advance too; culling only affects drawing.
    pub fn update(self: *ActorSystem, deltaMs: f64) void {
        var it = flecs.query_iter(self.world, self.query);
        while (flecs.query_next(&it)) {
            const actors = flecs.field(&it, Actor, 0).?;
            for (actors) |*a| a.update(deltaMs);
        }
    }

    /// Draws each actor's current frame through `renderer`, lowest
    /// `ZOrder` first. Inside a `.camera` pass, actors outside
    /// `renderer.viewRect()` are skipped.
    pub fn draw(self: *ActorSystem, renderer: anytype) void {
        self.list.reset();
        self.list.gather(Actor, self.world, self.query, renderer.viewRect(), renderer);
        self.list.submit(renderer);
    }

    /// Actors drawn by the last `draw`.
    pub fn lastDrawn(self: *const ActorSystem) usize {
        return self.list.drawn;
    }

    /// Actors the last `draw` skipped as off camera.
    pub fn lastCulled(self: *const ActorSystem) usize {
        return self.list.culled;
    }
};

/// Draws every entity's `Sprite` and `Actor` in one pass, sorted together
/// by `ZOrder` and culled to the camera, so a z 2 sprite lands on a z 1
/// actor. Drawing only; animate actors with `ActorSystem.update`.
pub const DrawSystem = struct {
    world: *flecs.world_t,
    spriteQuery: *flecs.query_t,
    actorQuery: *flecs.query_t,
    list: DrawList,

    /// Registers the engine components if needed and builds the queries.
    /// `alloc` backs the per-frame sort list.
    pub fn init(alloc: std.mem.Allocator, world: *flecs.world_t) !DrawSystem {
        registerEngineComponents(world);
        const spriteQuery = try drawQuery(world, Sprite);
        errdefer flecs.query_fini(spriteQuery);
        return .{
            .world = world,
            .spriteQuery = spriteQuery,
            .actorQuery = try drawQuery(world, Actor),
            .list = .{ .alloc = alloc },
        };
    }

    pub fn deinit(self: *DrawSystem) void {
        flecs.query_fini(self.spriteQuery);
        flecs.query_fini(self.actorQuery);
        self.list.deinit();
    }

    /// Draws every sprite and actor frame through `renderer`, lowest
    /// `ZOrder` first. Inside a `.camera` pass, anything outside
    /// `renderer.viewRect()` is skipped.
    pub fn draw(self: *DrawSystem, renderer: anytype) void {
        const view = renderer.viewRect();
        self.list.reset();
        self.list.gather(Sprite, self.world, self.spriteQuery, view, renderer);
        self.list.gather(Actor, self.world, self.actorQuery, view, renderer);
        self.list.submit(renderer);
    }

    /// Sprites and actors drawn by the last `draw`.
    pub fn lastDrawn(self: *const DrawSystem) usize {
        return self.list.drawn;
    }

    /// Sprites and actors the last `draw` skipped as off camera.
    pub fn lastCulled(self: *const DrawSystem) usize {
        return self.list.culled;
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
