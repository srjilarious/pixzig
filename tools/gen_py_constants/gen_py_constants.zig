//! Regenerates `python/pixzig/constants.py` from the engine's own enums.
//!
//! The Python bindings pass key and button codes, event kinds, blend modes
//! and the like across the C ABI as plain ints, so the two sides have to
//! agree on the numbering. These are pixzig's own dense enum values, and
//! this generator is what keeps the copy honest. Run it after adding,
//! removing or reordering anything in `src/pixzig/input/keys.zig`, the
//! `Event` union in `src/pixzig/platform/event.zig`, or any other enum
//! listed in `main` below:
//!
//!     zig build py-constants
//!
//! It rewrites the file in place; commit the result.

const std = @import("std");
const pixzig = @import("pixzig");

const keys = pixzig.input.keys;
const MouseAxis = pixzig.input.action.MouseAxis;
const EventKind = pixzig.Event.Kind;
const InputDevice = pixzig.input.Device;
const Ease = pixzig.Ease;
const BlendMode = pixzig.BlendMode;
const TextAlign = pixzig.TextAlign;
const TargetFilter = pixzig.renderer.TargetFilter;

const header =
    \\"""Key, mouse, gamepad, event, easing, blend and text codes.
    \\
    \\GENERATED FILE -- do not edit by hand. Regenerate with `zig build
    \\py-constants`, which reads the enums in `src/pixzig/input/keys.zig`,
    \\the `Event` kinds in `src/pixzig/platform/event.zig`, and the
    \\renderer and easing enums listed in
    \\`tools/gen_py_constants/gen_py_constants.zig`.
    \\
    \\The values are pixzig's own dense indices into the engine's enums.
    \\They are plain ints under the hood, but code should always use these
    \\names rather than the numbers.
    \\"""
    \\
;

/// Emits one Python class whose members are `Enum`'s fields, uppercased,
/// with their integer values. `doc` becomes the class's docstring (Google
/// style, read by `tools/gen_py_docs.py`), indented to the class body.
fn writeEnum(out: *std.ArrayList(u8), alloc: std.mem.Allocator, comptime name: []const u8, comptime Enum: type, comptime doc: []const u8) !void {
    try out.appendSlice(alloc, "\n\nclass " ++ name ++ ":\n");
    var lines = std.mem.splitScalar(u8, doc, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (first) {
            try out.print(alloc, "    \"\"\"{s}\n", .{line});
            first = false;
        } else if (line.len == 0) {
            try out.append(alloc, '\n');
        } else {
            try out.print(alloc, "    {s}\n", .{line});
        }
    }
    try out.appendSlice(alloc, "    \"\"\"\n\n");
    const info = @typeInfo(Enum).@"enum";
    inline for (info.field_names, info.field_values) |fieldName, value| {
        var buf: [64]u8 = undefined;
        const upper = std.ascii.upperString(buf[0..fieldName.len], fieldName);
        try out.print(alloc, "    {s} = {d}\n", .{ upper, value });
    }
}

// Docstrings for the generated classes, in the Google style the rest of
// the Python package uses. Keep the attribute lists in step with the enums.

const key_doc =
    \\A keyboard key, by physical position rather than the printed letter.
    \\
    \\`Key.W` is where W sits on a US QWERTY keyboard, whatever layout is
    \\active, so WASD controls stay under the same fingers on AZERTY or
    \\Dvorak. Read typed text with `Keyboard.text()` instead. Letters are
    \\`A` to `Z`, digits `ZERO` to `NINE`, and the rest follow the engine's
    \\`Key` names uppercased: `SPACE`, `ESCAPE`, `ENTER`, `LEFT`,
    \\`LEFT_SHIFT`, `F1`, `KP_ENTER` and so on. `BACK` is Android's back
    \\button.
;

const mouse_button_doc =
    \\A mouse button.
    \\
    \\Attributes:
    \\    LEFT: The left button.
    \\    RIGHT: The right button.
    \\    MIDDLE: The middle button or wheel click.
    \\    X1: The first side button, usually "back".
    \\    X2: The second side button, usually "forward".
;

const gamepad_button_doc =
    \\A gamepad button, by position on an Xbox-style pad.
    \\
    \\Attributes:
    \\    A: The bottom face button.
    \\    B: The right face button.
    \\    X: The left face button.
    \\    Y: The top face button.
    \\    LEFT_BUMPER: The left shoulder button.
    \\    RIGHT_BUMPER: The right shoulder button.
    \\    BACK: The back or select button.
    \\    START: The start button.
    \\    GUIDE: The guide or home button.
    \\    LEFT_THUMB: Pressing the left stick in.
    \\    RIGHT_THUMB: Pressing the right stick in.
    \\    DPAD_UP: D-pad up.
    \\    DPAD_RIGHT: D-pad right.
    \\    DPAD_DOWN: D-pad down.
    \\    DPAD_LEFT: D-pad left.
;

const gamepad_axis_doc =
    \\A gamepad stick or trigger axis.
    \\
    \\Attributes:
    \\    LEFT_X: The left stick, -1 left to 1 right.
    \\    LEFT_Y: The left stick, -1 up to 1 down.
    \\    RIGHT_X: The right stick, -1 left to 1 right.
    \\    RIGHT_Y: The right stick, -1 up to 1 down.
    \\    LEFT_TRIGGER: The left trigger, 0 to 1.
    \\    RIGHT_TRIGGER: The right trigger, 0 to 1.
;

const mouse_axis_doc =
    \\A direction of mouse movement, for `ActionMap.bind_axis_mouse`.
    \\
    \\Attributes:
    \\    X: Horizontal movement, positive to the right.
    \\    Y: Vertical movement, positive downward.
;

const event_kind_doc =
    \\What an `Event` reports.
    \\
    \\Attributes:
    \\    CLOSE_REQUESTED: The close button, Alt+F4, Cmd+Q, or SIGINT/SIGTERM.
    \\        The window closes afterwards unless `App.cancel_close()` is called.
    \\    WINDOW_RESIZED: The window changed size; see `Event.size`.
    \\    FOCUS_GAINED: The window got keyboard focus.
    \\    FOCUS_LOST: The window lost keyboard focus. Input state is already
    \\        cleared, so no key stays stuck down.
    \\    MINIMIZED: The window was minimized.
    \\    MAXIMIZED: The window was maximized.
    \\    RESTORED: The window was restored from minimized or maximized.
    \\    DROP_BEGIN: A drag-and-drop onto the window started.
    \\    DROP_FILE: A file was dropped; see `Event.path` and `Event.pos`.
    \\    DROP_TEXT: Text was dropped; see `Event.text` and `Event.pos`.
    \\    DROP_COMPLETE: The drag-and-drop finished.
    \\    GAMEPAD_ADDED: A pad was plugged in; see `Event.gamepad_id`.
    \\    GAMEPAD_REMOVED: A pad was unplugged; see `Event.gamepad_id`.
    \\    WILL_ENTER_BACKGROUND: The app is about to be suspended, mostly on
    \\        mobile. Audio is already paused; save here.
    \\    DID_ENTER_BACKGROUND: The app was suspended.
    \\    WILL_ENTER_FOREGROUND: The app is about to resume.
    \\    DID_ENTER_FOREGROUND: The app resumed. Audio is already resumed.
    \\    LOW_MEMORY: The OS is low on memory.
    \\    TERMINATING: The OS is closing the app.
    \\    SCRIPT_RELOADED: A Lua script was reloaded. Zig games only; Python
    \\        games never see it.
;

const input_device_doc =
    \\A kind of input device, from `App.last_device`.
    \\
    \\Attributes:
    \\    KEYBOARD: A key was pressed.
    \\    MOUSE: A real mouse moved or clicked.
    \\    GAMEPAD: A gamepad was used.
    \\    TOUCH: The screen was touched.
;

const ease_doc =
    \\An easing curve, for `pixzig.easing` and `pixzig.sequence`.
    \\
    \\`_IN` curves start slow, `_OUT` curves end slow and `_IN_OUT` curves do
    \\both. `BACK_*` and `ELASTIC_OUT` overshoot before settling.
    \\
    \\Attributes:
    \\    LINEAR: Constant speed.
    \\    QUAD_IN: Quadratic, starting slow.
    \\    QUAD_OUT: Quadratic, ending slow.
    \\    QUAD_IN_OUT: Quadratic, slow at both ends.
    \\    CUBIC_IN: Cubic, starting slow.
    \\    CUBIC_OUT: Cubic, ending slow.
    \\    CUBIC_IN_OUT: Cubic, slow at both ends.
    \\    SINE_IN: Sine, starting slow.
    \\    SINE_OUT: Sine, ending slow.
    \\    SINE_IN_OUT: Sine, slow at both ends.
    \\    BACK_IN: Pulls back below 0 before going.
    \\    BACK_OUT: Overshoots past 1 and settles.
    \\    ELASTIC_OUT: Overshoots and wobbles into place.
    \\    BOUNCE_OUT: Bounces off 1 like a dropped ball.
;

const blend_mode_doc =
    \\How draws combine with what's behind them, for `App.set_blend`.
    \\
    \\Attributes:
    \\    ALPHA: Normal transparency, the default.
    \\    ADDITIVE: Adds the color, brightening: glows, fire, lasers.
    \\    MULTIPLY: Multiplies what's behind by the color, darkening:
    \\        shadows, tinting.
    \\    PREMULTIPLIED: For colors already multiplied by their alpha, such
    \\        as a render target cleared transparent.
;

const text_align_doc =
    \\Which point of the text a draw's x names, for `Text.draw`.
    \\
    \\Attributes:
    \\    LEFT: x is the left edge.
    \\    CENTER: x is the middle.
    \\    RIGHT: x is the right edge.
;

const target_filter_doc =
    \\How a render target is sampled when drawn scaled, for
    \\`App.create_render_target`.
    \\
    \\Attributes:
    \\    NEAREST: Hard pixel edges, for low-resolution pixel art.
    \\    LINEAR: Smooth.
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer args.deinit();
    _ = args.next();
    const out_path = args.next() orelse "python/pixzig/constants.py";

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    try out.appendSlice(alloc, header);
    try writeEnum(&out, alloc, "Key", keys.Key, key_doc);
    try writeEnum(&out, alloc, "MouseButton", keys.MouseButton, mouse_button_doc);
    try writeEnum(&out, alloc, "GamepadButton", keys.GamepadButton, gamepad_button_doc);
    try writeEnum(&out, alloc, "GamepadAxis", keys.GamepadAxis, gamepad_axis_doc);
    try writeEnum(&out, alloc, "MouseAxis", MouseAxis, mouse_axis_doc);
    try writeEnum(&out, alloc, "EventKind", EventKind, event_kind_doc);
    try writeEnum(&out, alloc, "InputDevice", InputDevice, input_device_doc);
    try writeEnum(&out, alloc, "Ease", Ease, ease_doc);
    try writeEnum(&out, alloc, "BlendMode", BlendMode, blend_mode_doc);
    try writeEnum(&out, alloc, "TextAlign", TextAlign, text_align_doc);
    try writeEnum(&out, alloc, "TargetFilter", TargetFilter, target_filter_doc);

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = out.items });
    std.log.info("Wrote {s} ({d} bytes).", .{ out_path, out.items.len });
}
