# App

Module `pixzig.app`. Generated from its docstrings by `tools/gen_py_docs.py`.

The base class for a pixzig game written in Python.

Subclass [`App`](page:python-api/app#h2-app), override `update` and `render`, and call `run()`. The fixed-timestep loop mirrors pixzig's own `AppRunner.gameLoopCore` (src/pixzig/pixzig.zig), just owned by Python instead of Zig.

## `App`

```python
App(
    title: str,
    width: int = 800,
    height: int = 480,
    update_hz: float = 120.0,
    max_lag_ms: float = 250.0,
    logical_size=None,
    scale_policy: int = ScalePolicy.FIT,
    scale_factor: float = 1.0,
    fullscreen: bool = False,
    resizable: bool = True,
    vsync: bool = True,
    asset_root: str = None,
)
```

A pixzig game. Subclass it, override [`update`](page:python-api/app#h3-app-update) and [`render`](page:python-api/app#h3-app-render), and call [`run`](page:python-api/app#h3-app-run).

Creating an [`App`](page:python-api/app#h2-app) opens the window and starts the engine, so a subclass can load assets in its own `__init__` right after calling `super().__init__`. The window options mirror `EngineInitOptions` on the Zig side.

| Argument | Type | Default | Description |
|---|---|---|---|
| `title` | `str` |  | The window title. |
| `width` | `int` | `800` | The window width, in window coordinates. |
| `height` | `int` | `480` | The window height, in window coordinates. |
| `update_hz` | `float` | `120.0` | How many times a second [`update`](page:python-api/app#h3-app-update) runs. |
| `max_lag_ms` | `float` | `250.0` | The most time one frame catches up on. Any backlog past it (a hitch, a debugger pause) is dropped, so the game slows down briefly instead of running hundreds of updates at once. |
| `logical_size` |  | `None` | A fixed `(width, height)` game resolution that draw calls address, scaled to the window by `scale_policy`. None makes logical space track the framebuffer, one unit per pixel. |
| `scale_policy` | `int` | `ScalePolicy.FIT` | How `logical_size` scales to the window, a [`ScalePolicy`](page:python-api/window#h2-scalepolicy). Pixel art usually wants `ScalePolicy.INTEGER_FIT`, which scales by whole multiples so pixels stay square and crisp. |
| `scale_factor` | `float` | `1.0` | The constant scale for `ScalePolicy.FIXED`. |
| `fullscreen` | `bool` | `False` | Start fullscreen. |
| `resizable` | `bool` | `True` | Let the user resize the window. |
| `vsync` | `bool` | `True` | Wait for the display's refresh before showing each frame. |
| `asset_root` | `str` | `None` | The directory relative asset paths resolve against. None uses the main script's directory; see [`pixzig.paths`](page:python-api/paths). |

| Attribute | Description |
|---|---|
| `clear_color` | What [`run`](page:python-api/app#h3-app-run) clears the screen to before each [`render`](page:python-api/app#h3-app-render), an `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. |
| `keyboard` | The [`Keyboard`](page:python-api/input#h2-keyboard). |
| `mouse` | The [`Mouse`](page:python-api/input#h2-mouse). |
| `touch` | The [`Touch`](page:python-api/input#h2-touch) screen. |
| `shapes` | [`Shapes`](page:python-api/shapes#h2-shapes), for rectangles. |
| `text` | [`Text`](page:python-api/text#h2-text), for fonts and drawing text. |
| `audio` | [`Audio`](page:python-api/audio#h2-audio), for sounds and music. |
| `window` | The [`Window`](page:python-api/window#h2-window). |

**Raises:**

- `pixzig.Error`: The engine couldn't start, e.g. no OpenGL context.

**Example:**

A 320x240 game upscaled to a 960x720 window:

```python
class MyGame(App):
    def __init__(self):
        super().__init__(
            "My Game", 960, 720,
            logical_size=(320, 240),
            scale_policy=ScalePolicy.INTEGER_FIT,
        )
        self.clear_color = (24, 24, 32)

MyGame().run()
```

### `App.asset_root`

```python
asset_root: str  # property
```

The directory relative asset paths resolve against.

Defaults to the main script's directory. Assign it to point somewhere else, such as a packaged install or a mod directory. It applies to every later load, including through `app.audio` and `app.text`.

### `App.gamepad`

```python
gamepad(index: int) -> Gamepad
```

Returns the gamepad in a slot.

| Argument | Type | Description |
|---|---|---|
| `index` | `int` | The slot, from 0. |

**Returns:** The [`Gamepad`](page:python-api/input#h2-gamepad) in that slot. Check `connected` before reading it.

### `App.last_device`

```python
last_device: int  # property
```

The input device the player used last, an [`InputDevice`](page:python-api/constants#h2-inputdevice).

Use it to word prompts to match ("Press A" or "Press Space") or to hide touch hints.

### `App.load_texture`

```python
load_texture(name: str, path: str) -> None
```

Loads an image file as a texture.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The name to register it under, for [`load_sprite`](page:python-api/app#h3-app-load-sprite) and friends. |
| `path` | `str` | The image file, relative to [`asset_root`](page:python-api/app#h3-app-asset-root). |

**Raises:**

- `FileNotFoundError`: The file doesn't exist; the message names the resolved path and the asset root.
- `pixzig.Error`: The file couldn't be read or decoded.

### `App.create_subtexture`

```python
create_subtexture(base_name: str, new_name: str, x: int, y: int, w: int, h: int) -> None
```

Registers part of a loaded texture as its own texture.

| Argument | Type | Description |
|---|---|---|
| `base_name` | `str` | The texture to take the region from. |
| `new_name` | `str` | The name for the new texture. |
| `x` | `int` | The region's left edge, in pixels. |
| `y` | `int` | The region's top edge, in pixels. |
| `w` | `int` | The region's width, in pixels. |
| `h` | `int` | The region's height, in pixels. |

**Raises:**

- `pixzig.Error`: `base_name` isn't loaded.

### `App.load_sprite`

```python
load_sprite(texture_name: str) -> Sprite
```

Creates a sprite showing a loaded texture.

| Argument | Type | Description |
|---|---|---|
| `texture_name` | `str` | The texture, atlas frame or subtexture to show. |

**Returns:** A new [`Sprite`](page:python-api/sprite#h2-sprite), freed with the app.

**Raises:**

- `pixzig.Error`: No texture has that name.

### `App.load_tilemap`

```python
load_tilemap(name: str, path: str) -> None
```

Loads a Tiled `.tmx` map.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The name to register it under, for [`create_tilemap_renderer`](page:python-api/app#h3-app-create-tilemap-renderer). |
| `path` | `str` | The `.tmx` file, relative to [`asset_root`](page:python-api/app#h3-app-asset-root). |

**Raises:**

- `FileNotFoundError`: The file doesn't exist; the message names the resolved path and the asset root.
- `pixzig.Error`: The map couldn't be read, or uses an unsupported feature.

### `App.create_tilemap_renderer`

```python
create_tilemap_renderer(map_name: str) -> TileMapRenderer
```

Builds a renderer for a map loaded with [`load_tilemap`](page:python-api/app#h3-app-load-tilemap).

The tileset texture comes from the `<image source>` in the `.tmx`, so there is nothing else to pass in. A texture already loaded under that image's base name (`tiles` for `art/tiles.png`) is reused.

| Argument | Type | Description |
|---|---|---|
| `map_name` | `str` | The map's name from [`load_tilemap`](page:python-api/app#h3-app-load-tilemap). |

**Returns:** A new [`TileMapRenderer`](page:python-api/tilemap#h2-tilemaprenderer), freed with the app.

**Raises:**

- `pixzig.Error`: No map has that name, or its tileset image can't be loaded.

### `App.load_manifest`

```python
load_manifest(path: str) -> AssetManifest
```

Opens an asset manifest JSON file.

Its `boot` group loads right away. The manifest file is resolved against [`asset_root`](page:python-api/app#h3-app-asset-root); the asset paths inside it are resolved by the engine, against the manifest's own `root`.

| Argument | Type | Description |
|---|---|---|
| `path` | `str` | The manifest file. |

**Returns:** An [`AssetManifest`](page:python-api/manifest#h2-assetmanifest), freed with the app.

**Raises:**

- `FileNotFoundError`: The file doesn't exist; the message names the resolved path and the asset root.
- `pixzig.Error`: The manifest couldn't be read or a boot asset failed to load.

### `App.load_anim_file`

```python
load_anim_file(path: str) -> None
```

Loads a JSON file of frame sequences and actor states.

They go into the app's shared animation library, for [`Actor.add_state`](page:python-api/anim#h3-actor-add-state). The textures the frames name must already be loaded.

| Argument | Type | Description |
|---|---|---|
| `path` | `str` | The JSON file, relative to [`asset_root`](page:python-api/app#h3-app-asset-root). |

**Raises:**

- `FileNotFoundError`: The file doesn't exist; the message names the resolved path and the asset root.
- `pixzig.Error`: The file couldn't be read, or names an unknown texture or sequence.

### `App.create_sequence`

```python
create_sequence(name: str, loop: bool = True) -> None
```

Registers an empty frame sequence in the animation library.

Add frames to it with [`add_frame`](page:python-api/app#h3-app-add-frame).

| Argument | Type | Default | Description |
|---|---|---|---|
| `name` | `str` |  | The sequence's name. |
| `loop` | `bool` | `True` | Whether it loops. A play-once sequence switches its actor to the state's `next_state` when it ends. |

**Raises:**

- `pixzig.Error`: The sequence couldn't be created.

### `App.add_frame`

```python
add_frame(
    sequence: str,
    texture_name: str,
    frame_ms: float,
    flip: Flip = Flip.NONE,
) -> None
```

Appends a frame to a sequence made with [`create_sequence`](page:python-api/app#h3-app-create-sequence).

| Argument | Type | Default | Description |
|---|---|---|---|
| `sequence` | `str` |  | The sequence's name. |
| `texture_name` | `str` |  | The loaded texture the frame shows. |
| `frame_ms` | `float` |  | How long the frame shows, in milliseconds. |
| `flip` | `Flip` | `Flip.NONE` | How to flip the frame, a [`Flip`](page:python-api/sprite#h2-flip). |

**Raises:**

- `pixzig.Error`: The sequence or texture doesn't exist.

### `App.add_anim_state`

```python
add_anim_state(
    name: str,
    sequence: str,
    next_state: str = None,
    flip: Flip = Flip.NONE,
) -> None
```

Registers a named actor state that plays a sequence.

| Argument | Type | Default | Description |
|---|---|---|---|
| `name` | `str` |  | The state's name, e.g. `"walk_left"`. |
| `sequence` | `str` |  | The sequence it plays. |
| `next_state` | `str` | `None` | The state to switch to when a play-once sequence ends. None holds the last frame instead. Looping sequences ignore it. |
| `flip` | `Flip` | `Flip.NONE` | A flip applied on top of each frame's own, so one sequence can drive both directions. |

**Raises:**

- `pixzig.Error`: The sequence doesn't exist.

### `App.create_actor`

```python
create_actor(texture_name: str) -> Actor
```

Creates an actor, a sprite that plays animation states.

| Argument | Type | Description |
|---|---|---|
| `texture_name` | `str` | The texture its sprite (`actor.sprite`) starts on. |

**Returns:** A new [`Actor`](page:python-api/anim#h2-actor), freed with the app.

**Raises:**

- `pixzig.Error`: No texture has that name.

### `App.create_action_map`

```python
create_action_map() -> ActionMap
```

Creates an action map, for named actions and axes bound to any device.

**Returns:** A new [`ActionMap`](page:python-api/action#h2-actionmap), freed with the app.

**Raises:**

- `pixzig.Error`: The map couldn't be created.

### `App.create_camera`

```python
create_camera() -> Camera
```

Creates a 2D camera, for drawing a world larger than the screen.

**Returns:** A new [`Camera`](page:python-api/camera#h2-camera) looking at (0, 0), freed with the app.

**Raises:**

- `pixzig.Error`: The camera couldn't be created.

### `App.screen_to_logical`

```python
screen_to_logical(x: float, y: float)
```

Converts a point from window coordinates to logical coordinates.

| Argument | Type | Description |
|---|---|---|
| `x` | `float` | The point's x, in window coordinates (as `mouse.raw_pos` reports). |
| `y` | `float` | The point's y. |

**Returns:** The logical `(x, y)`, or None for a point in a letterbox bar.

### `App.logical_to_screen`

```python
logical_to_screen(x: float, y: float)
```

Converts a point from logical coordinates to window coordinates.

| Argument | Type | Description |
|---|---|---|
| `x` | `float` | The point's logical x. |
| `y` | `float` | The point's logical y. |

**Returns:** The `(x, y)` in window coordinates.

### `App.screen_to_world`

```python
screen_to_world(camera: Camera, x: float, y: float)
```

Converts a point from window coordinates to world coordinates.

| Argument | Type | Description |
|---|---|---|
| `camera` | `Camera` | The [`Camera`](page:python-api/camera#h2-camera) the world is seen through. |
| `x` | `float` | The point's x, in window coordinates. |
| `y` | `float` | The point's y. |

**Returns:** The world `(x, y)`, accounting for the camera's position, zoom and rotation, or None for a point in a letterbox bar.

### `App.world_to_screen`

```python
world_to_screen(camera: Camera, x: float, y: float)
```

Converts a point from world coordinates to window coordinates.

| Argument | Type | Description |
|---|---|---|
| `camera` | `Camera` | The [`Camera`](page:python-api/camera#h2-camera) the world is seen through. |
| `x` | `float` | The point's world x. |
| `y` | `float` | The point's world y. |

**Returns:** The `(x, y)` in window coordinates.

### `App.render_begin`

```python
render_begin(camera: Camera = None) -> None
```

Begins a render pass. Every draw goes between this and [`render_end`](page:python-api/app#h3-app-render-end).

There is no pass around [`render`](page:python-api/app#h3-app-render) by default, so it must open its own. Run as many passes as you like in one frame, e.g. a world pass then a HUD pass.

| Argument | Type | Default | Description |
|---|---|---|---|
| `camera` | `Camera` | `None` | Draw in world space through this [`Camera`](page:python-api/camera#h2-camera). None draws in logical coordinates, for UI and HUDs. |

**Example:**

```python
def render(self, alpha):
    self.render_begin(self.camera)
    self.map.render_below(self.camera, 1.0)
    self.player.draw()
    self.map.render_above(self.camera, 1.0)
    self.render_end()

    self.render_begin()
    self.text.draw("HUD text", 10, 10)
    self.render_end()
```

### `App.render_begin_screen`

```python
render_begin_screen() -> None
```

Begins a pass in framebuffer pixels, ignoring the logical size.

Inside a render target it uses the target's own pixels. Useful for debug overlays and for drawing a render target over the whole window. See `window.framebuffer_size`.

### `App.render_end`

```python
render_end() -> None
```

Ends the current render pass, sending its queued draws to the GPU.

### `App.set_blend`

```python
set_blend(mode: int) -> None
```

Sets how later draws in this pass blend with what's behind them.

Every pass starts at `BlendMode.ALPHA`, and the mode ends with the pass.

| Argument | Type | Description |
|---|---|---|
| `mode` | `int` | A [`BlendMode`](page:python-api/constants#h2-blendmode): `ADDITIVE` for glows and lasers, `MULTIPLY` for shadows, `PREMULTIPLIED` for drawing a render target cleared transparent. |

**Raises:**

- `pixzig.Error`: Called outside a pass, or with an unknown mode.

### `App.fade`

```python
fade(color, amount: float) -> None
```

Covers the logical screen with a color.

It's a pass of its own, so call it between passes, usually last in [`render`](page:python-api/app#h3-app-render): a fade to black, a hit flash, a dimmed pause screen.

| Argument | Type | Description |
|---|---|---|
| `color` |  | An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. |
| `amount` | `float` | Scales the color's alpha, from 0 (draws nothing) to 1. |

### `App.create_render_target`

```python
create_render_target(width: int, height: int, filter: int = 0) -> RenderTarget
```

Creates an offscreen image to draw into with [`set_target`](page:python-api/app#h3-app-set-target).

| Argument | Type | Default | Description |
|---|---|---|---|
| `width` | `int` |  | The target's width, in pixels. |
| `height` | `int` |  | The target's height, in pixels. |
| `filter` | `int` | `0` | A [`TargetFilter`](page:python-api/constants#h2-targetfilter). `NEAREST` keeps a low-resolution target blocky when drawn scaled up; `LINEAR` smooths it. |

**Returns:** A new [`RenderTarget`](page:python-api/render_target#h2-rendertarget), freed with the app.

**Raises:**

- `pixzig.Error`: The target couldn't be created.

### `App.set_target`

```python
set_target(target) -> None
```

Sends later passes into a render target, or back to the screen.

Call it between passes. Inside a target, [`render_begin`](page:python-api/app#h3-app-render-begin) and `render_begin(camera)` stretch the logical screen over the whole target.

| Argument | Description |
|---|---|
| `target` | The [`RenderTarget`](page:python-api/render_target#h2-rendertarget) to draw into, or None for the screen. |

### `App.create_shader`

```python
create_shader(name: str, fragment_source: str) -> None
```

Compiles a custom fragment shader for [`set_shader`](page:python-api/app#h3-app-set-shader).

The shader is GLSL ES 3.00. It gets `in vec2 Texcoord`, `in vec4 Col` (the draw's color), `flat in float Mode` and `uniform sampler2D tex`, and writes `out vec4 fragColor`. `texture(tex, Texcoord) * Col` is the plain sprite result to build on. Compiling a name again replaces it.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The shader's name. |
| `fragment_source` | `str` | The GLSL source. |

**Raises:**

- `pixzig.Error`: The shader failed to compile; the message has the log.

### `App.set_shader`

```python
set_shader(name) -> None
```

Draws the rest of this pass with a custom shader.

Every pass starts with the default shader.

| Argument | Description |
|---|---|
| `name` | A shader from [`create_shader`](page:python-api/app#h3-app-create-shader), or None for the default. |

**Raises:**

- `pixzig.Error`: No shader has that name.

### `App.set_uniform`

```python
set_uniform(name: str, value) -> None
```

Sets a uniform on the active shader.

A name the shader doesn't use is ignored.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The uniform's name. |
| `value` |  | An int sets an `int`, a float a `float`, a 2-tuple a `vec2` and a 4-tuple a `vec4`. Pass colors as 0-1 floats here. |

**Raises:**

- `TypeError`: The value isn't one of those types.

### `App.cancel_close`

```python
cancel_close() -> None
```

Keeps the window open after a close request.

Call it from [`on_event`](page:python-api/app#h3-app-on-event) while handling `EventKind.CLOSE_REQUESTED`, e.g. to ask about unsaved changes first.

### `App.update`

```python
update(dt_ms: float) -> None
```

Called at a fixed rate with the game's logic. Override it.

Call `self.quit()` to end the game; the return value is ignored.

| Argument | Type | Description |
|---|---|---|
| `dt_ms` | `float` | The step length in milliseconds, always `1000 / update_hz`. |

### `App.render`

```python
render(alpha: float) -> None
```

Called once per displayed frame to draw it. Override it.

The screen is already cleared to `clear_color`. A `render(self)` without `alpha` still works.

| Argument | Type | Description |
|---|---|---|
| `alpha` | `float` | How far the frame sits between the last two updates, from 0 to 1. Draw moving things at `prev + (curr - prev) * alpha` for smooth motion at any frame rate. |

### `App.on_event`

```python
on_event(event: Event) -> None
```

Called for window, drag-and-drop, gamepad and lifecycle events. Override it.

Events arrive once per frame, before the frame's updates. A close request closes the window afterwards unless this calls [`cancel_close`](page:python-api/app#h3-app-cancel-close).

| Argument | Type | Description |
|---|---|---|
| `event` | `Event` | The [`Event`](page:python-api/event#h2-event). |

### `App.quit`

```python
quit() -> None
```

Ends the game after the current tick.

This is the only way to quit from [`update`](page:python-api/app#h3-app-update); its return value isn't looked at.

### `App.close`

```python
close() -> None
```

Shuts the engine down and frees every native object this app handed out.

Calling it again, or after [`run`](page:python-api/app#h3-app-run) has returned, does nothing. [`run`](page:python-api/app#h3-app-run), `with App(...) as app:`, garbage collection and interpreter exit all call it for you. Sprites, actors and other wrappers raise if used afterwards.

### `App.run`

```python
run() -> None
```

Runs the game loop until [`quit`](page:python-api/app#h3-app-quit) is called or the window closes.

Each frame pumps events to [`on_event`](page:python-api/app#h3-app-on-event), runs [`update`](page:python-api/app#h3-app-update) in fixed steps to catch up with real time, clears the screen and calls [`render`](page:python-api/app#h3-app-render). The engine is shut down when it returns.

**Raises:**

- `pixzig.Error`: The app has already shut down.
