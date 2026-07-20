# Asset Manifest

An asset manifest is a JSON file that describes a game's assets. At runtime, `AssetManifest` loads assets from disk via `ResourceManager` and manages their ref-counted handles.

## Manifest JSON Format

```json
{
  "version": 1,
  "root": "assets",
  "groups": {
    "boot": ["ui_font"],
    "game": ["player_right_1", "tileset"]
  },
  "assets": [
    { "id": "player_right_1", "kind": "atlas",   "path": "pac-tiles" },
    { "id": "tileset",        "kind": "tilemap",  "path": "level1.tmx" },
    { "id": "ui_font",        "kind": "font",     "path": "font.ttf", "font_size": 16.0 },
    { "id": "level_script",   "kind": "raw",      "path": "level.lua" }
  ]
}
```

Asset kinds: `texture`, `atlas`, `font`, `tilemap`, `raw`. A `raw` asset is not loaded into `ResourceManager`; it just signals that the file must be present on disk (useful for Lua scripts and audio files).

The `boot` group is loaded automatically when the manifest is opened. All other groups require an explicit `loadGroup` call.

## Wiring in build.zig

Use `manifestFromFile` if the manifest lives as a JSON file in the repo:

```zig
const buildExample = @import("pixzig").buildExample;
const manifestFromFile = @import("pixzig").manifestFromFile;

const manifest = manifestFromFile(b, "assets/manifest.json");
const game = buildExample(b, target, optimize, pixzig_dep,
    pixzig_dep.module("pixzig"), "my_game", exe_mod, manifest, is_package);
```

Use `manifestFromDef` to define assets inline in `build.zig` with no separate JSON file:

```zig
const manifestFromDef = @import("pixzig").manifestFromDef;

const manifest = manifestFromDef(b, .{
    .root = "assets",
    .groups = &.{
        .{ .name = "game", .assets = &.{ "player_right_1" } },
    },
    .assets = &.{
        .{ .id = "player_right_1", .kind = "atlas", .path = "pac-tiles" },
    },
});
```

## Loading at Runtime

Import `manifest_options` from the build system and open the manifest in `App.init`:

```zig
const manifest_options = @import("manifest_options");
const AssetManifest = pixzig.AssetManifest;

var manifest = if (manifest_options.manifest_path.len > 0)
    try AssetManifest.loadFromFile(alloc, &eng.resources, manifest_options.manifest_path)
else
    try AssetManifest.loadFromJson(alloc, &eng.resources,
        manifest_options.manifest_json, manifest_options.manifest_base_dir);
errdefer manifest.deinit();
```

Then load a group and acquire handles:

```zig
try manifest.loadGroup("game");

self.player_tex = try eng.resources.acquireTexture("player_right_1");
```

Release handles in `deinit`, then deinit the manifest:

```zig
pub fn deinit(self: *App) void {
    self.player_tex.release();
    self.manifest.deinit();
    self.alloc.destroy(self);
}
```

## Dynamic Load and Unload

Groups can be loaded and unloaded at runtime:

```zig
// Unload a group (releases manifest's handles; others still valid until released).
manifest.unloadGroup("game");

// Reload later.
try manifest.loadGroup("game");
self.player_tex = try eng.resources.acquireTexture("player_right_1");
```

The manifest holds one ref per asset per loaded group. The underlying `ManagedResource` only frees the GPU resource once all refs (manifest's and yours) are released.
