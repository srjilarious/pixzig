# Input

Module `pixzig.input`. Generated from its docstrings by `tools/gen_py_docs.py`.

Keyboard, mouse, gamepad and touch input, reached through the app.

`App.keyboard`, `App.mouse` and `App.touch` are created with the app;
`App.gamepad(i)` returns a pad slot. The engine latches input once per
update tick, so `pressed` and `released` are true for exactly one tick.
For game controls, an [`ActionMap`](page:python-api/action#h2-actionmap) is usually nicer than reading devices
directly.

## `Finger`

One finger on the screen, from [`Touch.fingers`](page:python-api/input#h3-touch-fingers).

| Attribute | Description |
|---|---|
| `id` | Stays the same from when the finger lands until it lifts. |
| `pos` | Where it is, as `(x, y)` in logical game coordinates, or None over a letterbox bar. |
| `start` | Where it landed, the same way. |
| `on_control` | Whether it landed on a virtual pad control. |

## `Keyboard`

Keyboard state, reached as `App.keyboard`.

Keys are [`Key`](page:python-api/constants#h2-key) values naming physical positions: `Key.W` is where W sits on
a US QWERTY board whatever the layout, so WASD stays under the same fingers
on AZERTY or Dvorak. Read typed text with [`text`](page:python-api/input#h3-keyboard-text).

### `Keyboard.down`

```python
down(key: int) -> bool
```

Whether a key is held.

| Argument | Type | Description |
|---|---|---|
| `key` | `int` | A [`Key`](page:python-api/constants#h2-key). |

**Returns:** True while it's held.

### `Keyboard.pressed`

```python
pressed(key: int) -> bool
```

Whether a key went down this tick.

| Argument | Type | Description |
|---|---|---|
| `key` | `int` | A [`Key`](page:python-api/constants#h2-key). |

**Returns:** True for exactly one tick.

### `Keyboard.released`

```python
released(key: int) -> bool
```

Whether a key went up this tick.

| Argument | Type | Description |
|---|---|---|
| `key` | `int` | A [`Key`](page:python-api/constants#h2-key). |

**Returns:** True for exactly one tick.

### `Keyboard.text`

```python
text() -> str
```

The text typed this tick, for names, chat lines and text fields.

It's already run through the keyboard layout, dead keys and IME, so it's
correct for every language. Only meaningful while `update` is running.

**Returns:** The UTF-8 text, or "" when nothing was typed.

### `Keyboard.shift`

```python
shift: bool  # property
```

Whether either Shift key is held.

### `Keyboard.ctrl`

```python
ctrl: bool  # property
```

Whether either Ctrl key is held.

### `Keyboard.alt`

```python
alt: bool  # property
```

Whether either Alt key is held.

### `Keyboard.super`

```python
super: bool  # property
```

Whether a Super, Windows or Command key is held.

## `Mouse`

Mouse state, reached as `App.mouse`.

### `Mouse.pos`

```python
pos  # property
```

The cursor's position in logical game coordinates, as `(x, y)`.

`(-1, -1)` while the cursor is over a letterbox bar, outside the game area.

### `Mouse.raw_pos`

```python
raw_pos  # property
```

The cursor's position in window coordinates, as `(x, y)`, never clamped.

### `Mouse.scroll`

```python
scroll  # property
```

The scroll wheel's movement this tick, as `(horizontal, vertical)`.

### `Mouse.delta`

```python
delta  # property
```

The mouse's movement this tick in window coordinates, as `(dx, dy)`.

In relative mode it's the unbounded motion, for mouse look.

### `Mouse.down`

```python
down(button: int) -> bool
```

Whether a mouse button is held.

| Argument | Type | Description |
|---|---|---|
| `button` | `int` | A [`MouseButton`](page:python-api/constants#h2-mousebutton). |

**Returns:** True while it's held.

### `Mouse.pressed`

```python
pressed(button: int) -> bool
```

Whether a mouse button went down this tick.

| Argument | Type | Description |
|---|---|---|
| `button` | `int` | A [`MouseButton`](page:python-api/constants#h2-mousebutton). |

**Returns:** True for exactly one tick.

### `Mouse.released`

```python
released(button: int) -> bool
```

Whether a mouse button went up this tick.

| Argument | Type | Description |
|---|---|---|
| `button` | `int` | A [`MouseButton`](page:python-api/constants#h2-mousebutton). |

**Returns:** True for exactly one tick.

### `Mouse.relative`

```python
relative: bool  # property
```

Whether relative (captured) mouse mode is on.

### `Mouse.set_relative`

```python
set_relative(enabled: bool) -> None
```

Turns relative mouse mode on or off.

In relative mode the cursor is hidden and the window edge no longer stops
it, and [`delta`](page:python-api/input#h3-mouse-delta) reports unbounded motion. Good for first-person cameras.

| Argument | Type | Description |
|---|---|---|
| `enabled` | `bool` | True to capture the mouse, False to release it. |

**Raises:**

- `pixzig.Error`: The platform refused.

### `Mouse.show_cursor`

```python
show_cursor(visible: bool) -> None
```

Shows or hides the system cursor. It applies process-wide.

| Argument | Type | Description |
|---|---|---|
| `visible` | `bool` | True to show it. |

## `Touch`

Touchscreen input, reached as `App.touch`.

Positions are in logical game coordinates, the same space as `mouse.pos`,
or None over a letterbox bar.

### `Touch.tapped`

```python
tapped()
```

Where a finger landed this tick, like `mouse.pressed` for touch.

A landing counts the moment the finger touches down, so a tap shorter than a
tick still counts, and so does one that then drags.

**Returns:** The first landing inside the game area as `(x, y)`, or None. See [`taps`](page:python-api/input#h3-touch-taps)
for every landing when several fingers touch down at once.

### `Touch.taps`

```python
taps()
```

Every finger landing this tick inside the game area.

**Returns:** A list of `(x, y)`.

### `Touch.finger_count`

```python
finger_count: int  # property
```

How many fingers are on the screen.

### `Touch.fingers`

```python
fingers()
```

The fingers on the screen right now.

**Returns:** A list of [`Finger`](page:python-api/input#h2-finger).

## `Gamepad`

One gamepad slot. Get it with `App.gamepad(index)`.

Buttons use positional names (`GamepadButton.A` is the bottom face button).
Pads can be plugged in and out while the game runs; `EventKind.GAMEPAD_ADDED`
and `GAMEPAD_REMOVED` arrive through [`App.on_event`](page:python-api/app#h3-app-on-event).

| Attribute | Description |
|---|---|
| `index` | The slot this reads. |

### `Gamepad.connected`

```python
connected: bool  # property
```

Whether a pad is plugged into this slot.

### `Gamepad.down`

```python
down(button: int) -> bool
```

Whether a button is held.

| Argument | Type | Description |
|---|---|---|
| `button` | `int` | A [`GamepadButton`](page:python-api/constants#h2-gamepadbutton). |

**Returns:** True while it's held.

### `Gamepad.pressed`

```python
pressed(button: int) -> bool
```

Whether a button went down this tick.

| Argument | Type | Description |
|---|---|---|
| `button` | `int` | A [`GamepadButton`](page:python-api/constants#h2-gamepadbutton). |

**Returns:** True for exactly one tick.

### `Gamepad.released`

```python
released(button: int) -> bool
```

Whether a button went up this tick.

| Argument | Type | Description |
|---|---|---|
| `button` | `int` | A [`GamepadButton`](page:python-api/constants#h2-gamepadbutton). |

**Returns:** True for exactly one tick.

### `Gamepad.axis`

```python
axis(axis: int) -> float
```

Reads a stick or trigger.

| Argument | Type | Description |
|---|---|---|
| `axis` | `int` | A [`GamepadAxis`](page:python-api/constants#h2-gamepadaxis). |

**Returns:** -1 to 1 for sticks, 0 to 1 for triggers. No deadzone is applied; an
[`ActionMap`](page:python-api/action#h2-actionmap) axis binding adds one.
