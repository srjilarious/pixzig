# Constants

Module `pixzig.constants`. Generated from its docstrings by `tools/gen_py_docs.py`.

Key, mouse, gamepad, event, easing, blend and text codes.

GENERATED FILE -- do not edit by hand. Regenerate with `zig build py-constants`, which reads the enums in `src/pixzig/input/keys.zig`, the [`Event`](page:python-api/event#h2-event) kinds in `src/pixzig/platform/event.zig`, and the renderer and easing enums listed in `tools/gen_py_constants/gen_py_constants.zig`.

The values are pixzig's own dense indices into the engine's enums. They are plain ints under the hood, but code should always use these names rather than the numbers.

## `Key`

A keyboard key, by physical position rather than the printed letter.

`Key.W` is where W sits on a US QWERTY keyboard, whatever layout is active, so WASD controls stay under the same fingers on AZERTY or Dvorak. Read typed text with [`Keyboard.text`](page:python-api/input#h3-keyboard-text) instead. Letters are `A` to `Z`, digits `ZERO` to `NINE`, and the rest follow the engine's [`Key`](page:python-api/constants#h2-key) names uppercased: `SPACE`, `ESCAPE`, `ENTER`, `LEFT`, `LEFT_SHIFT`, `F1`, `KP_ENTER` and so on. `BACK` is Android's back button.

Members:

```python
UNKNOWN, SPACE, APOSTROPHE, COMMA, MINUS, PERIOD, SLASH, ZERO, ONE, TWO,
THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE, SEMICOLON, EQUAL, A, B, C, D, E,
F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z, LEFT_BRACKET,
BACKSLASH, RIGHT_BRACKET, GRAVE_ACCENT, ESCAPE, ENTER, TAB, BACKSPACE,
INSERT, DELETE, RIGHT, LEFT, DOWN, UP, PAGE_UP, PAGE_DOWN, HOME, END,
CAPS_LOCK, SCROLL_LOCK, NUM_LOCK, PRINT_SCREEN, PAUSE, F1, F2, F3, F4, F5,
F6, F7, F8, F9, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20, F21,
F22, F23, F24, KP_0, KP_1, KP_2, KP_3, KP_4, KP_5, KP_6, KP_7, KP_8, KP_9,
KP_DECIMAL, KP_DIVIDE, KP_MULTIPLY, KP_SUBTRACT, KP_ADD, KP_ENTER, KP_EQUAL,
LEFT_SHIFT, LEFT_CONTROL, LEFT_ALT, LEFT_SUPER, RIGHT_SHIFT, RIGHT_CONTROL,
RIGHT_ALT, RIGHT_SUPER, MENU, BACK
```

## `MouseButton`

A mouse button.

| Name | Value | Description |
|---|---|---|
| `LEFT` | `0` | The left button. |
| `RIGHT` | `1` | The right button. |
| `MIDDLE` | `2` | The middle button or wheel click. |
| `X1` | `3` | The first side button, usually "back". |
| `X2` | `4` | The second side button, usually "forward". |

## `GamepadButton`

A gamepad button, by position on an Xbox-style pad.

| Name | Value | Description |
|---|---|---|
| `A` | `0` | The bottom face button. |
| `B` | `1` | The right face button. |
| `X` | `2` | The left face button. |
| `Y` | `3` | The top face button. |
| `LEFT_BUMPER` | `4` | The left shoulder button. |
| `RIGHT_BUMPER` | `5` | The right shoulder button. |
| `BACK` | `6` | The back or select button. |
| `START` | `7` | The start button. |
| `GUIDE` | `8` | The guide or home button. |
| `LEFT_THUMB` | `9` | Pressing the left stick in. |
| `RIGHT_THUMB` | `10` | Pressing the right stick in. |
| `DPAD_UP` | `11` | D-pad up. |
| `DPAD_RIGHT` | `12` | D-pad right. |
| `DPAD_DOWN` | `13` | D-pad down. |
| `DPAD_LEFT` | `14` | D-pad left. |

## `GamepadAxis`

A gamepad stick or trigger axis.

| Name | Value | Description |
|---|---|---|
| `LEFT_X` | `0` | The left stick, -1 left to 1 right. |
| `LEFT_Y` | `1` | The left stick, -1 up to 1 down. |
| `RIGHT_X` | `2` | The right stick, -1 left to 1 right. |
| `RIGHT_Y` | `3` | The right stick, -1 up to 1 down. |
| `LEFT_TRIGGER` | `4` | The left trigger, 0 to 1. |
| `RIGHT_TRIGGER` | `5` | The right trigger, 0 to 1. |

## `MouseAxis`

A direction of mouse movement, for [`ActionMap.bind_axis_mouse`](page:python-api/action#h3-actionmap-bind-axis-mouse).

| Name | Value | Description |
|---|---|---|
| `X` | `0` | Horizontal movement, positive to the right. |
| `Y` | `1` | Vertical movement, positive downward. |

## `EventKind`

What an [`Event`](page:python-api/event#h2-event) reports.

| Name | Value | Description |
|---|---|---|
| `CLOSE_REQUESTED` | `0` | The close button, Alt+F4, Cmd+Q, or SIGINT/SIGTERM. The window closes afterwards unless [`App.cancel_close`](page:python-api/app#h3-app-cancel-close) is called. |
| `WINDOW_RESIZED` | `1` | The window changed size; see `Event.size`. |
| `FOCUS_GAINED` | `2` | The window got keyboard focus. |
| `FOCUS_LOST` | `3` | The window lost keyboard focus. Input state is already cleared, so no key stays stuck down. |
| `MINIMIZED` | `4` | The window was minimized. |
| `MAXIMIZED` | `5` | The window was maximized. |
| `RESTORED` | `6` | The window was restored from minimized or maximized. |
| `DROP_BEGIN` | `7` | A drag-and-drop onto the window started. |
| `DROP_FILE` | `8` | A file was dropped; see `Event.path` and `Event.pos`. |
| `DROP_TEXT` | `9` | Text was dropped; see `Event.text` and `Event.pos`. |
| `DROP_COMPLETE` | `10` | The drag-and-drop finished. |
| `GAMEPAD_ADDED` | `11` | A pad was plugged in; see `Event.gamepad_id`. |
| `GAMEPAD_REMOVED` | `12` | A pad was unplugged; see `Event.gamepad_id`. |
| `WILL_ENTER_BACKGROUND` | `13` | The app is about to be suspended, mostly on mobile. Audio is already paused; save here. |
| `DID_ENTER_BACKGROUND` | `14` | The app was suspended. |
| `WILL_ENTER_FOREGROUND` | `15` | The app is about to resume. |
| `DID_ENTER_FOREGROUND` | `16` | The app resumed. Audio is already resumed. |
| `LOW_MEMORY` | `17` | The OS is low on memory. |
| `TERMINATING` | `18` | The OS is closing the app. |
| `SCRIPT_RELOADED` | `19` | A Lua script was reloaded. Zig games only; Python games never see it. |

## `InputDevice`

A kind of input device, from [`App.last_device`](page:python-api/app#h3-app-last-device).

| Name | Value | Description |
|---|---|---|
| `KEYBOARD` | `0` | A key was pressed. |
| `MOUSE` | `1` | A real mouse moved or clicked. |
| `GAMEPAD` | `2` | A gamepad was used. |
| `TOUCH` | `3` | The screen was touched. |

## `Ease`

An easing curve, for [`pixzig.easing`](page:python-api/easing) and [`pixzig.sequence`](page:python-api/sequence).

`_IN` curves start slow, `_OUT` curves end slow and `_IN_OUT` curves do both. `BACK_*` and `ELASTIC_OUT` overshoot before settling.

| Name | Value | Description |
|---|---|---|
| `LINEAR` | `0` | Constant speed. |
| `QUAD_IN` | `1` | Quadratic, starting slow. |
| `QUAD_OUT` | `2` | Quadratic, ending slow. |
| `QUAD_IN_OUT` | `3` | Quadratic, slow at both ends. |
| `CUBIC_IN` | `4` | Cubic, starting slow. |
| `CUBIC_OUT` | `5` | Cubic, ending slow. |
| `CUBIC_IN_OUT` | `6` | Cubic, slow at both ends. |
| `SINE_IN` | `7` | Sine, starting slow. |
| `SINE_OUT` | `8` | Sine, ending slow. |
| `SINE_IN_OUT` | `9` | Sine, slow at both ends. |
| `BACK_IN` | `10` | Pulls back below 0 before going. |
| `BACK_OUT` | `11` | Overshoots past 1 and settles. |
| `ELASTIC_OUT` | `12` | Overshoots and wobbles into place. |
| `BOUNCE_OUT` | `13` | Bounces off 1 like a dropped ball. |

## `BlendMode`

How draws combine with what's behind them, for [`App.set_blend`](page:python-api/app#h3-app-set-blend).

| Name | Value | Description |
|---|---|---|
| `ALPHA` | `0` | Normal transparency, the default. |
| `ADDITIVE` | `1` | Adds the color, brightening: glows, fire, lasers. |
| `MULTIPLY` | `2` | Multiplies what's behind by the color, darkening: shadows, tinting. |
| `PREMULTIPLIED` | `3` | For colors already multiplied by their alpha, such as a render target cleared transparent. |

## `TextAlign`

Which point of the text a draw's x names, for [`Text.draw`](page:python-api/text#h3-text-draw).

| Name | Value | Description |
|---|---|---|
| `LEFT` | `0` | x is the left edge. |
| `CENTER` | `1` | x is the middle. |
| `RIGHT` | `2` | x is the right edge. |

## `TargetFilter`

How a render target is sampled when drawn scaled, for [`App.create_render_target`](page:python-api/app#h3-app-create-render-target).

| Name | Value | Description |
|---|---|---|
| `NEAREST` | `0` | Hard pixel edges, for low-resolution pixel art. |
| `LINEAR` | `1` | Smooth. |
