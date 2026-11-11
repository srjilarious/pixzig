# Camera

Module `pixzig.camera`. Generated from its docstrings by `tools/gen_py_docs.py`.

A 2D camera for drawing a world larger than the screen.

Create one with [`App.create_camera`](page:python-api/app#h3-app-create-camera) and draw through it with `App.render_begin(camera)`.

## `Camera`

Looks at a point in the world, with zoom and optional bounds.

Its position is the world point shown at the center of the screen.

### `Camera.set_pos`

```python
set_pos(x: float, y: float) -> None
```

Centers the camera on a world point.

| Argument | Type | Description |
|---|---|---|
| `x` | `float` | The world x. |
| `y` | `float` | The world y. |

### `Camera.pos`

```python
pos  # property
```

The world point at the center of the screen, as `(x, y)`.

### `Camera.set_zoom`

```python
set_zoom(zoom: float) -> None
```

Sets the zoom.

| Argument | Type | Description |
|---|---|---|
| `zoom` | `float` | 2.0 shows everything twice as big. The default is 1. |

### `Camera.zoom`

```python
zoom: float  # property
```

The zoom; 2.0 shows everything twice as big.

### `Camera.set_bounds`

```python
set_bounds(l: float, t: float, r: float, b: float) -> None
```

Keeps the camera from showing anything outside a world rect.

Usually the map's size. The camera stops at the edges instead of showing empty space, and centers on the bounds on an axis where the view is bigger than they are.

| Argument | Type | Description |
|---|---|---|
| `l` | `float` | The left edge. |
| `t` | `float` | The top edge. |
| `r` | `float` | The right edge. |
| `b` | `float` | The bottom edge. |

### `Camera.clear_bounds`

```python
clear_bounds() -> None
```

Removes the bounds set with [`set_bounds`](page:python-api/camera#h3-camera-set-bounds).

### `Camera.follow`

```python
follow(
    x: float,
    y: float,
    dt_ms: float,
    deadzone=(0.0, 0.0),
    smoothing: float = None,
) -> None
```

Moves the camera toward a target, such as the player, for one tick.

Call it from `update` with that tick's `dt_ms`. Bounds set with [`set_bounds`](page:python-api/camera#h3-camera-set-bounds) still apply when drawing.

| Argument | Type | Default | Description |
|---|---|---|---|
| `x` | `float` |  | The target's world x. |
| `y` | `float` |  | The target's world y. |
| `dt_ms` | `float` |  | The tick's length, in milliseconds. |
| `deadzone` |  | `(0.0, 0.0)` | The half-size `(w, h)`, in world units, of a box around the camera's center the target can move in without moving the camera. `(0, 0)` keeps the target centered. |
| `smoothing` | `float` | `None` | How fast the camera closes the gap, per second: after one second `exp(-smoothing)` of it remains, so 5 is snappy and 2 is floaty. None jumps straight to the target. |

### `Camera.destroy`

```python
destroy() -> None
```

Frees the camera now instead of when the app shuts down.

Calling it twice does nothing. Using the camera afterwards raises.
