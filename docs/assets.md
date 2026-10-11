# Assets

`eng.resources` is the `ResourceManager`. It loads textures, atlases, fonts, tile maps and shaders, keeps them by name, and reloads them when their files change in a debug build. An asset manifest can load whole groups of them for you.

## Where Files Are Read From

Every relative path you hand the engine resolves against the executable's own directory, not the current working directory. A packaged game finds its files no matter where it's launched from. Absolute paths are used as given.

In a dev build, `buildGame` points that base directory at your source tree instead. `zig build my_game` then reads your real `assets/` folder, and hot reload watches the files you're actually editing. A packaged build (`-Dpackage=true`) copies the assets next to the executable and reads them from there.

## Handles

Every loader returns a pointer to a handle, like `*TextureHandle`. A handle is the resource manager's slot for that name:

- Keep it as long as you like. It's valid until the resource manager shuts down.
- Never free it. The resource manager owns the asset.
- Look it up again by name any time with `getTexture`, `getFontAtlas`, `getTileMap` or `getShader`.

```zig
// In App.init:
self.tiles = try eng.resources.loadTexture("tiles", "assets/tiles.png");

// Anywhere later:
const tiles = try eng.resources.getTexture("tiles");
```

The asset itself lives in `handle.val`, e.g. `tiles.val.size` for a texture's size in pixels.

## Textures

```zig
const tex = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
```

To use part of a texture as its own texture, register a subtexture. The rect is in pixels from the texture's top-left corner:

```zig
_ = try eng.resources.addSubTexture(tex, "guy", RectI.init(32, 32, 32, 32));
var guy = try eng.resources.createSprite("guy");
```

Subtextures work on atlas frames and other subtextures too. `addSubTextureUV` takes UV coordinates (0 to 1) instead.

You can also make textures from data:

- `loadTextureFromBuffer(name, width, height, rgbaBytes)` uploads raw RGBA pixels.
- `createTextureImageFromChars(name, width, height, chars, mapping)` builds a small texture from a string, one character per pixel, with a table mapping characters to colors. It's a quick way to make placeholder art. See `examples/create_texture_ex.zig`.

## Atlases

An atlas is a PNG with many images packed into it, plus a JSON file naming each frame. Load both by their shared base name:

```zig
_ = try eng.resources.loadAtlas("assets/pac-tiles"); // reads pac-tiles.png and pac-tiles.json
const frame = try eng.resources.getTexture("player_right_1");
```

Every frame in the JSON becomes its own texture you can look up by name. Drawing many frames from one atlas keeps the renderer's batch together, so prefer atlases over lots of small textures. `loadAtlasNamed("main_sprites", "assets/pac-tiles")` registers the whole image under a name of your choosing.

The JSON lists each frame's name, size and rect in the image:

```json
{
    "frames": [
        { "name": "dot", "sizePx": { "x": 8, "y": 8 }, "pos": { "l": 0, "t": 8, "r": 8, "b": 16 } }
    ]
}
```

### Packing an Atlas With spack

Pixzig ships a simple sprite packer, `spack`, built with the examples. Give it image files and it writes a PNG and the matching JSON. Frames are named after their file names without the extension:

```sh
zig build
./zig-out/bin/spack/spack -w 256 -h 256 -o assets/sprites art/player_*.png art/enemy_*.png
```

## Fonts, Maps and Shaders

The same pattern covers the other asset types:

| Loader | Handle |
|---|---|
| `loadFontFromTtfFile(name, path, size)` | `*FontAtlasHandle`. See [Text and Fonts](page:text). |
| `loadFontFromBitmap(name, path, cellW, cellH, perRow, chars)` | `*FontAtlasHandle` |
| `loadTileMap(name, path)` | `*TileMapHandle`. See [Tile Maps](page:tile-rendering). |
| `loadShader(name, vertexSrc, fragmentSrc)` | `*ShaderHandle` |

Loading a name that already exists replaces the asset in place, so existing handles see the new one.

## Hot Reload

In a debug build, the resource manager watches the files behind every texture, atlas, TTF font and tile map. When one changes, it reloads it in place between updates: the handle you already hold now holds the new asset. Sprites, actors, text and tile renderers all draw the new version on their next draw with no code from you.

A few details:

- A reloaded image is uploaded into the same GPU texture, so its atlas frames and subtextures keep working.
- An atlas reload checks the new PNG and JSON before touching anything, so a broken file leaves the old atlas drawing.
- A frame that disappears from an atlas's JSON keeps its last image rather than going away, so a handle to it never dangles.
- Release builds don't watch files at all.

If you built something from an asset, like spawn points read from a map, check the handle's `version`. It goes up by one on every reload:

```zig
if (self.map.version != self.mapVersion) {
    self.mapVersion = self.map.version;
    self.rebuildSpawns();
}
```

## Asset Manifests

A manifest lists a game's assets in one place and groups them, so you can load a level's worth of assets with one call. An inline manifest also tells a web build exactly which files to preload. (Packaging copies your whole `assets/` folder either way.)

### Declaring Assets

The simplest way is inline in `build.zig`:

```zig
const pixzig_build = @import("pixzig");

const manifest = pixzig_build.manifestFromDef(b, .{
    .root = "assets",
    .groups = &.{
        .{ .name = "boot", .assets = &.{"ui_font"} },
        .{ .name = "game", .assets = &.{ "sprites", "level1" } },
    },
    .assets = &.{
        .{ .id = "sprites", .kind = "atlas", .path = "sprites" },
        .{ .id = "level1", .kind = "tilemap", .path = "level1.tmx" },
        .{ .id = "ui_font", .kind = "font", .path = "Roboto-Medium.ttf", .font_size = 16 },
        .{ .id = "intro", .kind = "raw", .path = "intro.lua" },
    },
});
```

Pass it as `.manifest` to `buildGame`. If you'd rather keep it in a JSON file, use `manifestFromFile(b, "assets/manifest.json")`:

```json
{
  "version": 1,
  "root": ".",
  "groups": {
    "boot": ["ui_font"],
    "game": ["sprites", "level1"]
  },
  "assets": [
    { "id": "sprites", "kind": "atlas",   "path": "sprites" },
    { "id": "level1",  "kind": "tilemap", "path": "level1.tmx" },
    { "id": "ui_font", "kind": "font",    "path": "Roboto-Medium.ttf", "font_size": 16.0 },
    { "id": "intro",   "kind": "raw",     "path": "intro.lua" }
  ]
}
```

Asset paths are relative to `root`, which for a manifest file is relative to the manifest's own folder. The kinds are `texture`, `atlas`, `font`, `tilemap` and `raw`. Each asset is registered under its `id`, so you look it up with `getTexture("sprites")` and so on. Atlas frames keep their own names. A `font` needs a `font_size`. A `raw` asset isn't loaded by the manifest; it just marks a file the game reads itself, like a Lua script or a sound, so a web build preloads it.

### Loading at Runtime

The easy way is to let the engine open the manifest during init. The build generates a `manifest_options` module for this:

```zig
const AppRunner = pixzig.AppRunner(App, .{
    .manifestOpts = @import("manifest_options"),
});
```

The engine opens the manifest before it sets up the renderer, so fonts in the `boot` group can be the default font (`renderInitOpts.font = .{ .id = "ui_font" }`). It owns the manifest as `eng.manifest` and frees it on shutdown.

The `boot` group loads as soon as the manifest opens. Load the others when you need them:

```zig
try eng.manifest.loadGroup("game");
self.level = try eng.resources.getTileMap("level1");
```

Loading a group that's already loaded does nothing. `unloadGroup("game")` marks it unloaded, so the next `loadGroup` reads its files again and refreshes the assets in place. It doesn't free anything: assets stay in the resource manager until shutdown, so handles never dangle.

If you need to open the manifest yourself, for instance later in `App.init`, use `ManifestSource`:

```zig
const manifest_options = @import("manifest_options");

self.manifest = try pixzig.ManifestSource.fromOptions(manifest_options)
    .load(alloc, &eng.resources);
// ... and in deinit:
self.manifest.deinit();
```

`examples/manifest_ex.zig` loads, unloads and reloads a group at runtime.
