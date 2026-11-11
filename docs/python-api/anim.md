# Animation

Module `pixzig.anim`. Generated from its docstrings by `tools/gen_py_docs.py`.

Sprite-sheet animation.

An [`Actor`](page:python-api/anim#h2-actor) owns a [`Sprite`](page:python-api/sprite#h2-sprite) (`actor.sprite`) and plays named states on it, like `"walk_left"` or `"idle"`, each state playing a frame sequence. The sequences and states live in one library shared by the whole app. Build it from a JSON file with [`App.load_anim_file`](page:python-api/app#h3-app-load-anim-file), or in code with [`App.create_sequence`](page:python-api/app#h3-app-create-sequence), [`App.add_frame`](page:python-api/app#h3-app-add-frame) and [`App.add_anim_state`](page:python-api/app#h3-app-add-anim-state), then add states to each actor.

**Example:**

```python
app.load_texture("hero", "assets/hero.png")
for i in range(4):
    app.create_subtexture("hero", f"hero_walk{i}", i * 16, 0, 16, 16)
app.create_sequence("walk", loop=True)
for i in range(4):
    app.add_frame("walk", f"hero_walk{i}", 120)
app.add_anim_state("walk_right", "walk")
app.add_anim_state("walk_left", "walk", flip=Flip.HORZ)

self.hero = app.create_actor("hero_walk0")
self.hero.add_state("walk_right")
self.hero.add_state("walk_left")

# In update(dt_ms):
self.hero.update(dt_ms)
self.hero.sprite.set_pos(x, y)

# In render(alpha):
self.hero.sprite.draw()
```

## `Actor`

A sprite that plays animation states. Create one with [`App.create_actor`](page:python-api/app#h3-app-create-actor).

| Attribute | Description |
|---|---|
| `sprite` | The [`Sprite`](page:python-api/sprite#h2-sprite) it animates. Move, scale and draw the actor through it. It's freed with the actor. |

### `Actor.add_state`

```python
add_state(name: str) -> None
```

Adds a state from the app's animation library to this actor.

The first state added becomes the current one.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | A state registered with [`App.add_anim_state`](page:python-api/app#h3-app-add-anim-state) or [`App.load_anim_file`](page:python-api/app#h3-app-load-anim-file). |

**Raises:**

- `pixzig.Error`: No state has that name.

### `Actor.set_state`

```python
set_state(name: str) -> None
```

Switches to a state and shows its first frame right away.

Switching to the state the actor is already in does nothing, so it's safe to call every tick.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | A state added with [`add_state`](page:python-api/anim#h3-actor-add-state). |

**Raises:**

- `pixzig.Error`: The actor has no state with that name.

### `Actor.finished`

```python
finished: bool  # property
```

Whether a play-once state with no `next_state` has reached its last frame.

The actor holds that frame until the state changes, which clears this.

### `Actor.update`

```python
update(dt_ms: float) -> None
```

Advances the animation, updating the sprite's frame.

A delta longer than the current frame steps through as many frames as it covers, so animations keep their pace however time arrives.

| Argument | Type | Description |
|---|---|---|
| `dt_ms` | `float` | The time to advance, in milliseconds. |

### `Actor.destroy`

```python
destroy() -> None
```

Frees the actor and its sprite now instead of when the app shuts down.

Calling it twice does nothing. Using the actor afterwards raises.
