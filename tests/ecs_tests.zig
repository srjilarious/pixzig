const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const ecs = pixzig.ecs;
const flecs = pixzig.flecs;
const Sprite = pixzig.sprites.Sprite;
const Actor = pixzig.sprites.Actor;
const RectF = pixzig.RectF;
const Color = pixzig.Color;
const Camera2D = pixzig.Camera2D;
const ScriptEngine = pixzig.scripting.ScriptEngine;

const Velocity = struct { x: f32 };
const Frozen = struct {};

// Never rendered: the helpers only hand sprites to the renderer.
var g_fakeHandle: pixzig.resources.TextureHandle = .{
    .val = .{
        .texture = 0,
        .size = .{ .x = 16, .y = 16 },
        .src = .{ .l = 0, .t = 0, .r = 1, .b = 1 },
    },
};

fn makeSprite(x: f32, y: f32) Sprite {
    var spr = Sprite.create(&g_fakeHandle);
    spr.setPosF(x, y);
    return spr;
}

/// Records what the helpers draw, in place of an engine Renderer.
const MockRenderer = struct {
    sprites: usize = 0,
    rects: [8]RectF = undefined,
    numRects: usize = 0,

    pub fn drawSprite(self: *MockRenderer, _: *const Sprite) void {
        self.sprites += 1;
    }

    pub fn drawEnclosingRect(self: *MockRenderer, dest: RectF, _: Color, _: u8) void {
        self.rects[self.numRects] = dest;
        self.numRects += 1;
    }
};

fn countMatches(world: *flecs.world_t, q: *flecs.query_t) usize {
    var n: usize = 0;
    var it = flecs.query_iter(world, q);
    while (flecs.query_next(&it)) n += it.count();
    return n;
}

pub fn ecsQueryMatchesAllTermsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const world = flecs.init();
    defer _ = flecs.fini(world);
    ecs.registerEngineComponents(world);
    ecs.registerComponents(world, .{ Velocity, Frozen });

    const a = flecs.new_id(world);
    flecs.set(world, a, Sprite, makeSprite(0, 0));
    flecs.set(world, a, Velocity, .{ .x = 1 });
    const b = flecs.new_id(world);
    flecs.set(world, b, Sprite, makeSprite(0, 0));
    const c = flecs.new_id(world);
    flecs.set(world, c, Sprite, makeSprite(0, 0));
    flecs.set(world, c, Velocity, .{ .x = 2 });
    flecs.add(world, c, Frozen);

    const both = try ecs.query(world, .{ Sprite, Velocity });
    defer flecs.query_fini(both);
    try testz.expectEqual(countMatches(world, both), 2);

    // A raw term mixes with plain types.
    const moving = try ecs.query(world, .{ Sprite, Velocity, flecs.term_t{ .id = flecs.id(Frozen), .oper = .Not } });
    defer flecs.query_fini(moving);
    try testz.expectEqual(countMatches(world, moving), 1);
}

pub fn ecsSpriteAndActorSystemsDrawTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = flecs.init();
    defer _ = flecs.fini(world);

    var sprites = try ecs.SpriteSystem.init(world);
    defer sprites.deinit();
    var actors = try ecs.ActorSystem.init(world);
    defer actors.deinit();

    for (0..3) |_| flecs.set(world, flecs.new_id(world), Sprite, makeSprite(0, 0));
    const actorEnt = flecs.new_id(world);
    flecs.set(world, actorEnt, Actor, Actor.init(alloc, makeSprite(0, 0)));
    defer if (flecs.get_mut(world, actorEnt, Actor)) |a| a.states.deinit();

    var r = MockRenderer{};
    sprites.draw(&r);
    try testz.expectEqual(r.sprites, 3);

    // An actor with no state yet updates without complaint.
    actors.update(16.0);
    actors.draw(&r);
    try testz.expectEqual(r.sprites, 4);
}

pub fn ecsDebugOutlinesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const world = flecs.init();
    defer _ = flecs.fini(world);

    var outlines = try ecs.DebugOutlines.init(world);
    defer outlines.deinit();

    const red: ecs.Outline = .{ .color = Color.red };
    const s = flecs.new_id(world);
    flecs.set(world, s, Sprite, makeSprite(10, 20));
    flecs.set(world, s, ecs.Outline, red);
    // No outline component: not drawn.
    flecs.set(world, flecs.new_id(world), Sprite, makeSprite(0, 0));
    const a = flecs.new_id(world);
    flecs.set(world, a, Actor, Actor.init(alloc, makeSprite(50, 60)));
    flecs.set(world, a, ecs.Outline, red);
    defer if (flecs.get_mut(world, a, Actor)) |act| act.states.deinit();

    var r = MockRenderer{};
    outlines.draw(&r);
    try testz.expectEqual(r.numRects, 0); // starts disabled

    // The console binding toggles it.
    var scripts = try ScriptEngine.init(alloc);
    defer scripts.deinit();
    try outlines.bindConsole(&scripts, "toggleOutlines");
    try scripts.run("toggleOutlines()");
    try testz.expectTrue(outlines.enabled);

    outlines.draw(&r);
    try testz.expectEqual(r.numRects, 2);
    try testz.expectEqual(r.rects[0].l, 10);
    try testz.expectEqual(r.rects[1].t, 60);
}

pub fn ecsFollowEntityTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;
    const world = flecs.init();
    defer _ = flecs.fini(world);
    ecs.registerEngineComponents(world);

    const e = flecs.new_id(world);
    flecs.set(world, e, Sprite, makeSprite(100, 200));
    const center = ecs.spriteCenter(world, e).?;
    try testz.expectEqual(center.x, 108);
    try testz.expectEqual(center.y, 208);

    var cam = Camera2D.init();
    ecs.followEntity(&cam, world, e, 16.0, .{});
    try testz.expectEqual(cam.pos.x, 108);
    try testz.expectEqual(cam.pos.y, 208);

    // An entity with nothing to follow leaves the camera where it is.
    const empty = flecs.new_id(world);
    try testz.expectTrue(ecs.spriteCenter(world, empty) == null);
    ecs.followEntity(&cam, world, empty, 16.0, .{});
    try testz.expectEqual(cam.pos.x, 108);
}
