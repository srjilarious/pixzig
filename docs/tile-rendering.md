# Tile Rendering

Pixzig loads Tiled `.tmx` maps and offers a few different renderers for drawing them. `ChunkedTiledRenderer` is the recommended renderer for game maps; the others exist for grid overlays and legacy/simple cases.

## Loading a Map

Maps load through `ResourceManager` like other assets, then are acquired as a ref-counted handle:

```zig
try eng.resources.loadTileMap("level1a", "assets/level1a.tmx");
const map = try eng.resources.acquireTileMap("level1a");
// ...
map.release(); // in deinit
```

## Choosing a Renderer

| Renderer | Use for | Notes |
|---|---|---|
| `ChunkedTiledRenderer` | Whole-map rendering (recommended default) | One `ChunkedTiledLayerRenderer` per map layer; supports z-order and parallax via layer properties |
| `ChunkedTiledLayerRenderer` | A single layer, chunked | Building block used internally by `ChunkedTiledRenderer`; use directly only if you need one layer rendered outside the normal multi-layer flow |
| `TiledLayerRenderer` | Small/simple maps, or a single dynamically-updated layer (e.g. a path-highlight overlay) | Legacy: builds one full-map vertex buffer per layer with `u16` indices, so it can overflow or become expensive on large maps |
| `GridRenderer` | Debug grid lines over a map | Not a tile renderer — draws colored cell borders for a given map/tile size, independent of any `TileMap`/`TileLayer` |

### ChunkedTiledRenderer

Splits each layer into fixed-size chunks (32x32 tiles) and culls chunks outside the camera's viewport. Chunks rebuild lazily as they come into view, so a full-map hot reload doesn't stall a frame.

```zig
const shader = try eng.resources.getShader(pixzig.shaders.TextureShader);
const texture = try eng.resources.getTexture("tiles");
var mapRenderer = try tile.ChunkedTiledRenderer.init(alloc, &map.val, shader, texture);
defer mapRenderer.deinit();

// Each frame:
mapRenderer.render(&map.val, &camera, &eng.viewport);
```

Per-layer draw order and parallax scrolling are read from Tiled custom properties set on the layer:

| Property | Type | Default | Effect |
|---|---|---|---|
| `z` | float | `0.0` | Draw order; lower z renders first |
| `parallax_x` | float | `1.0` | Horizontal scroll factor relative to the camera |
| `parallax_y` | float | `1.0` | Vertical scroll factor relative to the camera |

Layers are sorted by `z` ascending at init time. Use `render()` to draw every layer in order, or `renderLayersBelow(z)` / `renderLayersAbove(z)` to interleave tile layers with your own draw calls (for example, drawing background layers, then game objects, then foreground layers):

```zig
mapRenderer.renderLayersBelow(1.0, &map.val, &camera, &eng.viewport);
// draw sprites/objects here
mapRenderer.renderLayersAbove(1.0, &map.val, &camera, &eng.viewport);
```

After a hot reload, check the map handle's `dirty` flag, reacquire it, and call `reload()` to rebuild renderers for any added/removed/reordered layers (`rebuildAll()` instead if you know the layer structure itself hasn't changed):

```zig
if (map.dirty) {
    map = map.reacquire();
    try mapRenderer.reload(&map.val);
}
```

### TiledLayerRenderer

The original single-layer renderer. Still useful for a small map or a dynamically-updated overlay layer (see `a_star_path_ex.zig`, which uses it for a path-highlight layer alongside a `GridRenderer`), but it keeps one full vertex/index buffer per layer with `u16` indices, so it isn't suited to large maps.

```zig
var layerRenderer = try tile.TiledLayerRenderer.init(alloc, shader, texture);
defer layerRenderer.deinit();

try layerRenderer.recreateVertices(tileset, layer);
// ...
try layerRenderer.draw(layer, mvp);
```

### GridRenderer

Draws debug grid lines sized to a map's dimensions; it does not read a `TileMap` at all:

```zig
var grid = try tile.GridRenderer.init(
    alloc, color_shader,
    .{ .x = MapWidth, .y = MapHeight },
    .{ .x = TileWidth, .y = TileHeight },
    1, // border size in pixels
    Color{ .r = 1, .g = 1, .b = 1, .a = 1 },
);
defer grid.deinit();

grid.draw(mvp);
```

## Supported Tiled Subset

- **Layer data encoding:** CSV only. Base64 and compressed (zlib/gzip) tile data are rejected with `error.UnsupportedLayerEncoding`.
- **Multiple tilesets / `firstgid`:** supported for the simple case of one tileset per layer. GID-to-tileset resolution picks the tileset with the highest `firstgid <= gid`, but does not validate that the GID is still within that tileset's tile count or before the next tileset's `firstgid` — a corrupt or out-of-range GID can silently resolve to the wrong tile.
- **Layer properties:** loaded into `TileLayer.properties`, including the `z`/`parallax_x`/`parallax_y` properties `ChunkedTiledRenderer` reads.

### Not Supported

- **Mixed-tileset layers.** `TileLayer` stores a single `tileset` pointer for the whole layer, so a layer containing GIDs from more than one tileset cannot be represented correctly — per-tile tileset identity is lost. Keep each Tiled layer to a single tileset.
- **External TSX tileset files.** Tileset definitions must be inline in the `.tmx`; a `source`-referenced external `.tsx` is not resolved.
- **Flipped/rotated tile flags.** The horizontal/vertical/diagonal flip bits Tiled stores in the top bits of each GID are not stripped or applied.
- **Image collection tilesets** (one image per tile) and **object templates** are not read.

If your map needs any of the above, preprocess it (e.g. flatten to CSV, split mixed-tileset layers, inline external tilesets) before loading it with Pixzig.
