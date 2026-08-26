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

const PzEngine = struct {
    engine: *Engine,
    alloc: std.mem.Allocator,
    sprites: std.ArrayList(?pixzig.sprites.Sprite),
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
    };
    return pz;
}

export fn pz_deinit(eng: *PzEngine) callconv(.c) void {
    for (eng.sprites.items) |*slot| {
        if (slot.*) |*spr| spr.deinit();
    }
    eng.sprites.deinit(eng.alloc);
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
    pixzig.glfw.pollEvents();
    eng.engine.refreshWindowState();
}

export fn pz_update_input(eng: *PzEngine) callconv(.c) void {
    eng.engine.inputs.update(eng.engine.window, eng.engine.window_state.scale_factor, &eng.engine.viewport);
    eng.engine.resources.checkHotReload();
}

export fn pz_swap_buffers(eng: *PzEngine) callconv(.c) void {
    eng.engine.window.swapBuffers();
}

export fn pz_render_begin(eng: *PzEngine) callconv(.c) void {
    eng.engine.renderer.begin(eng.engine.uiMatrix());
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
// Sprites. sprite_id is an index into a per-engine slot table; -1 means
// "no such sprite" on lookups that must return a value.
// ---------------------------------------------------------------------------

fn getSprite(eng: *PzEngine, sprite_id: i32) ?*pixzig.sprites.Sprite {
    if (sprite_id < 0) return null;
    const idx: usize = @intCast(sprite_id);
    if (idx >= eng.sprites.items.len) return null;
    if (eng.sprites.items[idx]) |*s| return s;
    return null;
}

export fn pz_sprite_create(eng: *PzEngine, texture_name: [*:0]const u8) callconv(.c) i32 {
    const handle = eng.engine.resources.acquireTexture(std.mem.span(texture_name)) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    const size = pixzig.Vec2F{
        .x = @floatFromInt(handle.val.size.x),
        .y = @floatFromInt(handle.val.size.y),
    };
    const sprite = pixzig.sprites.Sprite.create(handle, size);

    for (eng.sprites.items, 0..) |slot, i| {
        if (slot == null) {
            eng.sprites.items[i] = sprite;
            return @intCast(i);
        }
    }
    eng.sprites.append(eng.alloc, sprite) catch |err| {
        setLastErrorErr(err);
        return -1;
    };
    return @intCast(eng.sprites.items.len - 1);
}

export fn pz_sprite_set_pos(eng: *PzEngine, sprite_id: i32, x: i32, y: i32) callconv(.c) void {
    const spr = getSprite(eng, sprite_id) orelse {
        setLastErrorMsg("invalid sprite id");
        return;
    };
    spr.setPos(x, y);
}

export fn pz_sprite_draw(eng: *PzEngine, sprite_id: i32) callconv(.c) void {
    const spr = getSprite(eng, sprite_id) orelse {
        setLastErrorMsg("invalid sprite id");
        return;
    };
    eng.engine.renderer.drawSprite(spr);
}

export fn pz_sprite_destroy(eng: *PzEngine, sprite_id: i32) callconv(.c) void {
    if (sprite_id < 0) return;
    const idx: usize = @intCast(sprite_id);
    if (idx >= eng.sprites.items.len) return;
    if (eng.sprites.items[idx]) |*s| {
        s.deinit();
        eng.sprites.items[idx] = null;
    }
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
