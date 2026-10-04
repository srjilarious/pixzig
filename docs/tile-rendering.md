# Tile Rendering

Pixzig loads Tiled `.tmx` maps and draws them with `TileMapRenderer`. `GridRenderer` sits alongside it as a debug overlay, and one older renderer is still reachable while it is on its way out.

## Loading a Map

Maps load through `ResourceManager` like other assets:

```zig
_ = try eng.resources.loadTileMap("level1a", "assets/level1a.tmx");
```

A relative path like `assets/level1a.tmx` resolves against the executable's
own directory, not the current working directory -- see
[Asset Manifest](assets.md#asset-paths).

That is usually the last you see of the handle: `TileMapRenderer` takes the
map by name and holds its own reference. When something else needs the map
data, `acquireTileMap` gives you a ref-counted handle of your own (release it
in `deinit`), and `getTileMap` a borrowed one.

## Choosing a Renderer

| Renderer | Use for | Notes |
|---|---|---|
| `TileMapRenderer` | Whole-map rendering | Chunked, one chunked layer renderer per map layer; supports z-order and parallax via layer properties |
| `GridRenderer` | Debug grid lines over a map | Not a tile renderer — draws colored cell borders for a given map/tile size, independent of any `TileMap`/`TileLayer` |
| `deprecated.TiledLayerRenderer` | A single dynamically-updated overlay layer | On its way out: one full-map vertex buffer per layer with `u16` indices, so it overflows on large maps |

### TileMapRenderer

Built from the name the map was loaded under, and works the rest out itself: it acquires the map handle, borrows the built-in texture shader, and loads each layer's tileset image -- the `<image source>` in the `.tmx` -- as a texture. Nothing else is passed in, and the render calls take only a camera and a viewport.

```zig
_ = try eng.resources.loadTileMap("level1a", "assets/level1a.tmx");

var mapRenderer = try tile.TileMapRenderer.init(alloc, &eng.resources, "level1a");
defer mapRenderer.deinit();

// Each frame:
mapRenderer.render(&camera, &eng.viewport);
```

Internally it splits each layer into fixed-size chunks (32x32 tiles) and culls chunks outside the camera's viewport. Chunks rebuild lazily as they come into view, so a full-map hot reload doesn't stall a frame.

#### Tileset textures

Each layer draws from its own tileset's image, so a map with more than one tileset renders correctly (within the one-tileset-per-layer limit below).

A tileset image is registered under its **base name**: `<image source="../art/tiles.png">` becomes the texture `tiles`. If a texture is already registered under that name, it is reused rather than read off disk again -- which is also how a map built in code rather than loaded from a `.tmx` names its texture:

```zig
_ = try eng.resources.loadTexture("tiles", "assets/tiles.png");

var tileset = try TileSet.initEmpty(alloc, tileSize, textureSize, tileCount);
tileset.imageSource = try alloc.dupe(u8, "tiles"); // matches the loaded name
// ... build layers, then:
_ = try eng.resources.addTileMap("generated", map); // takes ownership of the map
```

Otherwise the path is read relative to the `.tmx` it came from, so the `source` attribute must be correct as Tiled wrote it. A layer whose tileset image can't be resolved fails `init`; a layer with no tileset at all simply draws nothing.

#### Draw order and parallax

Per-layer draw order and parallax scrolling are read from Tiled custom properties set on the layer:

| Property | Type | Default | Effect |
|---|---|---|---|
| `z` | float | `0.0` | Draw order; lower z renders first |
| `parallax_x` | float | `1.0` | Horizontal scroll factor relative to the camera |
| `parallax_y` | float | `1.0` | Vertical scroll factor relative to the camera |

Layers are sorted by `z` ascending at init time. Use `render()` to draw every layer in order, `renderLayersBelow(z)` / `renderLayersAbove(z)` to interleave tile layers with your own draw calls, or `renderLayerNamed(name)` / `renderLayer(index)` for one layer on its own:

```zig
mapRenderer.renderLayersBelow(1.0, &camera, &eng.viewport);
// draw sprites/objects here
mapRenderer.renderLayersAbove(1.0, &camera, &eng.viewport);
```

#### Hot reload

Every render call picks up a reloaded `.tmx` first and rebuilds its layers, including added, removed, or reordered ones -- there is nothing to wire up. Call `sync()` yourself only when you derived something else from the map and need to refresh it; it returns true when a reload happened:

```zig
if (mapRenderer.sync()) {
    // the map changed: recompute camera bounds, respawn objects, ...
    camera.bounds = layerBounds(mapRenderer.tileMap().layerByName("main_layer").?);
}
```

`tileMap()` is the map the renderer currently holds; it is replaced by the reloaded generation on the next `sync`, so read it rather than caching it across frames. `rebuildAll()` forces an immediate rebuild of every chunk when you changed tile data yourself and the layer structure is unchanged.

For a map the game edits as it runs (digging, placing blocks), call `tileChanged(layerIndex, x, y)` after each `TileLayer.setTileData`. It marks only the chunk holding that tile dirty, which rebuilds on its next render:

```zig
layer.setTileData(x, y, tileIdx);
mapRenderer.tileChanged(0, x, y);
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

### deprecated.TiledLayerRenderer

The original single-layer renderer, kept under `tile.deprecated` while it is phased out. Still used by `a_star_path_ex.zig` for a path-highlight overlay alongside a `GridRenderer`, but it keeps one full vertex/index buffer per layer with `u16` indices, so it isn't suited to large maps. Build new code against `TileMapRenderer`.

```zig
var layerRenderer = try tile.deprecated.TiledLayerRenderer.init(alloc, shader, texture);
defer layerRenderer.deinit();

try layerRenderer.recreateVertices(tileset, layer);
// ...
try layerRenderer.draw(layer, mvp);
```

## Supported Tiled Subset

- **Layer data encoding:** CSV only. Base64 and compressed (zlib/gzip) tile data are rejected with `error.UnsupportedLayerEncoding`.
- **Multiple tilesets / `firstgid`:** supported for the simple case of one tileset per layer; each layer draws from its own tileset's image. GID-to-tileset resolution picks the tileset with the highest `firstgid <= gid`, but does not validate that the GID is still within that tileset's tile count or before the next tileset's `firstgid` — a corrupt or out-of-range GID can silently resolve to the wrong tile.
- **Layer properties:** loaded into `TileLayer.properties`, including the `z`/`parallax_x`/`parallax_y` properties `TileMapRenderer` reads.

### Not Supported

- **Mixed-tileset layers.** `TileLayer` stores a single `tileset` pointer for the whole layer, so a layer containing GIDs from more than one tileset cannot be represented correctly — per-tile tileset identity is lost. Keep each Tiled layer to a single tileset.
- **External TSX tileset files.** Tileset definitions must be inline in the `.tmx`; a `source`-referenced external `.tsx` is not resolved.
- **Flipped/rotated tile flags.** The horizontal/vertical/diagonal flip bits Tiled stores in the top bits of each GID are not stripped or applied.
- **Image collection tilesets** (one image per tile) and **object templates** are not read.

If your map needs any of the above, preprocess it (e.g. flatten to CSV, split mixed-tileset layers, inline external tilesets) before loading it with Pixzig.
