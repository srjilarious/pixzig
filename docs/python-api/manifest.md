# Asset Manifests

Module `pixzig.manifest`. Generated from its docstrings by `tools/gen_py_docs.py`.

Asset manifests: a game's assets listed in one JSON file, in groups.

Open one with `App.load_manifest(path)`. Loading a group registers its assets in the engine under their manifest ids, so they're usable straight away by id with [`App.load_sprite`](page:python-api/app#h3-app-load-sprite), [`App.create_tilemap_renderer`](page:python-api/app#h3-app-create-tilemap-renderer) and [`Text.set_font`](page:python-api/text#h3-text-set-font). A group named `boot` loads as soon as the manifest opens.

The kinds are `texture`, `atlas`, `font` (with a `font_size`), `tilemap`, `sound`, `music` and `raw` (a file the game reads itself with [`AssetManifest.read_raw`](page:python-api/manifest#h3-assetmanifest-read-raw)).

**Example:**

A manifest file:

```json
{
  "root": "assets",
  "groups": { "boot": ["ui"], "level1": ["tiles", "level1_map"] },
  "assets": [
    { "id": "ui", "kind": "atlas", "path": "ui" },
    { "id": "tiles", "kind": "texture", "path": "mario_grassish2.png" },
    { "id": "level1_map", "kind": "tilemap", "path": "level1a.tmx" }
  ]
}
```

## `AssetManifest`

An opened asset manifest. Create one with [`App.load_manifest`](page:python-api/app#h3-app-load-manifest).

### `AssetManifest.read_raw`

```python
read_raw(asset_id: str) -> bytes
```

Reads the whole file behind an asset, usually a `raw` one.

The file is read the way the engine reads every asset, so this is the way to load a game's own data files (JSON, text, level data).

| Argument | Type | Description |
|---|---|---|
| `asset_id` | `str` | The asset's id in the manifest. |

**Returns:** The file's contents.

**Raises:**

- `pixzig.Error`: No asset has that id, or its file can't be read.

### `AssetManifest.load_group`

```python
load_group(name: str) -> None
```

Loads every asset in a group.

Loading a group that's already loaded does nothing.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The group's name. |

**Raises:**

- `pixzig.Error`: No group has that name, or one of its assets failed to load.

### `AssetManifest.unload_group`

```python
unload_group(name: str) -> None
```

Marks a group unloaded, so the next [`load_group`](page:python-api/manifest#h3-assetmanifest-load-group) reads its files again.

Nothing is freed: assets stay loaded until the app shuts down, so sprites and renderers using them keep working, and reloading refreshes them in place.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The group's name. |

### `AssetManifest.destroy`

```python
destroy() -> None
```

Closes the manifest now instead of when the app shuts down.

The assets it loaded stay loaded. Calling it twice does nothing.
