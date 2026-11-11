# Window

Module `pixzig.window`. Generated from its docstrings by `tools/gen_py_docs.py`.

Window and viewport state, reached as `App.window`.

There are three coordinate spaces:

* **Window**: OS window coordinates, what `mouse.raw_pos` reports.
* **Framebuffer**: real pixels drawn, the window size times the display's scale on HiDPI screens.
* **Logical**: the game resolution passes draw in. It equals the framebuffer size unless `App(..., logical_size=...)` set one.

## `ScalePolicy`

How the logical game resolution maps onto the window.

Pass one to `App(..., scale_policy=...)` alongside a `logical_size`; without one it has no effect, since logical space then is the framebuffer. Mirrors [`ScalePolicy`](page:python-api/window#h2-scalepolicy) in src/pixzig/window.zig.

| Name | Value | Description |
|---|---|---|
| `STRETCH` | `0` | Fill the window, ignoring the aspect ratio. |
| `FIT` | `1` | Scale evenly so the whole game fits, with black bars on two sides when the aspect ratios differ. |
| `FILL` | `2` | Scale evenly to cover the window, cropping what doesn't fit. |
| `INTEGER_FIT` | `3` | `FIT` by whole multiples only, so pixel art stays crisp. |
| `INTEGER_FILL` | `4` | `FILL` by whole multiples. |
| `FIXED` | `5` | A constant scale from `App(..., scale_factor=...)`, centered. |

## `Window`

The game window. Reached as `App.window`.

### `Window.size`

```python
size  # property
```

The window's `(width, height)`, in window coordinates.

### `Window.framebuffer_size`

```python
framebuffer_size  # property
```

The drawable framebuffer's `(width, height)`, in pixels.

### `Window.logical_size`

```python
logical_size  # property
```

The logical game resolution's `(width, height)`.

When [`App`](page:python-api/app#h2-app) wasn't given a [`logical_size`](page:python-api/window#h3-window-logical-size), it follows the window, so read it rather than caching it.

### `Window.scale_factor`

```python
scale_factor: float  # property
```

Framebuffer pixels per window coordinate: 1.0 normally, 2.0 on a 2x display.

### `Window.set_title`

```python
set_title(title: str) -> None
```

Changes the window's title.

| Argument | Type | Description |
|---|---|---|
| `title` | `str` | The new title. |

### `Window.set_size`

```python
set_size(width: int, height: int) -> None
```

Resizes the window.

| Argument | Type | Description |
|---|---|---|
| `width` | `int` | The width, in window coordinates (not framebuffer pixels). |
| `height` | `int` | The height, in window coordinates. |

### `Window.fullscreen`

```python
fullscreen: bool  # property
```

Whether the window is fullscreen. Assign to switch.

**Raises:**

- `pixzig.Error`: On assignment, when the platform refused.

### `Window.set_vsync`

```python
set_vsync(enabled: bool) -> None
```

Turns vsync on or off, e.g. from a settings menu.

The starting value comes from `App(..., vsync=...)`. There's no getter: the driver may refuse, so what was asked for isn't necessarily what's in effect.

| Argument | Type | Description |
|---|---|---|
| `enabled` | `bool` | True to wait for the display's refresh. |
