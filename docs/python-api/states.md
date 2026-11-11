# pixzig.states

Module `pixzig.states`. Generated from its docstrings by `tools/gen_py_docs.py`.

A stack of game states, like `GameStateMgr` on the Zig side.

A title screen, the game, and a pause menu over the game are each a state. States are any objects with `update(dt_ms)` and `render(alpha)`; [`State`](page:python-api/states#h2-state) gives empty defaults for those and for the optional hooks:

* `activate` and `deactivate`: the state entered or left the stack.
* `pause` and `resume`: a push covered it, or a pop uncovered it. It stays on the stack in between.

**Example:**

```python
class Playing(State):
    def update(self, dt_ms): ...
    def render(self, alpha): ...

class Paused(State):
    def render(self, alpha):
        self.app.render_begin()
        self.app.text.draw("PAUSED", 160, 100, align=TextAlign.CENTER)
        self.app.render_end()

self.states = StateStack(self.playing)
self.states.push(self.paused)   # draws over the game, which freezes
self.states.pop()               # back to the game

# In App.update and App.render:
self.states.update(dt_ms)
self.states.render(alpha)
```

## `State`

An optional base class for states, where every method does nothing.

Override the ones a state needs.

### `State.update`

```python
update(dt_ms: float) -> None
```

Called each tick while the state updates.

| Argument | Type | Description |
|---|---|---|
| `dt_ms` | `float` | The tick's length, in milliseconds. |

### `State.render`

```python
render(alpha: float) -> None
```

Called each frame while the state renders.

| Argument | Type | Description |
|---|---|---|
| `alpha` | `float` | The interpolation alpha passed to [`App.render`](page:python-api/app#h3-app-render). |

### `State.activate`

```python
activate() -> None
```

Called when the state enters the stack.

### `State.deactivate`

```python
deactivate() -> None
```

Called when the state leaves the stack.

### `State.pause`

```python
pause() -> None
```

Called when a `push` covers the state.

### `State.resume`

```python
resume() -> None
```

Called when a `pop` uncovers the state again.

## `StateStack`

```python
StateStack(initial)
```

The states, bottom first; the top one takes input.

| Argument | Description |
|---|---|
| `initial` | The state to start with. Its `activate` isn't called, like the Zig side. |

### `StateStack.current`

```python
current  # property
```

The state on top of the stack.

### `StateStack.depth`

```python
depth: int  # property
```

How many states are on the stack: 1 when nothing is pushed.

### `StateStack.is_on_stack`

```python
is_on_stack(state) -> bool
```

Whether a state is anywhere on the stack.

| Argument | Description |
|---|---|
| `state` | The state object. |

**Returns:** True when it's on the stack, covered or not.

### `StateStack.set_state`

```python
set_state(state) -> None
```

Replaces the whole stack with one state.

Deactivates every state on it, top first, then activates the new one.

| Argument | Description |
|---|---|
| `state` | The new state. |

### `StateStack.push`

```python
push(state, render_below: bool = True, update_below: bool = False) -> None
```

Lays a state over the current one, e.g. a pause menu over the game.

Pauses the current state and activates the new one.

| Argument | Type | Default | Description |
|---|---|---|---|
| `state` |  |  | The state to push. |
| `render_below` | `bool` | `True` | Render the states below first, so this one draws over them. False for a state that covers the whole screen. |
| `update_below` | `bool` | `False` | Keep updating the states below, for a popup over a live game. False freezes them while this state is on top. |

**Raises:**

- `ValueError`: The state is already on the stack. Nothing changes.

### `StateStack.pop`

```python
pop() -> None
```

Removes the top state, deactivating it and resuming the one below.

**Raises:**

- `ValueError`: Only the bottom state is left; replace it with [`set_state`](page:python-api/states#h3-statestack-set-state).

### `StateStack.update`

```python
update(dt_ms: float) -> None
```

Updates the top state, and the states below it it lets update.

Each state below updates for as long as the state above it was pushed with `update_below`. Lower states update first.

| Argument | Type | Description |
|---|---|---|
| `dt_ms` | `float` | The tick's length, in milliseconds. |

### `StateStack.render`

```python
render(alpha: float = 1.0) -> None
```

Renders the top state, and the states below it it lets render.

Each state below renders for as long as the state above it was pushed with `render_below`. Lower states render first, so the top one draws over them.

| Argument | Type | Default | Description |
|---|---|---|---|
| `alpha` | `float` | `1.0` | The interpolation alpha from [`App.render`](page:python-api/app#h3-app-render). |

### `StateStack.close`

```python
close() -> None
```

Deactivates every state still on the stack, top first.
