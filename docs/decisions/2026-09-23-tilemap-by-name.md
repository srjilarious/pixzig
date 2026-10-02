# 2026-09-23 — Tilemap rendering by name

Resolves item 5.4 of the API ergonomics review: "Tilemaps need the 'by name'
treatment". Landed on `dev` as `dada9a7`.

## What changed

`ChunkedTiledRenderer` became `tile.TileMapRenderer`, built from a
`ResourceManager` and a map name instead of a map pointer, a shader and a
texture:

```zig
var mapRenderer = try tile.TileMapRenderer.init(alloc, &eng.resources, "level1a");
mapRenderer.renderLayersBelow(1.0, &camera, &eng.viewport);
```

## Decisions

**One public renderer, named for what it draws.** `TileMapRenderer` rather
than keeping `ChunkedTiledRenderer` — chunking is an implementation detail,
and the name already matches the Python binding. `ChunkedTiledLayerRenderer`
is no longer exported at all; `TiledLayerRenderer` moved to
`tile.deprecated` so `a_star_path_ex` keeps working while it is phased out;
`GridRenderer` stays where it was, being a debug tool rather than a tile
renderer. The two renderer source files were renamed to match their types.

**The renderer owns the map and heals its own reloads.** It acquires the
`TileMapHandle`, so the render calls no longer take the map, and every render
call picks up a hot-reloaded `.tmx` and rebuilds its layers before drawing.
`sync()` is public and returns true when a reload happened, which is the hook
for state derived from the map (camera bounds, spawn points) — that is all
`tile_load_ex` does now, instead of the handle-dirty/reacquire/reload block it
used to carry.

**Tileset textures resolve per layer, loading on demand.** Each layer draws
from its own `layer.tileset`, so a multi-tileset map is correct rather than
sharing one texture. `ResourceManager.tilesetTexture` keys on the base name of
the tileset's `<image source>` (`../art/tiles.png` → `tiles`): a texture
already registered under that name is reused, otherwise the path is read
relative to the `.tmx`. Reuse-before-load is also what lets a map built in
code name a texture the game loaded itself — it sets `TileSet.imageSource` to
the loaded name. A layer with no tileset gets a renderer with no texture and
draws nothing; a tileset whose image cannot be resolved fails `init` loudly.

Carrying this needed two new fields: `TileSet.imageSource` (the `source`
attribute, as spelled in the file) and `TileMap.sourcePath` (the resolved
`.tmx` path, since image paths are relative to it).

**`ResourceManager.addTileMap`** registers a map built in code, taking
ownership. It exists because the by-name constructor left no way to render a
procedural map, and it lets the renderer tests drive the real path — including
hot reload, which is now just re-registering the same name.

**The C and Python APIs drop the texture name** rather than keeping it as an
optional override: `pz_tilemap_renderer_create(eng, map_name)` and
`create_tilemap_renderer(map_name)`. A breaking change to two example scripts,
taken in exchange for not carrying an escape hatch nothing needs.

## Also

`assets/level1a.tmx` pointed its tileset at
`../zig-out/bin/tile_load_ex/assets/mario_grassish2.png`, a build-output path
that broke opening the map in Tiled. Now that the renderer reads that
attribute it had to be right: it is `mario_grassish2.png`, next to the `.tmx`
(review item 5.3).
