# Overview

Pixzig for Python: write 2D games against the pixzig engine.

The package talks to a shared-library build of the engine through `ctypes`, so it needs no compiler. Subclass [`App`](page:python-api/app#h2-app), override `update` and `render`, and call `run()`; the app's members (`keyboard`, `text`, `audio` and so on) and its `create_*` methods reach the rest of the engine.

**Example:**

```python
from pixzig import App, Key

class MyGame(App):
    def __init__(self):
        super().__init__("My Game", width=800, height=480)
        self.load_texture("pac", "assets/pac-tiles.png")
        self.player = self.load_sprite("pac")

    def update(self, dt_ms):
        if self.keyboard.pressed(Key.ESCAPE):
            self.quit()

    def render(self, alpha):
        self.render_begin()
        self.player.draw()
        self.render_end()

MyGame().run()
```

## Reference Pages

These pages are generated from the package's docstrings by `tools/gen_py_docs.py`. [Python Bindings](page:python) covers installing the package and how a Python game is put together.

| Page | Covers |
|---|---|
| [App](page:python-api/app) | The base class for a pixzig game written in Python. `App` |
| [Input](page:python-api/input) | Keyboard, mouse, gamepad and touch input, reached through the app. `Finger`, `Keyboard`, `Mouse`, `Touch`, `Gamepad` |
| [Action Maps](page:python-api/action) | Action maps: named actions and axes bound to keys, buttons and sticks. `ActionMap` |
| [Sprites](page:python-api/sprite) | Sprites: a texture region drawn at a position, with an origin, scale and color options. `Rotate`, `Flip`, `Sprite` |
| [Animation](page:python-api/anim) | Sprite-sheet animation. `Actor` |
| [Text](page:python-api/text) | TrueType text, reached as `App.text`. `Text` |
| [Shapes](page:python-api/shapes) | Rectangle drawing, reached as `App.shapes`. `Shapes` |
| [Camera](page:python-api/camera) | A 2D camera for drawing a world larger than the screen. `Camera` |
| [Window](page:python-api/window) | Window and viewport state, reached as `App.window`. `ScalePolicy`, `Window` |
| [Render Targets](page:python-api/render_target) | Offscreen images to draw into, then draw like a texture. `RenderTarget` |
| [Audio](page:python-api/audio) | Sound effects, music and generated audio, reached as `App.audio`. `Bus`, `Audio` |
| [Tile Maps](page:python-api/tilemap) | Tiled maps: drawing them and reading or editing their data. `TileFlags`, `TileObject`, `TileMapRenderer` |
| [Asset Manifests](page:python-api/manifest) | Asset manifests: a game's assets listed in one JSON file, in groups. `AssetManifest` |
| [Events](page:python-api/event) | Engine events: window, drag-and-drop, gamepad hot-plug and app lifecycle. `Event` |
| [Constants](page:python-api/constants) | Key, mouse, gamepad, event, easing, blend and text codes. `Key`, `MouseButton`, `GamepadButton`, `GamepadAxis`, `MouseAxis`, `EventKind`, ... |
| [pixzig.sequence](page:python-api/sequence) | Sequences: scripted moments written as generators. `Step`, `SequencePlayer` |
| [pixzig.states](page:python-api/states) | A stack of game states, like `GameStateMgr` on the Zig side. `State`, `StateStack` |
| [pixzig.collision](page:python-api/collision) | Collision tests between simple shapes, the engine's own `pixzig.collision`. `Overlap`, `SegmentHit` |
| [pixzig.color](page:python-api/color) | Color helpers, like `Color` on the Zig side. `rgb`, `hex`, `with_alpha`, `lerp` |
| [pixzig.easing](page:python-api/easing) | Easing curves, the engine's own `Ease`. `ease`, `tween` |
| [pixzig.save](page:python-api/save) | Saves and settings, like `pixzig.save` on the Zig side, with JSON in place of ZON. `pref_path`, `write_file_atomic`, `save_json`, `load_json` |
| [pixzig.paths](page:python-api/paths) | How the Python bindings resolve asset paths. `AssetPaths` |

## `Error`

Subclass of `Exception`.

Raised when a pixzig engine call fails.

The message is the engine's own error, e.g. `"FileNotFound"` or a shader's compile log. Using a sprite, actor or other object after it or its app was destroyed raises it too.
