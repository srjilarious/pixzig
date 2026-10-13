//! Engine-level events: everything the OS reports that isn't keyboard,
//! mouse or text input. `Engine.pollEventsWith` translates SDL's events
//! into `Event` and hands them to the app's `onEvent`, so games never see
//! an `SDL_Event`.
//!
//! Input events are deliberately not here. They are latched by
//! `InputManager` and read per tick (`down`, `pressed`, actions), which is
//! what keeps them consistent across several fixed-step updates in one
//! frame.

const std = @import("std");
const sdl = @import("sdl3");
const common = @import("../common.zig");
const gamepad = @import("../input/gamepad.zig");

const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

pub const GamepadId = gamepad.GamepadId;

/// A file dropped onto the window.
pub const DroppedFile = struct {
    /// Borrowed from SDL and only valid during the `onEvent` call. Copy it
    /// to keep it.
    path: [:0]const u8,
    /// Where it was dropped, in window coordinates. Pass it to
    /// `eng.windowToLogical` for game coordinates.
    pos: Vec2F,
};

/// Text dragged from another application and dropped onto the window.
pub const DroppedText = struct {
    /// Borrowed from SDL and only valid during the `onEvent` call. Copy it
    /// to keep it.
    text: [:0]const u8,
    /// Where it was dropped, in window coordinates.
    pos: Vec2F,
};

pub const Event = union(enum) {
    /// The user asked to close the window or quit: the close button,
    /// Alt+F4, Cmd+Q, or SIGINT/SIGTERM. The window closes after the event
    /// unless the app calls `eng.cancelClose()` while handling it. Arrives
    /// at most once per event pump, even though SDL reports both a window
    /// close and a quit when the last window is closed.
    close_requested,
    /// The window's size changed, in window coordinates.
    /// `eng.windowState` and `eng.viewport` already reflect it.
    window_resized: Vec2I,
    /// The window gained keyboard focus.
    focus_gained,
    /// The window lost keyboard focus. Input state has already been
    /// cleared, so nothing held reads as still down.
    focus_lost,
    minimized,
    maximized,
    /// The window left the minimized or maximized state.
    restored,

    /// A drag-and-drop onto the window started. One or more `drop_file`
    /// or `drop_text` events follow, then `drop_complete`.
    drop_begin,
    drop_file: DroppedFile,
    drop_text: DroppedText,
    drop_complete,

    /// A gamepad was connected. Only reported when `inputOpts.numGamepads`
    /// is above zero, since that is what starts SDL's gamepad subsystem.
    /// Pads already plugged in at startup arrive on the first pump. Match
    /// it to a slot with `Gamepad.id()`.
    gamepad_added: GamepadId,
    /// A gamepad was disconnected.
    gamepad_removed: GamepadId,

    // Application lifecycle, mostly from mobile platforms. On iOS and
    // Android `will_enter_background` must be acted on before returning,
    // and this arrives through the pump a frame late at best, so treat
    // these as advisory until mobile support registers an event watch.

    /// The OS is about to background the app: pause audio, save state.
    will_enter_background,
    did_enter_background,
    will_enter_foreground,
    /// The app is in the foreground again: resume.
    did_enter_foreground,
    /// The OS is low on memory. Free caches you can rebuild.
    low_memory,
    /// The OS is terminating the app.
    terminating,

    pub const Kind = std.meta.Tag(Event);
};

/// Translates one SDL event into an engine `Event`, or null for events
/// that aren't engine-level: input events, and window events the engine
/// consumes without forwarding (pixel-size and display-scale changes,
/// expose, move, ...).
pub fn fromSdl(event: *const sdl.SDL_Event) ?Event {
    return switch (event.type) {
        sdl.SDL_EVENT_QUIT,
        sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
        => .close_requested,
        sdl.SDL_EVENT_WINDOW_RESIZED => .{ .window_resized = .{
            .x = event.window.data1,
            .y = event.window.data2,
        } },
        sdl.SDL_EVENT_WINDOW_FOCUS_GAINED => .focus_gained,
        sdl.SDL_EVENT_WINDOW_FOCUS_LOST => .focus_lost,
        sdl.SDL_EVENT_WINDOW_MINIMIZED => .minimized,
        sdl.SDL_EVENT_WINDOW_MAXIMIZED => .maximized,
        sdl.SDL_EVENT_WINDOW_RESTORED => .restored,

        sdl.SDL_EVENT_DROP_BEGIN => .drop_begin,
        sdl.SDL_EVENT_DROP_FILE => .{ .drop_file = .{
            .path = std.mem.span(event.drop.data orelse return null),
            .pos = .{ .x = event.drop.x, .y = event.drop.y },
        } },
        sdl.SDL_EVENT_DROP_TEXT => .{ .drop_text = .{
            .text = std.mem.span(event.drop.data orelse return null),
            .pos = .{ .x = event.drop.x, .y = event.drop.y },
        } },
        sdl.SDL_EVENT_DROP_COMPLETE => .drop_complete,

        sdl.SDL_EVENT_GAMEPAD_ADDED => .{ .gamepad_added = event.gdevice.which },
        sdl.SDL_EVENT_GAMEPAD_REMOVED => .{ .gamepad_removed = event.gdevice.which },

        sdl.SDL_EVENT_WILL_ENTER_BACKGROUND => .will_enter_background,
        sdl.SDL_EVENT_DID_ENTER_BACKGROUND => .did_enter_background,
        sdl.SDL_EVENT_WILL_ENTER_FOREGROUND => .will_enter_foreground,
        sdl.SDL_EVENT_DID_ENTER_FOREGROUND => .did_enter_foreground,
        sdl.SDL_EVENT_LOW_MEMORY => .low_memory,
        sdl.SDL_EVENT_TERMINATING => .terminating,
        else => null,
    };
}
