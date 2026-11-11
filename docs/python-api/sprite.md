# Sprites

Module `pixzig.sprite`. Generated from its docstrings by `tools/gen_py_docs.py`.

Sprites: a texture region drawn at a position, with an origin, scale and
color options.

Create one with `App.load_sprite(texture_name)`. An actor's sprite is
`actor.sprite`.

## `Rotate`

Subclass of `IntEnum`.

A quarter-turn rotation or flip applied when a sprite is drawn.

The sprite's rect stays the same, so quarter turns are meant for square
sprites. Matches the engine's [`Rotate`](page:python-api/sprite#h2-rotate) enum.

| Name | Value | Description |
|---|---|---|
| `NONE` | `0` | Drawn as is. |
| `ROT90` | `1` | A quarter turn clockwise. |
| `ROT180` | `2` | A half turn. |
| `ROT270` | `3` | Three quarter turns clockwise. |
| `FLIP_HORZ` | `4` | Mirrored left to right. |
| `FLIP_VERT` | `5` | Mirrored top to bottom. |

## `Flip`

Subclass of `IntEnum`.

A flip for an animation frame or state. Matches the engine's [`Flip`](page:python-api/sprite#h2-flip) enum.

A frame's flip and its state's flip combine, and two flips on the same axis
cancel out.

| Name | Value | Description |
|---|---|---|
| `NONE` | `0` | No flip. |
| `HORZ` | `1` | Mirrored left to right. |
| `VERT` | `2` | Mirrored top to bottom. |
| `BOTH` | `3` | Both. |

## `Sprite`

A texture region drawn at a position. Create one with [`App.load_sprite`](page:python-api/app#h3-app-load-sprite).

Positions are floats, so slow movement accumulates smoothly, but the sprite
snaps to a whole pixel when drawn, so it never comes out blurry.

### `Sprite.set_pos`

```python
set_pos(x: float, y: float) -> None
```

Moves the sprite's origin to a point.

The origin is the top-left corner unless [`set_origin`](page:python-api/sprite#h3-sprite-set-origin) moved it.

| Argument | Type | Description |
|---|---|---|
| `x` | `float` | The x, in the pass's coordinates. |
| `y` | `float` | The y. |

### `Sprite.set_origin`

```python
set_origin(x: float, y: float) -> None
```

Sets the pivot that [`set_pos`](page:python-api/sprite#h3-sprite-set-pos) places and scaling grows around.

The sprite stays where it is on screen.

| Argument | Type | Description |
|---|---|---|
| `x` | `float` | The pivot's x in the frame's own pixels; `(8, 16)` is the bottom-center of a 16x16 frame. |
| `y` | `float` | The pivot's y. |

### `Sprite.set_size`

```python
set_size(w: float, h: float) -> None
```

Resizes the sprite on screen, around its origin.

| Argument | Type | Description |
|---|---|---|
| `w` | `float` | The width. |
| `h` | `float` | The height. |

### `Sprite.set_scale`

```python
set_scale(sx: float, sy: float = None) -> None
```

Scales the sprite relative to its frame's size, around its origin.

| Argument | Type | Default | Description |
|---|---|---|---|
| `sx` | `float` |  | The horizontal scale; 2 doubles it and 1 restores it. |
| `sy` | `float` | `None` | The vertical scale. None uses `sx`, for a uniform scale. |

### `Sprite.set_rotate`

```python
set_rotate(rotate: Rotate) -> None
```

Sets a quarter-turn rotation or flip.

| Argument | Type | Description |
|---|---|---|
| `rotate` | `Rotate` | A [`Rotate`](page:python-api/sprite#h2-rotate). |

### `Sprite.set_src_rect`

```python
set_src_rect(x: int, y: int, w: int, h: int) -> None
```

Draws only part of the sprite's frame.

| Argument | Type | Description |
|---|---|---|
| `x` | `int` | The region's left edge, in the texture's pixels. |
| `y` | `int` | The region's top edge. |
| `w` | `int` | The region's width. |
| `h` | `int` | The region's height. |

### `Sprite.set_tint`

```python
set_tint(color) -> None
```

Multiplies the sprite's colors by a color.

| Argument | Description |
|---|---|
| `color` | An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. White clears the tint; an alpha below 255 fades the sprite. |

### `Sprite.clear_tint`

```python
clear_tint() -> None
```

Removes the tint, drawing the sprite in its own colors.

### `Sprite.set_fill`

```python
set_fill(color) -> None
```

Draws the sprite as a solid-color silhouette, keeping its shape.

Use it for a hit flash, a shadow or a selection highlight. It takes
precedence over the tint.

| Argument | Description |
|---|---|
| `color` | An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. The alpha blends between the sprite's own colors (0) and a solid fill (255). None draws the sprite normally again. |

### `Sprite.rect`

```python
rect  # property
```

The sprite's rect on screen, as `(x, y, w, h)`.

### `Sprite.pos`

```python
pos  # property
```

The origin's position, as `(x, y)`: what [`set_pos`](page:python-api/sprite#h3-sprite-set-pos) set.

### `Sprite.size`

```python
size  # property
```

The sprite's size on screen, as `(w, h)`.

### `Sprite.width`

```python
width: float  # property
```

The sprite's width on screen.

### `Sprite.height`

```python
height: float  # property
```

The sprite's height on screen.

### `Sprite.draw`

```python
draw() -> None
```

Draws the sprite. Call it inside a render pass.

### `Sprite.destroy`

```python
destroy() -> None
```

Frees the sprite now instead of when the app shuts down.

An actor's sprite is freed with its actor, so this does nothing for one.
Calling it twice does nothing. Using the sprite afterwards raises.
