//! Flat C ABI surface for pixzig, built as `libpixzig_ffi` (see the
//! `python-ffi` build step). Freezes a single, non-generic
//! `PixzigEngineOptions` instantiation so the engine's comptime-generic
//! API can be called from a C ABI. Python (or any other C-caller) owns the
//! game loop and drives it by calling the frame-stepping functions below in
//! sequence; nothing here calls back into the caller.
const std = @import("std");
const pixzig = @import("pixzig");

const FfiOpts = pixzig.PixzigEngineOptions{
    .inputOpts = .{ .mouse = true, .numGamepads = pixzig.input.MaxGamepads },
    .rendererOpts = .{ .textRendering = true },
};
const Engine = pixzig.PixzigEngine(FfiOpts);

const PzSprite = struct {
    eng: *PzEngine,
    sprite: pixzig.sprites.Sprite,
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
};

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

    wrapper.* = .{ .eng = eng, .sprite = sprite, .registry_index = undefined };
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

export fn pz_sprite_get_rect(spr: *PzSprite, out_x: *f32, out_y: *f32, out_w: *f32, out_h: *f32) callconv(.c) void {
    out_x.* = spr.sprite.dest.l;
    out_y.* = spr.sprite.dest.t;
    out_w.* = spr.sprite.dest.width();
    out_h.* = spr.sprite.dest.height();
}

export fn pz_sprite_draw(spr: *PzSprite) callconv(.c) void {
    spr.eng.engine.renderer.drawSprite(&spr.sprite);
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
