//! Flat C ABI surface for pixzig, built as `libpixzig_ffi` (see the
//! `python-ffi` build step). Freezes a single, non-generic
//! `PixzigEngineOptions` instantiation so the engine's comptime-generic
//! API can be called from a C ABI. Python (or any other C-caller) owns the
//! game loop and drives it by calling the frame-stepping functions below in
//! sequence; nothing here calls back into the caller.
const std = @import("std");
const pixzig = @import("pixzig");

const FfiOpts = pixzig.PixzigEngineOptions{
    .inputOpts = .{ .mouse = true, .numGamepads = pixzig.input.MaxGamepads, .textInput = true },
    .rendererOpts = .{ .textRendering = true },
    .audioOpts = .{ .enabled = true },
};
const Engine = pixzig.PixzigEngine(FfiOpts);

const Flip = pixzig.sprites.Flip;
const Rotate = pixzig.common.Rotate;

/// Maps a Python-side integer to the `Flip` enum: 0=none, 1=horz, 2=vert, 3=both.
fn flipFromInt(v: c_int) Flip {
    return switch (v) {
        1 => .horz,
        2 => .vert,
        3 => .both,
        else => .none,
    };
}

/// Maps a Python-side integer to the `Rotate` enum, matching its
/// declaration order: 0=none, 1=rot90, 2=rot180, 3=rot270, 4=flipHorz, 5=flipVert.
fn rotateFromInt(v: c_int) Rotate {
    return switch (v) {
        1 => .rot90,
        2 => .rot180,
        3 => .rot270,
        4 => .flipHorz,
        5 => .flipVert,
        else => .none,
    };
}

const PzSprite = struct {
    eng: *PzEngine,
    sprite: pixzig.sprites.Sprite,
    /// The sprite's size at creation (full texture frame), kept so
    /// `pz_sprite_set_scale` has a stable reference to scale from.
    base_size: pixzig.Vec2F,
    /// Colour multiplier applied by `pz_sprite_draw`. Null means "untinted",
    /// which routes to the faster plain sprite batch.
    tint: ?pixzig.Color,
    registry_index: usize,
};

const PzActor = struct {
    eng: *PzEngine,
    actor: pixzig.sprites.Actor,
    registry_index: usize,
};

const PzCamera = struct {
    eng: *PzEngine,
    camera: pixzig.Camera2D,
    registry_index: usize,
};

const PzTilemapRenderer = struct {
    eng: *PzEngine,
    map: *pixzig.TileMapHandle,
    renderer: pixzig.tile.ChunkedTiledRenderer,
    registry_index: usize,
};

const PzAssetManifest = struct {
    eng: *PzEngine,
    manifest: pixzig.AssetManifest,
    registry_index: usize,
};

// ---------------------------------------------------------------------------
// Action mapping. `pixzig.input.ActionMap(Action, Axes)` is comptime-generic
// over user-defined enums, which Python can't supply. Instead, freeze one
// instantiation over synthetic fixed-capacity "slot" enums (mirroring the
// single frozen `Engine` instantiation above); Python assigns each named
// action/axis a slot integer and the two never leave the Python wrapper.
// ---------------------------------------------------------------------------

const MaxFfiActions = 64;
const MaxFfiAxes = 32;

fn SlotEnum(comptime count: usize) type {
    @setEvalBranchQuota(count * 2000);
    var names: [count][]const u8 = undefined;
    for (0..count) |i| {
        names[i] = std.fmt.comptimePrint("slot_{d}", .{i});
    }
    const IntTag = std.math.IntFittingRange(0, count - 1);
    return @Enum(IntTag, .exhaustive, &names, &std.simd.iota(IntTag, count));
}

const FfiAction = SlotEnum(MaxFfiActions);
const FfiAxis = SlotEnum(MaxFfiAxes);
const FfiActionMap = pixzig.input.ActionMap(FfiAction, FfiAxis);

fn ffiAction(slot: i32) ?FfiAction {
    if (slot < 0 or slot >= MaxFfiActions) return null;
    return @enumFromInt(@as(std.meta.Tag(FfiAction), @intCast(slot)));
}

fn ffiAxis(slot: i32) ?FfiAxis {
    if (slot < 0 or slot >= MaxFfiAxes) return null;
    return @enumFromInt(@as(std.meta.Tag(FfiAxis), @intCast(slot)));
}

const PzActionMap = struct {
    eng: *PzEngine,
    map: *FfiActionMap,
    registry_index: usize,
};

/// Appends `wrapper` to `list` and records its index for O(1) removal later.
fn registryAdd(comptime T: type, list: *std.ArrayList(*T), alloc: std.mem.Allocator, wrapper: *T) !void {
    wrapper.registry_index = list.items.len;
    try list.append(alloc, wrapper);
}

/// Swap-removes `wrapper` from `list` in O(1), fixing up the moved entry's
/// stored index.
fn registryRemove(comptime T: type, list: *std.ArrayList(*T), wrapper: *T) void {
    _ = list.swapRemove(wrapper.registry_index);
    if (wrapper.registry_index < list.items.len) {
        list.items[wrapper.registry_index].registry_index = wrapper.registry_index;
    }
}

const PzEngine = struct {
    engine: *Engine,
    alloc: std.mem.Allocator,
    sprites: std.ArrayList(*PzSprite),
    cameras: std.ArrayList(*PzCamera),
    tilemap_renderers: std.ArrayList(*PzTilemapRenderer),
    manifests: std.ArrayList(*PzAssetManifest),
    action_maps: std.ArrayList(*PzActionMap),
    actors: std.ArrayList(*PzActor),
    /// Shared frame-sequence/actor-state store, created on the first
    /// `pz_anim_*` call. Referenced by every `Actor`'s states, so it is torn
    /// down only after all actors in `pz_deinit`.
    anim: ?pixzig.sprites.FrameSequenceManager,
};

/// Returns the engine's shared `FrameSequenceManager`, creating it on first use.
fn animMgr(eng: *PzEngine) !*pixzig.sprites.FrameSequenceManager {
    if (eng.anim == null) {
        eng.anim = try pixzig.sprites.FrameSequenceManager.init(eng.alloc);
    }
    return &eng.anim.?;
}

var g_last_error_buf: [256]u8 = undefined;
var g_last_error_len: usize = 0;

fn setLastErrorMsg(msg: []const u8) void {
    const n = @min(msg.len, g_last_error_buf.len - 1);
    @memcpy(g_last_error_buf[0..n], msg[0..n]);
    g_last_error_buf[n] = 0;
    g_last_error_len = n;
}

fn setLastErrorErr(err: anyerror) void {
    setLastErrorMsg(@errorName(err));
}

export fn pz_last_error() callconv(.c) [*:0]const u8 {
    return @ptrCast(&g_last_error_buf);
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

export fn pz_init(title: [*:0]const u8, width: i32, height: i32) callconv(.c) ?*PzEngine {
    const alloc = std.heap.c_allocator;

    const pz = alloc.create(PzEngine) catch |err| {
        setLastErrorErr(err);
        return null;
    };

    const engine = Engine.init(std.mem.span(title), alloc, .{
        .windowSize = .{ .x = width, .y = height },
    }) catch |err| {
        setLastErrorErr(err);
        alloc.destroy(pz);
        return null;
    };

    pz.* = .{
        .engine = engine,
        .alloc = alloc,
        .sprites = .empty,
        .cameras = .empty,
        .tilemap_renderers = .empty,
        .manifests = .empty,
        .action_maps = .empty,
        .actors = .empty,
        .anim = null,
    };
    return pz;
}

export fn pz_deinit(eng: *PzEngine) callconv(.c) void {
    for (eng.sprites.items) |spr| {
        spr.sprite.deinit();
        eng.alloc.destroy(spr);
    }
    eng.sprites.deinit(eng.alloc);

    for (eng.cameras.items) |cam| {
        eng.alloc.destroy(cam);
    }
    eng.cameras.deinit(eng.alloc);

    for (eng.tilemap_renderers.items) |tr| {
        tr.renderer.deinit();
        tr.map.release();
        eng.alloc.destroy(tr);
    }
    eng.tilemap_renderers.deinit(eng.alloc);

    for (eng.manifests.items) |m| {
        m.manifest.deinit();
        eng.alloc.destroy(m);
    }
    eng.manifests.deinit(eng.alloc);

    for (eng.action_maps.items) |am| {
        am.map.deinit();
        eng.alloc.destroy(am);
    }
    eng.action_maps.deinit(eng.alloc);

    // Actors first: their states reference sequences owned by `anim`.
    for (eng.actors.items) |ac| {
        ac.actor.deinit();
        eng.alloc.destroy(ac);
    }
    eng.actors.deinit(eng.alloc);
    if (eng.anim) |*m| m.deinit();

    eng.engine.deinit();
    eng.alloc.destroy(eng);
}

// ---------------------------------------------------------------------------
// Frame stepping. Mirrors PixzigAppRunner.gameLoopCore, split into calls the
// caller's own loop invokes directly instead of one fixed-timestep Zig loop.
// ---------------------------------------------------------------------------

export fn pz_should_close(eng: *PzEngine) callconv(.c) bool {
    return eng.engine.window.shouldClose();
}

export fn pz_poll_events(eng: *PzEngine) callconv(.c) void {
    eng.engine.pollEvents();
    eng.engine.refreshWindowState();
}

export fn pz_update_input(eng: *PzEngine) callconv(.c) void {
    eng.engine.inputs.update(eng.engine.window_state.scale_factor, &eng.engine.viewport);
    eng.engine.resources.checkHotReload();
}

/// Closes an input tick, rolling the current key/button state into the
/// previous one. Must be called after the caller's update ran, or
/// `pz_key_pressed` would keep reporting the same press forever.
export fn pz_finish_tick(eng: *PzEngine) callconv(.c) void {
    eng.engine.inputs.finishTick();
}

export fn pz_swap_buffers(eng: *PzEngine) callconv(.c) void {
    eng.engine.window.swapBuffers();
}

export fn pz_render_begin(eng: *PzEngine) callconv(.c) void {
    eng.engine.renderer.begin(eng.engine.uiMatrix());
}

/// Like pz_render_begin, but begins a world-space pass using the given
/// camera's matrix instead of screen-space UI coordinates. Use this to draw
/// sprites/shapes interleaved with tilemap layers (see pz_tilemap_render_*).
export fn pz_render_begin_world(eng: *PzEngine, cam: *PzCamera) callconv(.c) void {
    eng.engine.renderer.begin(cam.camera.matrix(&eng.engine.viewport));
}

export fn pz_render_clear(eng: *PzEngine, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    eng.engine.renderer.clear(r, g, b, a);
}

export fn pz_render_end(eng: *PzEngine) callconv(.c) void {
    eng.engine.renderer.end();
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

export fn pz_key_down(eng: *PzEngine, key: c_int) callconv(.c) bool {
    return eng.engine.inputs.keyboard.down(@enumFromInt(key));
}

export fn pz_key_pressed(eng: *PzEngine, key: c_int) callconv(.c) bool {
    return eng.engine.inputs.keyboard.pressed(@enumFromInt(key));
}

export fn pz_key_released(eng: *PzEngine, key: c_int) callconv(.c) bool {
    return eng.engine.inputs.keyboard.released(@enumFromInt(key));
}

export fn pz_mouse_pos(eng: *PzEngine, out_x: *f32, out_y: *f32) callconv(.c) void {
    const p = eng.engine.inputs.mouse.pos();
    out_x.* = p.x;
    out_y.* = p.y;
}

export fn pz_mouse_button_down(eng: *PzEngine, btn: c_int) callconv(.c) bool {
    return eng.engine.inputs.mouse.down(@enumFromInt(btn));
}

export fn pz_mouse_button_pressed(eng: *PzEngine, btn: c_int) callconv(.c) bool {
    return eng.engine.inputs.mouse.pressed(@enumFromInt(btn));
}

export fn pz_mouse_button_released(eng: *PzEngine, btn: c_int) callconv(.c) bool {
    return eng.engine.inputs.mouse.released(@enumFromInt(btn));
}

export fn pz_gamepad_connected(eng: *PzEngine, idx: c_int) callconv(.c) bool {
    if (idx < 0 or idx >= pixzig.input.MaxGamepads) return false;
    return eng.engine.inputs.gamepad(@intCast(idx)).isConnected();
}

export fn pz_gamepad_button_down(eng: *PzEngine, idx: c_int, btn: c_int) callconv(.c) bool {
    if (idx < 0 or idx >= pixzig.input.MaxGamepads) return false;
    return eng.engine.inputs.gamepad(@intCast(idx)).down(@enumFromInt(@as(u8, @intCast(btn))));
}

export fn pz_gamepad_button_pressed(eng: *PzEngine, idx: c_int, btn: c_int) callconv(.c) bool {
    if (idx < 0 or idx >= pixzig.input.MaxGamepads) return false;
    return eng.engine.inputs.gamepad(@intCast(idx)).pressed(@enumFromInt(@as(u8, @intCast(btn))));
}

export fn pz_gamepad_button_released(eng: *PzEngine, idx: c_int, btn: c_int) callconv(.c) bool {
    if (idx < 0 or idx >= pixzig.input.MaxGamepads) return false;
    return eng.engine.inputs.gamepad(@intCast(idx)).released(@enumFromInt(@as(u8, @intCast(btn))));
}

export fn pz_gamepad_axis(eng: *PzEngine, idx: c_int, axis: c_int) callconv(.c) f32 {
    if (idx < 0 or idx >= pixzig.input.MaxGamepads) return 0;
    return eng.engine.inputs.gamepad(@intCast(idx)).axis(@enumFromInt(@as(u8, @intCast(axis))));
}

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

export fn pz_load_texture(eng: *PzEngine, name: [*:0]const u8, path: [*:0]const u8) callconv(.c) i32 {
    _ = eng.engine.resources.loadTexture(std.mem.span(name), std.mem.span(path)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_texture_sub(eng: *PzEngine, base_name: [*:0]const u8, new_name: [*:0]const u8, x: i32, y: i32, w: i32, h: i32) callconv(.c) i32 {
    const managed = eng.engine.resources.getTexture(std.mem.span(base_name)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    const current = managed.get() orelse {
        setLastErrorMsg("texture not loaded");
        return -1;
    };
    const coords = pixzig.RectF.fromCoords(x, y, w, h, @intCast(current.val.size.x), @intCast(current.val.size.y));
    _ = eng.engine.resources.addSubTexture(managed, std.mem.span(new_name), coords) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_load_font(eng: *PzEngine, name: [*:0]const u8, ttf_path: [*:0]const u8, size: f32) callconv(.c) i32 {
    eng.engine.resources.loadFontFromTtfFile(std.mem.span(name), std.mem.span(ttf_path), size) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_set_default_font(eng: *PzEngine, name: [*:0]const u8) callconv(.c) i32 {
    eng.engine.renderer.setDefaultFont(&eng.engine.resources, std.mem.span(name)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

// ---------------------------------------------------------------------------
// Sprites. Sprites are opaque handles (*PzSprite); valid from pz_sprite_create
// until pz_sprite_destroy.
// ---------------------------------------------------------------------------

fn pzSpriteCreateImpl(eng: *PzEngine, texture_name: []const u8) !*PzSprite {
    const handle = try eng.engine.resources.acquireTexture(texture_name);
    const size = pixzig.Vec2F{
        .x = @floatFromInt(handle.val.size.x),
        .y = @floatFromInt(handle.val.size.y),
    };
    var sprite = pixzig.sprites.Sprite.create(handle, size);
    errdefer sprite.deinit();

    const wrapper = try eng.alloc.create(PzSprite);
    errdefer eng.alloc.destroy(wrapper);

    wrapper.* = .{
        .eng = eng,
        .sprite = sprite,
        .base_size = size,
        .tint = null,
        .registry_index = undefined,
    };
    try registryAdd(PzSprite, &eng.sprites, eng.alloc, wrapper);
    return wrapper;
}

export fn pz_sprite_create(eng: *PzEngine, texture_name: [*:0]const u8) callconv(.c) ?*PzSprite {
    return pzSpriteCreateImpl(eng, std.mem.span(texture_name)) catch |err| {
        setLastErrorErr(err);
        return null;
    };
}

export fn pz_sprite_set_pos(spr: *PzSprite, x: i32, y: i32) callconv(.c) void {
    spr.sprite.setPos(x, y);
}

/// Resizes the sprite's on-screen rectangle, keeping its top-left corner.
export fn pz_sprite_set_size(spr: *PzSprite, w: f32, h: f32) callconv(.c) void {
    spr.sprite.size = .{ .x = w, .y = h };
    spr.sprite.dest = .{
        .l = spr.sprite.dest.l,
        .t = spr.sprite.dest.t,
        .r = spr.sprite.dest.l + w,
        .b = spr.sprite.dest.t + h,
    };
}

/// Scales the sprite relative to its creation size (the full texture frame),
/// keeping its top-left corner. `sx`/`sy` of 1.0 restores the original size.
export fn pz_sprite_set_scale(spr: *PzSprite, sx: f32, sy: f32) callconv(.c) void {
    pz_sprite_set_size(spr, spr.base_size.x * sx, spr.base_size.y * sy);
}

/// Sets a 90-degree rotation / flip for the sprite. `rot`: 0=none, 1=rot90,
/// 2=rot180, 3=rot270, 4=flipHorz, 5=flipVert.
export fn pz_sprite_set_rotate(spr: *PzSprite, rot: c_int) callconv(.c) void {
    spr.sprite.rotate = rotateFromInt(rot);
}

/// Sets the sub-region of the sprite's texture to draw, in texture pixels.
export fn pz_sprite_set_src_rect(spr: *PzSprite, x: i32, y: i32, w: i32, h: i32) callconv(.c) void {
    const tex_sz = spr.sprite.texture.val.size;
    spr.sprite.src_coords = pixzig.RectF.fromCoords(x, y, w, h, @intCast(tex_sz.x), @intCast(tex_sz.y));
}

/// Sets a per-sprite colour multiplier used by `pz_sprite_draw`. (1,1,1,1)
/// clears the tint and restores the plain (faster) draw path.
export fn pz_sprite_set_tint(spr: *PzSprite, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    if (r == 1 and g == 1 and b == 1 and a == 1) {
        spr.tint = null;
    } else {
        spr.tint = .{ .r = r, .g = g, .b = b, .a = a };
    }
}

export fn pz_sprite_get_size(spr: *PzSprite, out_w: *f32, out_h: *f32) callconv(.c) void {
    out_w.* = spr.sprite.size.x;
    out_h.* = spr.sprite.size.y;
}

export fn pz_sprite_get_rect(spr: *PzSprite, out_x: *f32, out_y: *f32, out_w: *f32, out_h: *f32) callconv(.c) void {
    out_x.* = spr.sprite.dest.l;
    out_y.* = spr.sprite.dest.t;
    out_w.* = spr.sprite.dest.width();
    out_h.* = spr.sprite.dest.height();
}

export fn pz_sprite_draw(spr: *PzSprite) callconv(.c) void {
    if (spr.tint) |c| {
        spr.eng.engine.renderer.drawSpriteColored(&spr.sprite, c);
    } else {
        spr.eng.engine.renderer.drawSprite(&spr.sprite);
    }
}

export fn pz_sprite_destroy(spr: *PzSprite) callconv(.c) void {
    spr.sprite.deinit();
    registryRemove(PzSprite, &spr.eng.sprites, spr);
    spr.eng.alloc.destroy(spr);
}

// ---------------------------------------------------------------------------
// Camera. Cameras are opaque handles (*PzCamera); valid from pz_camera_create
// until pz_camera_destroy. Used with pz_render_begin_world and the
// pz_tilemap_render_* functions.
// ---------------------------------------------------------------------------

export fn pz_camera_create(eng: *PzEngine) callconv(.c) ?*PzCamera {
    const wrapper = eng.alloc.create(PzCamera) catch |err| {
        setLastErrorErr(err);
        return null;
    };
    wrapper.* = .{
        .eng = eng,
        .camera = pixzig.Camera2D.init(eng.engine.viewport.logical_size),
        .registry_index = undefined,
    };
    registryAdd(PzCamera, &eng.cameras, eng.alloc, wrapper) catch |err| {
        eng.alloc.destroy(wrapper);
        setLastErrorErr(err);
        return null;
    };
    return wrapper;
}

export fn pz_camera_destroy(cam: *PzCamera) callconv(.c) void {
    registryRemove(PzCamera, &cam.eng.cameras, cam);
    cam.eng.alloc.destroy(cam);
}

export fn pz_camera_set_pos(cam: *PzCamera, x: f32, y: f32) callconv(.c) void {
    cam.camera.pos = .{ .x = x, .y = y };
}

export fn pz_camera_get_pos(cam: *PzCamera, out_x: *f32, out_y: *f32) callconv(.c) void {
    out_x.* = cam.camera.pos.x;
    out_y.* = cam.camera.pos.y;
}

export fn pz_camera_set_zoom(cam: *PzCamera, zoom: f32) callconv(.c) void {
    cam.camera.zoom = zoom;
}

export fn pz_camera_get_zoom(cam: *PzCamera) callconv(.c) f32 {
    return cam.camera.zoom;
}

export fn pz_camera_set_bounds(cam: *PzCamera, l: f32, t: f32, r: f32, b: f32) callconv(.c) void {
    cam.camera.bounds = .{ .l = l, .t = t, .r = r, .b = b };
}

export fn pz_camera_clear_bounds(cam: *PzCamera) callconv(.c) void {
    cam.camera.bounds = null;
}

// ---------------------------------------------------------------------------
// Tilemap loading + chunked rendering. Renderers are opaque handles
// (*PzTilemapRenderer); valid from pz_tilemap_renderer_create until
// pz_tilemap_renderer_destroy.
// ---------------------------------------------------------------------------

export fn pz_load_tilemap(eng: *PzEngine, name: [*:0]const u8, path: [*:0]const u8) callconv(.c) i32 {
    eng.engine.resources.loadTileMap(std.mem.span(name), std.mem.span(path)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

fn pzTilemapRendererCreateImpl(eng: *PzEngine, map_name: []const u8, texture_name: []const u8) !*PzTilemapRenderer {
    const map = try eng.engine.resources.acquireTileMap(map_name);
    errdefer map.release();

    const shader = try eng.engine.resources.getShader(pixzig.shaders.TextureShader);
    const texture = try eng.engine.resources.getTexture(texture_name);

    var renderer = try pixzig.tile.ChunkedTiledRenderer.init(eng.alloc, &map.val, shader, texture);
    errdefer renderer.deinit();

    const wrapper = try eng.alloc.create(PzTilemapRenderer);
    errdefer eng.alloc.destroy(wrapper);

    wrapper.* = .{ .eng = eng, .map = map, .renderer = renderer, .registry_index = undefined };
    try registryAdd(PzTilemapRenderer, &eng.tilemap_renderers, eng.alloc, wrapper);
    return wrapper;
}

export fn pz_tilemap_renderer_create(eng: *PzEngine, map_name: [*:0]const u8, texture_name: [*:0]const u8) callconv(.c) ?*PzTilemapRenderer {
    return pzTilemapRendererCreateImpl(eng, std.mem.span(map_name), std.mem.span(texture_name)) catch |err| {
        setLastErrorErr(err);
        return null;
    };
}

export fn pz_tilemap_renderer_destroy(tr: *PzTilemapRenderer) callconv(.c) void {
    tr.renderer.deinit();
    tr.map.release();
    registryRemove(PzTilemapRenderer, &tr.eng.tilemap_renderers, tr);
    tr.eng.alloc.destroy(tr);
}

export fn pz_tilemap_pixel_size(tr: *PzTilemapRenderer, layer_index: i32, out_w: *f32, out_h: *f32) callconv(.c) void {
    if (layer_index < 0 or @as(usize, @intCast(layer_index)) >= tr.map.val.layers.items.len) {
        setLastErrorMsg("invalid layer index");
        out_w.* = 0;
        out_h.* = 0;
        return;
    }
    const layer = &tr.map.val.layers.items[@intCast(layer_index)];
    out_w.* = @floatFromInt(layer.size.x * layer.tileSize.x);
    out_h.* = @floatFromInt(layer.size.y * layer.tileSize.y);
}

export fn pz_tilemap_render(tr: *PzTilemapRenderer, cam: *PzCamera) callconv(.c) void {
    tr.renderer.render(&tr.map.val, &cam.camera, &tr.eng.engine.viewport);
}

export fn pz_tilemap_render_below(tr: *PzTilemapRenderer, cam: *PzCamera, z: f32) callconv(.c) void {
    tr.renderer.renderLayersBelow(z, &tr.map.val, &cam.camera, &tr.eng.engine.viewport);
}

export fn pz_tilemap_render_above(tr: *PzTilemapRenderer, cam: *PzCamera, z: f32) callconv(.c) void {
    tr.renderer.renderLayersAbove(z, &tr.map.val, &cam.camera, &tr.eng.engine.viewport);
}

export fn pz_tilemap_check_reload(tr: *PzTilemapRenderer) callconv(.c) bool {
    if (!tr.map.dirty) return false;
    tr.map = tr.map.reacquire();
    tr.renderer.reload(&tr.map.val) catch |err| {
        setLastErrorErr(err);
        return false;
    };
    return true;
}

fn pzManifestLoadImpl(eng: *PzEngine, path: []const u8) !*PzAssetManifest {
    var manifest = try pixzig.AssetManifest.loadFromFile(eng.alloc, &eng.engine.resources, path);
    errdefer manifest.deinit();

    const wrapper = try eng.alloc.create(PzAssetManifest);
    errdefer eng.alloc.destroy(wrapper);

    wrapper.* = .{ .eng = eng, .manifest = manifest, .registry_index = undefined };
    try registryAdd(PzAssetManifest, &eng.manifests, eng.alloc, wrapper);
    return wrapper;
}

// ---------------------------------------------------------------------------
// Asset manifests. Manifests are opaque handles (*PzAssetManifest); valid
// from pz_manifest_load until pz_manifest_destroy. Assets loaded via
// pz_manifest_load_group are registered in the shared ResourceManager under
// their manifest id, so they're then usable directly by name with
// pz_sprite_create / pz_tilemap_renderer_create / pz_set_default_font -- no
// separate FFI surface needed to consume them.
// ---------------------------------------------------------------------------

export fn pz_manifest_load(eng: *PzEngine, path: [*:0]const u8) callconv(.c) ?*PzAssetManifest {
    return pzManifestLoadImpl(eng, std.mem.span(path)) catch |err| {
        setLastErrorErr(err);
        return null;
    };
}

export fn pz_manifest_load_group(m: *PzAssetManifest, group_name: [*:0]const u8) callconv(.c) i32 {
    m.manifest.loadGroup(std.mem.span(group_name)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_manifest_unload_group(m: *PzAssetManifest, group_name: [*:0]const u8) callconv(.c) void {
    m.manifest.unloadGroup(std.mem.span(group_name));
}

export fn pz_manifest_destroy(m: *PzAssetManifest) callconv(.c) void {
    m.manifest.deinit();
    registryRemove(PzAssetManifest, &m.eng.manifests, m);
    m.eng.alloc.destroy(m);
}

// ---------------------------------------------------------------------------
// Action maps. Maps are opaque handles (*PzActionMap); valid from
// pz_action_map_create until pz_action_map_destroy. `action`/`axis`
// parameters are slot indices in [0, MaxFfiActions)/[0, MaxFfiAxes) -- the
// Python wrapper owns the name -> slot bookkeeping, this layer only ever
// sees integers.
// ---------------------------------------------------------------------------

fn pzActionMapCreateImpl(eng: *PzEngine) !*PzActionMap {
    const map = try FfiActionMap.init(eng.alloc);
    errdefer map.deinit();

    const wrapper = try eng.alloc.create(PzActionMap);
    errdefer eng.alloc.destroy(wrapper);

    wrapper.* = .{ .eng = eng, .map = map, .registry_index = undefined };
    try registryAdd(PzActionMap, &eng.action_maps, eng.alloc, wrapper);
    return wrapper;
}

export fn pz_action_map_create(eng: *PzEngine) callconv(.c) ?*PzActionMap {
    return pzActionMapCreateImpl(eng) catch |err| {
        setLastErrorErr(err);
        return null;
    };
}

export fn pz_action_map_destroy(am: *PzActionMap) callconv(.c) void {
    am.map.deinit();
    registryRemove(PzActionMap, &am.eng.action_maps, am);
    am.eng.alloc.destroy(am);
}

export fn pz_action_map_update(am: *PzActionMap, elapsed_us: f64) callconv(.c) void {
    _ = am.map.update(&am.eng.engine.inputs, elapsed_us);
}

export fn pz_action_bind_key(am: *PzActionMap, action_slot: i32, key: c_int) callconv(.c) i32 {
    const act = ffiAction(action_slot) orelse {
        setLastErrorMsg("invalid action slot");
        return -1;
    };
    am.map.bind(act, .{ .key = @enumFromInt(key) }) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_action_bind_mouse_button(am: *PzActionMap, action_slot: i32, button: c_int) callconv(.c) i32 {
    const act = ffiAction(action_slot) orelse {
        setLastErrorMsg("invalid action slot");
        return -1;
    };
    am.map.bind(act, .{ .mouse_button = @enumFromInt(button) }) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_action_bind_gamepad_button(am: *PzActionMap, action_slot: i32, button: c_int) callconv(.c) i32 {
    const act = ffiAction(action_slot) orelse {
        setLastErrorMsg("invalid action slot");
        return -1;
    };
    am.map.bind(act, .{ .gamepad_button = @enumFromInt(@as(u8, @intCast(button))) }) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_action_bind_axis_buttons(am: *PzActionMap, axis_slot: i32, neg_key: c_int, pos_key: c_int) callconv(.c) i32 {
    const ax = ffiAxis(axis_slot) orelse {
        setLastErrorMsg("invalid axis slot");
        return -1;
    };
    am.map.bindAxis(ax, .{ .buttons = .{
        .negative = .{ .key = @enumFromInt(neg_key) },
        .positive = .{ .key = @enumFromInt(pos_key) },
    } }) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_action_bind_axis_gamepad(am: *PzActionMap, axis_slot: i32, gamepad_axis: c_int, deadzone: f32) callconv(.c) i32 {
    const ax = ffiAxis(axis_slot) orelse {
        setLastErrorMsg("invalid axis slot");
        return -1;
    };
    am.map.bindAxis(ax, .{ .gamepad_axis = .{
        .axis = @enumFromInt(@as(u8, @intCast(gamepad_axis))),
        .deadzone = deadzone,
    } }) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_action_bind_axis_mouse(am: *PzActionMap, axis_slot: i32, mouse_axis: c_int, sensitivity: f32, clamp: f32) callconv(.c) i32 {
    const ax = ffiAxis(axis_slot) orelse {
        setLastErrorMsg("invalid axis slot");
        return -1;
    };
    const ma: pixzig.input.action.MouseAxis = if (mouse_axis == 0) .x else .y;
    am.map.bindAxis(ax, .{ .mouse_axis = .{
        .axis = ma,
        .sensitivity = sensitivity,
        .clamp = clamp,
    } }) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_action_up(am: *PzActionMap, action_slot: i32) callconv(.c) bool {
    const act = ffiAction(action_slot) orelse return true;
    return am.map.up(act);
}

export fn pz_action_down(am: *PzActionMap, action_slot: i32) callconv(.c) bool {
    const act = ffiAction(action_slot) orelse return false;
    return am.map.down(act);
}

export fn pz_action_pressed(am: *PzActionMap, action_slot: i32) callconv(.c) bool {
    const act = ffiAction(action_slot) orelse return false;
    return am.map.pressed(act);
}

export fn pz_action_released(am: *PzActionMap, action_slot: i32) callconv(.c) bool {
    const act = ffiAction(action_slot) orelse return false;
    return am.map.released(act);
}

export fn pz_action_axis(am: *PzActionMap, axis_slot: i32) callconv(.c) f32 {
    const ax = ffiAxis(axis_slot) orelse return 0;
    return am.map.axis(ax);
}

// ---------------------------------------------------------------------------
// Shapes and text
// ---------------------------------------------------------------------------

export fn pz_draw_filled_rect(eng: *PzEngine, x: f32, y: f32, w: f32, h: f32, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    const dest = pixzig.RectF{ .l = x, .t = y, .r = x + w, .b = y + h };
    eng.engine.renderer.drawFilledRect(dest, .{ .r = r, .g = g, .b = b, .a = a });
}

export fn pz_draw_rect(eng: *PzEngine, x: f32, y: f32, w: f32, h: f32, r: f32, g: f32, b: f32, a: f32, line_width: u8) callconv(.c) void {
    const dest = pixzig.RectF{ .l = x, .t = y, .r = x + w, .b = y + h };
    eng.engine.renderer.drawRect(dest, .{ .r = r, .g = g, .b = b, .a = a }, line_width);
}

export fn pz_draw_string(eng: *PzEngine, text: [*:0]const u8, x: i32, y: i32) callconv(.c) void {
    _ = eng.engine.renderer.drawString(std.mem.span(text), .{ .x = x, .y = y });
}

// ---------------------------------------------------------------------------
// Audio. Sounds are named and loaded from a file once, then played by name.
// The audio engine is always initialised for the FFI build.
// ---------------------------------------------------------------------------

export fn pz_audio_load(eng: *PzEngine, name: [*:0]const u8, path: [*:0]const u8) callconv(.c) i32 {
    eng.engine.audio.loadSound(std.mem.span(name), std.mem.span(path)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

/// Plays a previously loaded sound. Overlapping plays of the same name spin
/// up extra voices up to the engine's concurrent-sound cap.
export fn pz_audio_play(eng: *PzEngine, name: [*:0]const u8) callconv(.c) i32 {
    eng.engine.audio.playSound(std.mem.span(name)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

// ---------------------------------------------------------------------------
// Sprite animation. The engine owns one shared FrameSequenceManager (created
// lazily). Frame textures must already be loaded (pz_load_texture / an atlas
// / a manifest) under the names the sequences reference. Actors are opaque
// handles (*PzActor); valid from pz_actor_create until pz_actor_destroy.
// ---------------------------------------------------------------------------

/// Loads a JSON frame-sequence + actor-state file into the shared manager.
/// `path` should be absolute (or relative to the process cwd).
export fn pz_anim_load_file(eng: *PzEngine, path: [*:0]const u8) callconv(.c) i32 {
    const mgr = animMgr(eng) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    mgr.loadSequenceFile(std.mem.span(path), &eng.engine.resources) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

/// Creates an empty frame sequence in the shared manager. `loop` false makes
/// it a play-once sequence. Add frames with pz_anim_seq_add_frame.
export fn pz_anim_new_sequence(eng: *PzEngine, seq_name: [*:0]const u8, loop: bool) callconv(.c) i32 {
    const mgr = animMgr(eng) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    var seq = pixzig.sprites.FrameSequence.initEmpty(mgr.alloc) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    seq.mode = if (loop) .loop else .once;
    seq.ownsHandles = true;
    mgr.addSeq(std.mem.span(seq_name), seq) catch |err| {
        seq.deinit();
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

/// Appends a frame (a loaded texture shown for `frame_ms`) to a sequence made
/// by pz_anim_new_sequence. `flip`: 0=none, 1=horz, 2=vert, 3=both.
export fn pz_anim_seq_add_frame(eng: *PzEngine, seq_name: [*:0]const u8, texture_name: [*:0]const u8, frame_ms: f64, flip: c_int) callconv(.c) i32 {
    const mgr = animMgr(eng) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    const seq = mgr.sequences.get(std.mem.span(seq_name)) orelse {
        setLastErrorMsg("no sequence with that name");
        return -1;
    };
    const tex = eng.engine.resources.acquireTexture(std.mem.span(texture_name)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    seq.frames.append(mgr.alloc, .{ .tex = tex, .frameTimeMs = frame_ms, .flip = flipFromInt(flip) }) catch |err| {
        tex.release();
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

/// Registers a named actor state that plays `seq_name`. `next_state` may be
/// null; `flip` is applied on top of each frame's own flip.
export fn pz_anim_add_state(eng: *PzEngine, state_name: [*:0]const u8, seq_name: [*:0]const u8, next_state: ?[*:0]const u8, flip: c_int) callconv(.c) i32 {
    const mgr = animMgr(eng) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    const seq = mgr.getSeq(std.mem.span(seq_name)) orelse {
        setLastErrorMsg("no sequence with that name");
        return -1;
    };
    mgr.addState(.{
        .name = std.mem.span(state_name),
        .nextState = if (next_state) |ns| std.mem.span(ns) else null,
        .sequence = seq,
        .flip = flipFromInt(flip),
    }) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

fn pzActorCreateImpl(eng: *PzEngine) !*PzActor {
    var actor = try pixzig.sprites.Actor.init(eng.alloc);
    errdefer actor.deinit();

    const wrapper = try eng.alloc.create(PzActor);
    errdefer eng.alloc.destroy(wrapper);

    wrapper.* = .{ .eng = eng, .actor = actor, .registry_index = undefined };
    try registryAdd(PzActor, &eng.actors, eng.alloc, wrapper);
    return wrapper;
}

export fn pz_actor_create(eng: *PzEngine) callconv(.c) ?*PzActor {
    return pzActorCreateImpl(eng) catch |err| {
        setLastErrorErr(err);
        return null;
    };
}

export fn pz_actor_destroy(ac: *PzActor) callconv(.c) void {
    ac.actor.deinit();
    registryRemove(PzActor, &ac.eng.actors, ac);
    ac.eng.alloc.destroy(ac);
}

/// Copies a state registered in the shared manager (by pz_anim_load_file or
/// pz_anim_add_state) into this actor. The first state added becomes current.
export fn pz_actor_add_state(ac: *PzActor, state_name: [*:0]const u8) callconv(.c) i32 {
    const mgr = animMgr(ac.eng) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    const state = mgr.getState(std.mem.span(state_name)) orelse {
        setLastErrorMsg("no actor state with that name");
        return -1;
    };
    _ = ac.actor.addState(state, .{}) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

/// Switches the actor to `state_name` and applies that state's first frame to
/// `spr` right away, so the sprite updates even before the next tick.
export fn pz_actor_set_state(ac: *PzActor, state_name: [*:0]const u8, spr: *PzSprite) callconv(.c) void {
    ac.actor.setState(std.mem.span(state_name));
    const st = ac.actor.currState orelse return;
    if (st.sequence.frames.items.len == 0) return;
    st.sequence.frames.items[0].apply(&spr.sprite, st.flip);
}

/// Advances the actor's animation by `dt_ms` and writes the current frame
/// into `spr` (texture sub-rect + flip).
export fn pz_actor_update(ac: *PzActor, dt_ms: f64, spr: *PzSprite) callconv(.c) void {
    ac.actor.update(dt_ms, &spr.sprite);
}

// ---------------------------------------------------------------------------
// Window / viewport
// ---------------------------------------------------------------------------

export fn pz_window_size(eng: *PzEngine, out_w: *i32, out_h: *i32) callconv(.c) void {
    out_w.* = eng.engine.window_state.window_size.x;
    out_h.* = eng.engine.window_state.window_size.y;
}

export fn pz_framebuffer_size(eng: *PzEngine, out_w: *i32, out_h: *i32) callconv(.c) void {
    out_w.* = eng.engine.window_state.framebuffer_size.x;
    out_h.* = eng.engine.window_state.framebuffer_size.y;
}

export fn pz_logical_size(eng: *PzEngine, out_w: *i32, out_h: *i32) callconv(.c) void {
    out_w.* = eng.engine.viewport.logical_size.x;
    out_h.* = eng.engine.viewport.logical_size.y;
}

/// Framebuffer-pixels-per-window-coordinate (the larger axis). 1.0 on a
/// non-HiDPI display, 2.0 on a typical retina display.
export fn pz_window_scale_factor(eng: *PzEngine) callconv(.c) f32 {
    return @max(eng.engine.window_state.scale_factor.x, eng.engine.window_state.scale_factor.y);
}

export fn pz_window_set_title(eng: *PzEngine, title: [*:0]const u8) callconv(.c) void {
    eng.engine.window.setTitle(std.mem.span(title));
}

export fn pz_window_set_size(eng: *PzEngine, w: i32, h: i32) callconv(.c) void {
    eng.engine.window.setSize(w, h);
}

export fn pz_window_set_fullscreen(eng: *PzEngine, enabled: bool) callconv(.c) i32 {
    eng.engine.window.setFullscreen(enabled) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_window_is_fullscreen(eng: *PzEngine) callconv(.c) bool {
    return eng.engine.window.isFullscreen();
}

// ---------------------------------------------------------------------------
// Coordinate transforms. "screen" is window coordinates (what pz_mouse_pos
// and pz_mouse_raw_pos report); "logical" is the scaled game-resolution
// space passes are drawn in; "world" additionally accounts for a camera.
// The screen-space functions return false when the point is in a letterbox /
// pillarbox band with no logical-space equivalent.
// ---------------------------------------------------------------------------

fn fbToWindow(eng: *PzEngine, fb: pixzig.Vec2F) pixzig.Vec2F {
    const sx = eng.engine.window_state.scale_factor.x;
    const sy = eng.engine.window_state.scale_factor.y;
    return .{
        .x = if (sx > 0) fb.x / sx else fb.x,
        .y = if (sy > 0) fb.y / sy else fb.y,
    };
}

export fn pz_screen_to_logical(eng: *PzEngine, sx: f32, sy: f32, out_x: *f32, out_y: *f32) callconv(.c) bool {
    const logical = eng.engine.windowToLogical(.{ .x = sx, .y = sy }) orelse {
        out_x.* = 0;
        out_y.* = 0;
        return false;
    };
    out_x.* = logical.x;
    out_y.* = logical.y;
    return true;
}

export fn pz_logical_to_screen(eng: *PzEngine, lx: f32, ly: f32, out_x: *f32, out_y: *f32) callconv(.c) void {
    const win = fbToWindow(eng, eng.engine.viewport.logicalToFramebuffer(.{ .x = lx, .y = ly }));
    out_x.* = win.x;
    out_y.* = win.y;
}

export fn pz_screen_to_world(eng: *PzEngine, cam: *PzCamera, sx: f32, sy: f32, out_x: *f32, out_y: *f32) callconv(.c) bool {
    const logical = eng.engine.windowToLogical(.{ .x = sx, .y = sy }) orelse {
        out_x.* = 0;
        out_y.* = 0;
        return false;
    };
    const world = cam.camera.logicalToWorld(logical);
    out_x.* = world.x;
    out_y.* = world.y;
    return true;
}

export fn pz_world_to_screen(eng: *PzEngine, cam: *PzCamera, wx: f32, wy: f32, out_x: *f32, out_y: *f32) callconv(.c) void {
    const logical = cam.camera.worldToLogical(.{ .x = wx, .y = wy });
    const win = fbToWindow(eng, eng.engine.viewport.logicalToFramebuffer(logical));
    out_x.* = win.x;
    out_y.* = win.y;
}

// ---------------------------------------------------------------------------
// Mouse extras (wheel, motion delta, relative/captured mode, cursor)
// ---------------------------------------------------------------------------

export fn pz_mouse_scroll(eng: *PzEngine, out_x: *f32, out_y: *f32) callconv(.c) void {
    const s = eng.engine.inputs.mouse.scroll();
    out_x.* = s.x;
    out_y.* = s.y;
}

export fn pz_mouse_delta(eng: *PzEngine, out_x: *f32, out_y: *f32) callconv(.c) void {
    const d = eng.engine.inputs.mouse.delta();
    out_x.* = d.x;
    out_y.* = d.y;
}

/// Cursor position in window coordinates (unmapped; unlike pz_mouse_pos this
/// is not viewport-corrected and is valid even over letterbox bands).
export fn pz_mouse_raw_pos(eng: *PzEngine, out_x: *f32, out_y: *f32) callconv(.c) void {
    const p = eng.engine.inputs.mouse.rawPos();
    out_x.* = p.x;
    out_y.* = p.y;
}

/// Enables/disables relative (captured) mouse mode: the OS cursor is hidden
/// and pz_mouse_delta reports unbounded motion. Good for FPS-style controls.
export fn pz_mouse_set_relative(eng: *PzEngine, enabled: bool) callconv(.c) i32 {
    eng.engine.window.setCursorCapture(enabled) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return 0;
}

export fn pz_mouse_relative(eng: *PzEngine) callconv(.c) bool {
    return eng.engine.window.cursorCaptured();
}

/// Shows or hides the system cursor (SDL applies this process-wide).
export fn pz_cursor_show(eng: *PzEngine, visible: bool) callconv(.c) void {
    _ = eng;
    pixzig.platform.showCursor(visible);
}

// ---------------------------------------------------------------------------
// Keyboard text input + modifier state
// ---------------------------------------------------------------------------

var g_text_buf: [512]u8 = undefined;

/// UTF-8 text typed during the current tick (layout- and IME-correct), as a
/// NUL-terminated string. Empty when nothing was typed. Only meaningful
/// between pz_update_input and pz_finish_tick. The returned pointer is reused
/// each call; copy the bytes if you need to keep them.
export fn pz_key_text(eng: *PzEngine) callconv(.c) [*:0]const u8 {
    const n = eng.engine.inputs.keyboard.text(g_text_buf[0 .. g_text_buf.len - 1]);
    g_text_buf[n] = 0;
    return @ptrCast(&g_text_buf);
}

export fn pz_key_shift(eng: *PzEngine) callconv(.c) bool {
    return eng.engine.inputs.keyboard.shift();
}

export fn pz_key_ctrl(eng: *PzEngine) callconv(.c) bool {
    return eng.engine.inputs.keyboard.ctrl();
}

export fn pz_key_alt(eng: *PzEngine) callconv(.c) bool {
    return eng.engine.inputs.keyboard.alt();
}

export fn pz_key_super(eng: *PzEngine) callconv(.c) bool {
    return eng.engine.inputs.keyboard.super();
}

// ---------------------------------------------------------------------------
// Tilemap runtime access. All functions take a *PzTilemapRenderer (the
// handle from pz_tilemap_renderer_create) and a raw `layer_index` /
// `group_index` into the loaded map's layer / object-group lists -- the same
// index convention pz_tilemap_pixel_size already uses. Tile values are
// tileset indices (0-based), -1 meaning "no tile".
//
// Collision flag bits (see pz_tilemap_tile_flags), matching the engine:
//   1  blocks left     2  blocks top      4  blocks right
//   8  blocks bottom   0x0f blocks all    0x10 kills
// ---------------------------------------------------------------------------

const PzTileObject = extern struct {
    id: i32,
    gid: i32,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

var g_tm_str_a: [256]u8 = undefined;
var g_tm_str_b: [256]u8 = undefined;
var g_tm_str_c: [256]u8 = undefined;

fn tmCopyZ(buf: []u8, s: []const u8) [*:0]const u8 {
    const n = @min(s.len, buf.len - 1);
    @memcpy(buf[0..n], s[0..n]);
    buf[n] = 0;
    return @ptrCast(buf.ptr);
}

fn tmLayer(tr: *PzTilemapRenderer, layer_index: i32) ?*pixzig.tile.TileLayer {
    if (layer_index < 0) return null;
    return tr.map.val.layerByIndex(@intCast(layer_index));
}

fn tmGroup(tr: *PzTilemapRenderer, group_index: i32) ?*pixzig.tile.ObjectGroup {
    if (group_index < 0) return null;
    return tr.map.val.objectGroupByIndex(@intCast(group_index));
}

fn tmPropValue(props: ?std.ArrayList(pixzig.tile.Property), name: []const u8) ?[]const u8 {
    const list = props orelse return null;
    for (list.items) |p| {
        if (std.mem.eql(u8, p.name, name)) return p.value;
    }
    return null;
}

export fn pz_tilemap_layer_count(tr: *PzTilemapRenderer) callconv(.c) i32 {
    return @intCast(tr.map.val.layers.items.len);
}

/// Raw index of the first layer named `name`, or -1 if there is none.
export fn pz_tilemap_layer_index(tr: *PzTilemapRenderer, name: [*:0]const u8) callconv(.c) i32 {
    const want = std.mem.span(name);
    for (tr.map.val.layers.items, 0..) |layer, i| {
        if (layer.name) |n| {
            if (std.mem.eql(u8, n, want)) return @intCast(i);
        }
    }
    return -1;
}

/// Layer dimensions in tiles. Writes (0, 0) for an out-of-range index.
export fn pz_tilemap_layer_size(tr: *PzTilemapRenderer, layer_index: i32, out_w: *i32, out_h: *i32) callconv(.c) void {
    const layer = tmLayer(tr, layer_index) orelse {
        out_w.* = 0;
        out_h.* = 0;
        return;
    };
    out_w.* = layer.size.x;
    out_h.* = layer.size.y;
}

/// A layer's per-tile size in pixels. Writes (0, 0) for an out-of-range index.
export fn pz_tilemap_tile_size(tr: *PzTilemapRenderer, layer_index: i32, out_w: *i32, out_h: *i32) callconv(.c) void {
    const layer = tmLayer(tr, layer_index) orelse {
        out_w.* = 0;
        out_h.* = 0;
        return;
    };
    out_w.* = layer.tileSize.x;
    out_h.* = layer.tileSize.y;
}

/// Tileset index at tile coords (tx, ty). -1 for an empty cell, an
/// out-of-bounds coord, or an out-of-range layer.
export fn pz_tilemap_get_tile(tr: *PzTilemapRenderer, layer_index: i32, tx: i32, ty: i32) callconv(.c) i32 {
    const layer = tmLayer(tr, layer_index) orelse return -1;
    return layer.tileData(tx, ty);
}

/// Sets the tileset index at (tx, ty). Out-of-bounds coords are ignored.
/// Call pz_tilemap_refresh afterwards (once, after a batch of edits) to make
/// the change visible.
export fn pz_tilemap_set_tile(tr: *PzTilemapRenderer, layer_index: i32, tx: i32, ty: i32, value: i32) callconv(.c) void {
    const layer = tmLayer(tr, layer_index) orelse return;
    layer.setTileData(tx, ty, value);
}

/// Marks every rendered chunk dirty so pz_tilemap_set_tile edits are picked
/// up. Chunks rebuild lazily as they come into view.
export fn pz_tilemap_refresh(tr: *PzTilemapRenderer) callconv(.c) void {
    tr.renderer.markAllDirty();
}

/// The engine collision/behaviour bitmask for the tile at (tx, ty), or 0
/// when the cell is empty, out of bounds, or the layer has no tileset.
export fn pz_tilemap_tile_flags(tr: *PzTilemapRenderer, layer_index: i32, tx: i32, ty: i32) callconv(.c) i32 {
    const layer = tmLayer(tr, layer_index) orelse return 0;
    const t = layer.tile(tx, ty) orelse return 0;
    return @intCast(t.core);
}

/// True when the tile at (tx, ty) blocks movement on every side
/// (`blocks all`).
export fn pz_tilemap_tile_blocked(tr: *PzTilemapRenderer, layer_index: i32, tx: i32, ty: i32) callconv(.c) bool {
    const layer = tmLayer(tr, layer_index) orelse return false;
    const t = layer.tile(tx, ty) orelse return false;
    return (t.core & pixzig.tile.BlocksAll) != 0;
}

/// A custom string property on the tileset tile at (tx, ty), or "" when the
/// tile or property is absent. Returned pointer is reused each call.
export fn pz_tilemap_tile_prop(tr: *PzTilemapRenderer, layer_index: i32, tx: i32, ty: i32, name: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const empty: [*:0]const u8 = "";
    const layer = tmLayer(tr, layer_index) orelse return empty;
    const t = layer.tile(tx, ty) orelse return empty;
    const v = tmPropValue(t.properties, std.mem.span(name)) orelse return empty;
    return tmCopyZ(&g_tm_str_a, v);
}

/// Tile coords covering world-pixel (wx, wy) in the given layer's tile grid.
/// World pixels are the tilemap's own space (origin at the map's top-left),
/// the space the renderer draws in.
export fn pz_tilemap_world_to_tile(tr: *PzTilemapRenderer, layer_index: i32, wx: f32, wy: f32, out_tx: *i32, out_ty: *i32) callconv(.c) void {
    const layer = tmLayer(tr, layer_index) orelse {
        out_tx.* = 0;
        out_ty.* = 0;
        return;
    };
    const tw: f32 = @floatFromInt(layer.tileSize.x);
    const th: f32 = @floatFromInt(layer.tileSize.y);
    out_tx.* = if (tw > 0) @intFromFloat(@floor(wx / tw)) else 0;
    out_ty.* = if (th > 0) @intFromFloat(@floor(wy / th)) else 0;
}

/// World-pixel position of the top-left corner of tile (tx, ty).
export fn pz_tilemap_tile_to_world(tr: *PzTilemapRenderer, layer_index: i32, tx: i32, ty: i32, out_x: *f32, out_y: *f32) callconv(.c) void {
    const layer = tmLayer(tr, layer_index) orelse {
        out_x.* = 0;
        out_y.* = 0;
        return;
    };
    out_x.* = @floatFromInt(tx * layer.tileSize.x);
    out_y.* = @floatFromInt(ty * layer.tileSize.y);
}

export fn pz_tilemap_object_group_count(tr: *PzTilemapRenderer) callconv(.c) i32 {
    return @intCast(tr.map.val.objectGroups.items.len);
}

/// Raw index of the first object group named `name`, or -1 if there is none.
export fn pz_tilemap_object_group_index(tr: *PzTilemapRenderer, name: [*:0]const u8) callconv(.c) i32 {
    const want = std.mem.span(name);
    for (tr.map.val.objectGroups.items, 0..) |group, i| {
        if (group.name) |n| {
            if (std.mem.eql(u8, n, want)) return @intCast(i);
        }
    }
    return -1;
}

export fn pz_tilemap_object_count(tr: *PzTilemapRenderer, group_index: i32) callconv(.c) i32 {
    const group = tmGroup(tr, group_index) orelse return 0;
    return @intCast(group.objects.items.len);
}

/// Index of the first object named `name` in the group, or -1 if there is none.
export fn pz_tilemap_object_index(tr: *PzTilemapRenderer, group_index: i32, name: [*:0]const u8) callconv(.c) i32 {
    const group = tmGroup(tr, group_index) orelse return -1;
    const want = std.mem.span(name);
    for (group.objects.items, 0..) |obj, i| {
        if (obj.name) |n| {
            if (std.mem.eql(u8, n, want)) return @intCast(i);
        }
    }
    return -1;
}

/// Fills `out` with the numeric fields of object `obj_index` in the group.
/// Returns false (leaving `out` untouched) for an out-of-range index. Name,
/// class and custom properties come from the pz_tilemap_object_* string
/// getters.
export fn pz_tilemap_object_get(tr: *PzTilemapRenderer, group_index: i32, obj_index: i32, out: *PzTileObject) callconv(.c) bool {
    const group = tmGroup(tr, group_index) orelse return false;
    if (obj_index < 0 or @as(usize, @intCast(obj_index)) >= group.objects.items.len) return false;
    const obj = &group.objects.items[@intCast(obj_index)];
    out.* = .{
        .id = obj.id,
        .gid = obj.gid,
        .x = obj.pos.x,
        .y = obj.pos.y,
        .w = obj.size.x,
        .h = obj.size.y,
    };
    return true;
}

export fn pz_tilemap_object_name(tr: *PzTilemapRenderer, group_index: i32, obj_index: i32) callconv(.c) [*:0]const u8 {
    const empty: [*:0]const u8 = "";
    const group = tmGroup(tr, group_index) orelse return empty;
    if (obj_index < 0 or @as(usize, @intCast(obj_index)) >= group.objects.items.len) return empty;
    const name = group.objects.items[@intCast(obj_index)].name orelse return empty;
    return tmCopyZ(&g_tm_str_a, name);
}

export fn pz_tilemap_object_class(tr: *PzTilemapRenderer, group_index: i32, obj_index: i32) callconv(.c) [*:0]const u8 {
    const empty: [*:0]const u8 = "";
    const group = tmGroup(tr, group_index) orelse return empty;
    if (obj_index < 0 or @as(usize, @intCast(obj_index)) >= group.objects.items.len) return empty;
    const class = group.objects.items[@intCast(obj_index)].class orelse return empty;
    return tmCopyZ(&g_tm_str_b, class);
}

/// A custom string property on the object, or "" when absent. Returned
/// pointer is reused each call.
export fn pz_tilemap_object_prop(tr: *PzTilemapRenderer, group_index: i32, obj_index: i32, name: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const empty: [*:0]const u8 = "";
    const group = tmGroup(tr, group_index) orelse return empty;
    if (obj_index < 0 or @as(usize, @intCast(obj_index)) >= group.objects.items.len) return empty;
    const obj = &group.objects.items[@intCast(obj_index)];
    const v = tmPropValue(obj.properties, std.mem.span(name)) orelse return empty;
    return tmCopyZ(&g_tm_str_c, v);
}
