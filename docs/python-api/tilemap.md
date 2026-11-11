# Tile Maps

Module `pixzig.tilemap`. Generated from its docstrings by `tools/gen_py_docs.py`.

Tiled maps: drawing them and reading or editing their data.

Load a map with `App.load_tilemap(name, path)`, then create a renderer with `App.create_tilemap_renderer(map_name)`; it finds the tileset image named in the `.tmx` itself. Besides drawing, [`TileMapRenderer`](page:python-api/tilemap#h2-tilemaprenderer) reads and writes tiles, reports per-tile collision flags and properties, converts between tile and world coordinates, and walks Tiled object layers.

`layer_index` and `group_index` arguments are indices into the map's layer and object group lists; look one up by name with `layer_index("name")` or `object_group_index("name")`. Tile values are 0-based tileset indices, with -1 for no tile.

**Example:**

```python
self.load_tilemap("level1", "assets/level1.tmx")
self.map = self.create_tilemap_renderer("level1")
walls = self.map.layer_index("walls")
w, h = self.map.pixel_size(walls)
self.camera.set_bounds(0, 0, w, h)

group = self.map.object_group_index("spawns")
player = self.map.object_by_name(group, "player")
self.hero.sprite.set_pos(player.x, player.y)
```

## `TileFlags`

Subclass of `IntFlag`.

Collision and behavior flags on a tile, from [`TileMapRenderer.tile_flags`](page:python-api/tilemap#h3-tilemaprenderer-tile-flags).

They come from the `blocks` and `kills` custom properties on tileset tiles in Tiled, and match the engine's core tile flags.

| Name | Value | Description |
|---|---|---|
| `NONE` | `0` | No flags. |
| `BLOCKS_LEFT` | `1` | Solid from the left (`blocks = left`). |
| `BLOCKS_TOP` | `2` | Solid from above (`blocks = top`); a one-way platform. |
| `BLOCKS_RIGHT` | `4` | Solid from the right (`blocks = right`). |
| `BLOCKS_BOTTOM` | `8` | Solid from below (`blocks = bottom`). |
| `BLOCKS_ALL` | `15` | Solid from every side (`blocks = all`). |
| `KILLS` | `16` | Deadly (`kills = true`). |

## `TileObject`

One object from a Tiled object layer.

| Attribute | Description |
|---|---|
| `index` | Its index in the group, for `object_property`. |
| `id` | Its Tiled object id. |
| `gid` | The tile it shows, for tile objects; 0 otherwise. |
| `x` | The left edge, in map pixels. |
| `y` | The top edge, in map pixels. |
| `w` | The width, in pixels. |
| `h` | The height, in pixels. |
| `name` | Its name in Tiled, or "". |
| `class_` | Its class in Tiled (or the older `type`), or "". |

## `TileMapRenderer`

Draws a Tiled map and gives access to its data.

Create one with [`App.create_tilemap_renderer`](page:python-api/app#h3-app-create-tilemap-renderer). It only draws the parts of the map the camera can see. Give layers a `z` float property in Tiled to draw some behind your sprites and some in front with [`render_below`](page:python-api/tilemap#h3-tilemaprenderer-render-below) and [`render_above`](page:python-api/tilemap#h3-tilemaprenderer-render-above).

### `TileMapRenderer.pixel_size`

```python
pixel_size(layer_index: int)
```

A layer's size in pixels, e.g. for a camera's bounds.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer. |

**Returns:** The `(width, height)`.

### `TileMapRenderer.render`

```python
render(camera: Camera) -> None
```

Draws every layer in `z` order. Call it inside a world render pass.

| Argument | Type | Description |
|---|---|---|
| `camera` | `Camera` | The [`Camera`](page:python-api/camera#h2-camera) the pass draws through. |

### `TileMapRenderer.render_below`

```python
render_below(camera: Camera, z: float) -> None
```

Draws the layers whose `z` property is below a threshold: the background.

| Argument | Type | Description |
|---|---|---|
| `camera` | `Camera` | The [`Camera`](page:python-api/camera#h2-camera) the pass draws through. |
| `z` | `float` | The threshold. |

### `TileMapRenderer.render_above`

```python
render_above(camera: Camera, z: float) -> None
```

Draws the layers whose `z` property is at or above a threshold: the foreground.

| Argument | Type | Description |
|---|---|---|
| `camera` | `Camera` | The [`Camera`](page:python-api/camera#h2-camera) the pass draws through. |
| `z` | `float` | The threshold. |

### `TileMapRenderer.check_reload`

```python
check_reload() -> bool
```

Reloads the map if its file changed on disk. Call it once per frame.

Only debug engine builds watch files.

**Returns:** True when it reloaded, so the game can re-read [`pixel_size`](page:python-api/tilemap#h3-tilemaprenderer-pixel-size) for camera bounds or anything else it took from the map.

### `TileMapRenderer.layer_count`

```python
layer_count() -> int
```

How many tile layers the map has.

### `TileMapRenderer.layer_index`

```python
layer_index(name: str) -> int
```

Looks a tile layer up by name.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The layer's name in Tiled. |

**Returns:** The index of the first layer with that name, or -1.

### `TileMapRenderer.layer_size`

```python
layer_size(layer_index: int)
```

A layer's size in tiles.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer. |

**Returns:** The `(width, height)`.

### `TileMapRenderer.tile_size`

```python
tile_size(layer_index: int)
```

The size of one tile in a layer.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer. |

**Returns:** The `(width, height)` in pixels.

### `TileMapRenderer.get_tile`

```python
get_tile(layer_index: int, tx: int, ty: int) -> int
```

Reads a tile.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer. |
| `tx` | `int` | The tile column. |
| `ty` | `int` | The tile row. |

**Returns:** The tileset index, or -1 for an empty cell or one outside the layer.

### `TileMapRenderer.set_tile`

```python
set_tile(layer_index: int, tx: int, ty: int, value: int) -> None
```

Changes a tile. Cells outside the layer are ignored.

Call [`refresh`](page:python-api/tilemap#h3-tilemaprenderer-refresh) once after a batch of edits to make them visible.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer. |
| `tx` | `int` | The tile column. |
| `ty` | `int` | The tile row. |
| `value` | `int` | The tileset index, or -1 to clear the cell. |

### `TileMapRenderer.refresh`

```python
refresh() -> None
```

Makes [`set_tile`](page:python-api/tilemap#h3-tilemaprenderer-set-tile) edits visible.

Drawn chunks are marked stale and rebuilt as they come into view.

### `TileMapRenderer.tile_flags`

```python
tile_flags(layer_index: int, tx: int, ty: int) -> TileFlags
```

A tile's collision and behavior flags.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer. |
| `tx` | `int` | The tile column. |
| `ty` | `int` | The tile row. |

**Returns:** The [`TileFlags`](page:python-api/tilemap#h2-tileflags).

### `TileMapRenderer.is_blocked`

```python
is_blocked(layer_index: int, tx: int, ty: int) -> bool
```

Whether a tile is solid from every side (`TileFlags.BLOCKS_ALL`).

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer. |
| `tx` | `int` | The tile column. |
| `ty` | `int` | The tile row. |

**Returns:** True for a wall.

### `TileMapRenderer.move_x`

```python
move_x(
    layer_index: int,
    x: float,
    y: float,
    w: float,
    h: float,
    dx: float,
    mask: TileFlags = TileFlags.BLOCKS_ALL,
)
```

Moves a box sideways, stopping flush against the first solid tile.

This is the engine's tile mover (`tile.Mover` in Zig). Move one axis at a time, [`move_x`](page:python-api/tilemap#h3-tilemaprenderer-move-x) then [`move_y`](page:python-api/tilemap#h3-tilemaprenderer-move-y), so a box slides along walls and floors instead of sticking to them.

| Argument | Type | Default | Description |
|---|---|---|---|
| `layer_index` | `int` |  | The layer to collide with. |
| `x` | `float` |  | The box's left edge, in world pixels. |
| `y` | `float` |  | The box's top edge. |
| `w` | `float` |  | The box's width. |
| `h` | `float` |  | The box's height. |
| `dx` | `float` |  | How far to move; negative moves left. |
| `mask` | `TileFlags` | `TileFlags.BLOCKS_ALL` | Which tile flags block it. The default is tiles that block every side. |

**Returns:** A tuple `(new_x, hit)`: the box's new left edge, and whether a tile stopped it short.

### `TileMapRenderer.move_y`

```python
move_y(
    layer_index: int,
    x: float,
    y: float,
    w: float,
    h: float,
    dy: float,
    mask: TileFlags = TileFlags.BLOCKS_ALL,
)
```

Moves a box up or down, stopping flush against the first solid tile.

See [`move_x`](page:python-api/tilemap#h3-tilemaprenderer-move-x).

| Argument | Type | Default | Description |
|---|---|---|---|
| `layer_index` | `int` |  | The layer to collide with. |
| `x` | `float` |  | The box's left edge, in world pixels. |
| `y` | `float` |  | The box's top edge. |
| `w` | `float` |  | The box's width. |
| `h` | `float` |  | The box's height. |
| `dy` | `float` |  | How far to move; negative moves up. |
| `mask` | `TileFlags` | `TileFlags.BLOCKS_ALL` | Which tile flags block it. The default is tiles that block every side. |

**Returns:** A tuple `(new_y, hit)`: the box's new top edge, and whether a tile stopped it short. Moving down, a hit means it landed.

### `TileMapRenderer.tile_property`

```python
tile_property(layer_index: int, tx: int, ty: int, name: str) -> str
```

Reads a custom property on a tile's tileset entry.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer. |
| `tx` | `int` | The tile column. |
| `ty` | `int` | The tile row. |
| `name` | `str` | The property's name. |

**Returns:** The value as a string, or "" when it isn't set.

### `TileMapRenderer.world_to_tile`

```python
world_to_tile(layer_index: int, wx: float, wy: float)
```

The tile that contains a world point.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer, for its tile size. |
| `wx` | `float` | The world x, in pixels. |
| `wy` | `float` | The world y, in pixels. |

**Returns:** The `(tx, ty)`.

### `TileMapRenderer.tile_to_world`

```python
tile_to_world(layer_index: int, tx: int, ty: int)
```

Where a tile's top-left corner is in the world.

| Argument | Type | Description |
|---|---|---|
| `layer_index` | `int` | The layer, for its tile size. |
| `tx` | `int` | The tile column. |
| `ty` | `int` | The tile row. |

**Returns:** The `(x, y)` in world pixels.

### `TileMapRenderer.object_group_count`

```python
object_group_count() -> int
```

How many object layers the map has.

### `TileMapRenderer.object_group_index`

```python
object_group_index(name: str) -> int
```

Looks an object layer up by name.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The layer's name in Tiled. |

**Returns:** The index of the first object group with that name, or -1.

### `TileMapRenderer.object_count`

```python
object_count(group_index: int) -> int
```

How many objects are in an object group.

| Argument | Type | Description |
|---|---|---|
| `group_index` | `int` | The object group. |

**Returns:** The count.

### `TileMapRenderer.object_index`

```python
object_index(group_index: int, name: str) -> int
```

Looks an object up by name.

| Argument | Type | Description |
|---|---|---|
| `group_index` | `int` | The object group. |
| `name` | `str` | The object's name in Tiled. |

**Returns:** The index of the first object with that name, or -1.

### `TileMapRenderer.object_by_name`

```python
object_by_name(group_index: int, name: str)
```

Finds an object by name, e.g. a spawn point.

| Argument | Type | Description |
|---|---|---|
| `group_index` | `int` | The object group. |
| `name` | `str` | The object's name in Tiled. |

**Returns:** The first [`TileObject`](page:python-api/tilemap#h2-tileobject) with that name, or None.

### `TileMapRenderer.object`

```python
object(group_index: int, obj_index: int)
```

Reads one object.

| Argument | Type | Description |
|---|---|---|
| `group_index` | `int` | The object group. |
| `obj_index` | `int` | The object's index in the group. |

**Returns:** The [`TileObject`](page:python-api/tilemap#h2-tileobject), or None when the index is out of range.

### `TileMapRenderer.objects`

```python
objects(group_index: int)
```

Iterates the objects in an object group.

| Argument | Type | Description |
|---|---|---|
| `group_index` | `int` | The object group. |

**Yields:** Each [`TileObject`](page:python-api/tilemap#h2-tileobject) in order.

### `TileMapRenderer.object_property`

```python
object_property(group_index: int, obj_index: int, name: str) -> str
```

Reads a custom property on an object.

| Argument | Type | Description |
|---|---|---|
| `group_index` | `int` | The object group. |
| `obj_index` | `int` | The object's index in the group (`TileObject.index`). |
| `name` | `str` | The property's name. |

**Returns:** The value as a string, or "" when it isn't set.

### `TileMapRenderer.destroy`

```python
destroy() -> None
```

Frees the renderer now instead of when the app shuts down.

The map itself stays loaded. Calling it twice does nothing.
