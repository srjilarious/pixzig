const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const sdl = @import("sdl3");

const event = pixzig.platform.event;
const Event = pixzig.Event;

fn sdlEvent(eventType: u32) sdl.SDL_Event {
    var ev = std.mem.zeroes(sdl.SDL_Event);
    ev.type = eventType;
    return ev;
}

fn kindOf(ev: sdl.SDL_Event) ?Event.Kind {
    const translated = event.fromSdl(&ev) orelse return null;
    return std.meta.activeTag(translated);
}

/// Both of SDL's ways of asking to close become the one `close_requested`,
/// which the pump then de-duplicates per pass.
pub fn closeEventsTranslateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_QUIT)), .close_requested);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED)), .close_requested);
}

pub fn windowEventsTranslateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var resized = sdlEvent(sdl.SDL_EVENT_WINDOW_RESIZED);
    resized.window.data1 = 1280;
    resized.window.data2 = 720;
    const translated = event.fromSdl(&resized).?;
    try testz.expectEqual(translated.window_resized.x, 1280);
    try testz.expectEqual(translated.window_resized.y, 720);

    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WINDOW_FOCUS_GAINED)), .focus_gained);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WINDOW_FOCUS_LOST)), .focus_lost);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WINDOW_MINIMIZED)), .minimized);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WINDOW_MAXIMIZED)), .maximized);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WINDOW_RESTORED)), .restored);
}

pub fn dropEventsTranslateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var file = sdlEvent(sdl.SDL_EVENT_DROP_FILE);
    file.drop.data = "/tmp/level1.tmx";
    file.drop.x = 12.5;
    file.drop.y = 40.0;
    const dropped = event.fromSdl(&file).?;
    try testz.expectEqualStr(dropped.drop_file.path, "/tmp/level1.tmx");
    try testz.expectEqual(dropped.drop_file.pos.x, 12.5);
    try testz.expectEqual(dropped.drop_file.pos.y, 40.0);

    var text = sdlEvent(sdl.SDL_EVENT_DROP_TEXT);
    text.drop.data = "hello";
    try testz.expectEqualStr(event.fromSdl(&text).?.drop_text.text, "hello");

    // A drop without data has nothing to hand on, so it's skipped rather
    // than turned into an empty path.
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_DROP_FILE)), null);

    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_DROP_BEGIN)), .drop_begin);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_DROP_COMPLETE)), .drop_complete);
}

pub fn gamepadAndLifecycleEventsTranslateTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    var added = sdlEvent(sdl.SDL_EVENT_GAMEPAD_ADDED);
    added.gdevice.which = 7;
    try testz.expectEqual(event.fromSdl(&added).?.gamepad_added, 7);

    var removed = sdlEvent(sdl.SDL_EVENT_GAMEPAD_REMOVED);
    removed.gdevice.which = 7;
    try testz.expectEqual(event.fromSdl(&removed).?.gamepad_removed, 7);

    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WILL_ENTER_BACKGROUND)), .will_enter_background);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_DID_ENTER_BACKGROUND)), .did_enter_background);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WILL_ENTER_FOREGROUND)), .will_enter_foreground);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_DID_ENTER_FOREGROUND)), .did_enter_foreground);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_LOW_MEMORY)), .low_memory);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_TERMINATING)), .terminating);
}

/// Input stays with `InputManager`, and window bookkeeping the engine
/// consumes itself isn't forwarded.
pub fn inputEventsAreNotForwardedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    _ = alloc;

    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_KEY_DOWN)), null);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_MOUSE_MOTION)), null);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_TEXT_INPUT)), null);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_GAMEPAD_BUTTON_DOWN)), null);
    try testz.expectEqual(kindOf(sdlEvent(sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED)), null);
}
