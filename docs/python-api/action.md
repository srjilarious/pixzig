# Action Maps

Module `pixzig.action`. Generated from its docstrings by `tools/gen_py_docs.py`.

Action maps: named actions and axes bound to keys, buttons and sticks.

Game code asks "is the player jumping?" instead of "is Space down?". One
action can have a key and a gamepad button at once, and players can rebind
them. Create a map with [`App.create_action_map`](page:python-api/app#h3-app-create-action-map).

Several bindings on one action are OR'ed together; several on one axis add
up, so a keyboard and a stick can both drive `move_x`. Action and axis names
are any strings, assigned to the engine's slots the first time a `bind_*`
call names them. There are 64 action slots and 32 axis slots.

**Example:**

```python
actions = app.create_action_map()
actions.bind_key("jump", Key.SPACE)
actions.bind_gamepad_button("jump", GamepadButton.A)
actions.bind_axis_buttons("move_x", Key.A, Key.D)

# Once per update tick:
actions.update()
if actions.pressed("jump"):
    hero.jump()
dx = actions.axis("move_x")
```

## `ActionMap`

Named actions and axes bound to physical inputs.

Create one with [`App.create_action_map`](page:python-api/app#h3-app-create-action-map), bind it once, then call [`update`](page:python-api/action#h3-actionmap-update)
at the top of every [`update`](page:python-api/action#h3-actionmap-update) tick before querying it.

### `ActionMap.bind_key`

```python
bind_key(action: str, key: int) -> None
```

Binds a keyboard key to an action.

| Argument | Type | Description |
|---|---|---|
| `action` | `str` | The action's name. |
| `key` | `int` | A [`Key`](page:python-api/constants#h2-key). |

**Raises:**

- `pixzig.Error`: All 64 action slots are taken, or the map was destroyed.

### `ActionMap.bind_mouse_button`

```python
bind_mouse_button(action: str, button: int) -> None
```

Binds a mouse button to an action.

| Argument | Type | Description |
|---|---|---|
| `action` | `str` | The action's name. |
| `button` | `int` | A [`MouseButton`](page:python-api/constants#h2-mousebutton). |

**Raises:**

- `pixzig.Error`: All 64 action slots are taken, or the map was destroyed.

### `ActionMap.bind_gamepad_button`

```python
bind_gamepad_button(action: str, button: int) -> None
```

Binds a gamepad button to an action. It reads gamepad slot 0.

| Argument | Type | Description |
|---|---|---|
| `action` | `str` | The action's name. |
| `button` | `int` | A [`GamepadButton`](page:python-api/constants#h2-gamepadbutton). |

**Raises:**

- `pixzig.Error`: All 64 action slots are taken, or the map was destroyed.

### `ActionMap.bind_axis_buttons`

```python
bind_axis_buttons(axis: str, negative_key: int, positive_key: int) -> None
```

Binds a pair of keys to an axis, reading -1, 0 or 1.

| Argument | Type | Description |
|---|---|---|
| `axis` | `str` | The axis's name. |
| `negative_key` | `int` | The [`Key`](page:python-api/constants#h2-key) that pushes it toward -1. |
| `positive_key` | `int` | The [`Key`](page:python-api/constants#h2-key) that pushes it toward 1. |

**Raises:**

- `pixzig.Error`: All 32 axis slots are taken, or the map was destroyed.

### `ActionMap.bind_axis_gamepad`

```python
bind_axis_gamepad(axis: str, gamepad_axis: int, deadzone: float = 0.18) -> None
```

Binds a gamepad stick or trigger axis to an axis. It reads gamepad slot 0.

| Argument | Type | Default | Description |
|---|---|---|---|
| `axis` | `str` |  | The axis's name. |
| `gamepad_axis` | `int` |  | A [`GamepadAxis`](page:python-api/constants#h2-gamepadaxis). |
| `deadzone` | `float` | `0.18` | Readings closer to center than this count as 0. A stick's is measured on the whole stick, both axes together, so diagonals stay smooth; a trigger's on its own. |

**Raises:**

- `pixzig.Error`: All 32 axis slots are taken, or the map was destroyed.

### `ActionMap.bind_axis_mouse`

```python
bind_axis_mouse(
    axis: str,
    mouse_axis: int,
    sensitivity: float = 1.0,
    clamp: float = 1.0,
) -> None
```

Binds mouse movement to an axis, for mouse look.

| Argument | Type | Default | Description |
|---|---|---|---|
| `axis` | `str` |  | The axis's name. |
| `mouse_axis` | `int` |  | A [`MouseAxis`](page:python-api/constants#h2-mouseaxis). |
| `sensitivity` | `float` | `1.0` | Scales the tick's movement, in window coordinates. |
| `clamp` | `float` | `1.0` | The largest value the axis reports, either way. |

**Raises:**

- `pixzig.Error`: All 32 axis slots are taken, or the map was destroyed.

### `ActionMap.update`

```python
update() -> None
```

Reads this tick's input into the map. Call it once per [`update`](page:python-api/action#h3-actionmap-update), first.

### `ActionMap.up`

```python
up(action: str) -> bool
```

Whether an action is not held.

| Argument | Type | Description |
|---|---|---|
| `action` | `str` | A bound action's name. |

**Returns:** True when none of its bindings are held.

**Raises:**

- `pixzig.Error`: Nothing has been bound to that name.

### `ActionMap.down`

```python
down(action: str) -> bool
```

Whether an action is held.

| Argument | Type | Description |
|---|---|---|
| `action` | `str` | A bound action's name. |

**Returns:** True while any of its bindings is held.

**Raises:**

- `pixzig.Error`: Nothing has been bound to that name.

### `ActionMap.pressed`

```python
pressed(action: str) -> bool
```

Whether an action was pressed this tick.

| Argument | Type | Description |
|---|---|---|
| `action` | `str` | A bound action's name. |

**Returns:** True for exactly one tick, the one it went down on.

**Raises:**

- `pixzig.Error`: Nothing has been bound to that name.

### `ActionMap.released`

```python
released(action: str) -> bool
```

Whether an action was released this tick.

| Argument | Type | Description |
|---|---|---|
| `action` | `str` | A bound action's name. |

**Returns:** True for exactly one tick, the one it went up on.

**Raises:**

- `pixzig.Error`: Nothing has been bound to that name.

### `ActionMap.axis`

```python
axis(axis: str) -> float
```

Reads an axis.

| Argument | Type | Description |
|---|---|---|
| `axis` | `str` | A bound axis's name. |

**Returns:** The sum of its bindings, from -1 to 1 for keys and sticks.

**Raises:**

- `pixzig.Error`: Nothing has been bound to that name.

### `ActionMap.destroy`

```python
destroy() -> None
```

Frees the map now instead of when the app shuts down.

Calling it twice does nothing. Using the map afterwards raises.
