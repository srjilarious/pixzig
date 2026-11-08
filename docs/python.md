# Python Bindings

Pixzig can also be driven from Python. The `pixzig` Python package talks to a shared library build of the engine through `ctypes`, so it works on any Python 3.9 or newer without compiling an extension. It covers sprites, animation, shapes, styled text, input (including touch), action maps, audio, cameras, tile maps, manifests, render targets, custom shaders and blend modes, plus Python versions of the sequencer, the game state stack, colors, collision tests and saves.

Lua scripting and the flecs ECS are Zig-only: a Python game already has a scripting language, and keeps its own objects.

## Installing

Wheels for Windows (x64) and Linux (x86_64) are published to [PyPI](https://pypi.org/project/pixzig/), so a plain `pip install` is all a game needs. The native engine library ships inside the wheel. Install it into a virtual environment:

On Windows:

```bat
py -m venv .venv
.venv\Scripts\activate
pip install pixzig
```

On Linux:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install pixzig
```

The wheel version matches the engine version, so `pip install pixzig==0.22.0` gets the Python API for engine 0.22.0. The Linux wheel is built against manylinux 2.28 (glibc 2.28 or newer). macOS isn't packaged yet.

The examples in `python/examples/` aren't part of the package. They load art from the repo's top-level `assets/` folder, so clone the repo to run them.

### Building from a checkout

To work on the bindings, or to use engine changes that aren't released yet, build the wheels yourself. This builds the native library with `zig build python-ffi` and packages it:

```sh
python3 python/build_wheels.py
```

That writes Linux and Windows wheels to `python/dist/`. Install the one for your platform into a virtual environment. With [uv](https://docs.astral.sh/uv/) and `just`, `just py_install` does both steps into `.venv`, and `just py hello_pixzig` runs an example from `python/examples/`.

A locally built Linux wheel is tied to the glibc on the machine that built it, so build it on a system at least as old as the ones you want to run on. (The published wheel avoids this by building inside the manylinux container.)

## A Python Game

Subclass `App`, set things up in `__init__`, and override `update` and `render`:

```python
from pixzig import App, Key


class MyGame(App):
    def __init__(self):
        super().__init__("My Game", width=800, height=480)
        self.clear_color = (18, 18, 28)

        self.load_texture("pac", "assets/pac-tiles.png")
        self.player = self.load_sprite("pac")
        self.x, self.y = 100.0, 100.0

    def update(self, dt_ms: float) -> None:
        if self.keyboard.pressed(Key.ESCAPE):
            self.quit()
            return
        if self.keyboard.down(Key.RIGHT):
            self.x += 0.2 * dt_ms
        self.player.set_pos(self.x, self.y)

    def render(self, alpha: float) -> None:
        self.render_begin()
        self.player.draw()
        self.text.draw("Esc to quit", 20, 440)
        self.render_end()


if __name__ == "__main__":
    MyGame().run()
```

It's the same model as the Zig side (see [The Game Loop](page:app-runner)): `update` runs at a fixed rate, 120 Hz by default, and `render` runs once per frame. A few differences:

- Call `self.quit()` to stop. `update`'s return value is ignored.
- `render` gets the interpolation `alpha`, how far the frame sits between the last two updates (see [Smooth Motion](page:app-runner)). A `render(self)` without it still works.
- The screen is cleared to `self.clear_color` before `render` is called.
- Draw between `self.render_begin()` and `self.render_end()`. Pass a camera, `render_begin(camera)`, to draw in world space.
- Override `on_event(self, event)` for window, drag-and-drop, gamepad hot-plug and lifecycle events. `event.kind` is an `EventKind`, and `event.size`, `event.pos`, `event.path`, `event.text` and `event.gamepad_id` are filled in for the kinds that have them. Call `self.cancel_close()` while handling `EventKind.CLOSE_REQUESTED` to keep the window open.

`App`'s constructor takes the same window options as `EngineInitOptions`: `width`, `height`, `logical_size`, `scale_policy`, `fullscreen`, `resizable`, `vsync`, plus `update_hz` and `max_lag_ms`.

## Asset Paths

Relative paths resolve against the directory of your main script, not the working directory, so a game runs the same from wherever you start it. Pass `asset_root=` to `App`, or set `app.asset_root`, to point somewhere else.

## What's Available

| On `App` | What it gives you |
|---|---|
| `load_texture`, `create_subtexture`, `load_sprite` | Textures and `Sprite`s. |
| `create_sequence`, `add_frame`, `add_anim_state`, `load_anim_file`, `create_actor` | Animation. See [Sprites and Animation](page:animation). |
| `create_action_map` | An `ActionMap` with string action names. |
| `create_camera` | A `Camera` with position, zoom, bounds and `follow`. |
| `create_render_target`, `set_target` | Offscreen images to draw into; see below. |
| `create_shader`, `set_shader`, `set_uniform` | Custom fragment shaders. |
| `set_blend`, `fade` | Blend modes (`BlendMode`) and full-screen fades. |
| `render_begin()`, `render_begin(camera)`, `render_begin_screen()` | Logical, world and framebuffer-pixel passes. |
| `last_device` | The `InputDevice` the player used last. |
| `load_tilemap`, `create_tilemap_renderer` | Tiled maps, with tile, flag and object access. |
| `load_manifest` | An `AssetManifest` with `load_group` and `unload_group`. |
| `screen_to_world`, `world_to_screen`, `screen_to_logical`, `logical_to_screen` | Coordinate conversion. |

| Subsystem | What it is |
|---|---|
| `app.keyboard`, `app.mouse`, `app.gamepad(i)` | Raw input. |
| `app.touch` | `tapped()`, `taps()`, `fingers()` and `finger_count`, in logical coordinates. |
| `app.shapes` | `filled_rect`, `rect` and `enclosing_rect`. |
| `app.text` | `load_font`, `set_font`, `set_pixelated`, `draw`, `measure`, `line_height`. |
| `app.audio` | Sounds (`load`, `play` with volume/pan/pitch/loop, `stop`), music (`load_music`, `play_music` with fades, `stop_music`), `set_bus_volume`, `pause_all`, and `play_stream` for generated audio. |
| `app.window` | Size, title, fullscreen and vsync. |

| Module | What it is |
|---|---|
| `pixzig.color` | `hex`, `rgb`, `with_alpha`, `lerp` and constants like `color.BLACK`. |
| `pixzig.collision` | `circle_circle`, `circle_rect`, `rect_rect`, `segment_circle`, `segment_rect`, `point_in_circle`, `point_in_polygon`: the engine's own tests. |
| `pixzig.sequence` | `SequencePlayer` and generator-based sequences; see below. |
| `pixzig.states` | `StateStack` and `State`; see below. |
| `pixzig.easing` | `ease(Ease.QUAD_OUT, t)` and `tween`, the engine's curves. |
| `pixzig.save` | `pref_path`, `save_json`, `load_json` and `write_file_atomic`. |

Colors are `(r, g, b)` or `(r, g, b, a)` tuples of 0-255 values. Keys and buttons are the `Key`, `MouseButton`, `GamepadButton` and `GamepadAxis` enums, generated from the engine's own, as are `Ease`, `BlendMode`, `TextAlign`, `TargetFilter` and `InputDevice`.

### Text

`draw` takes the style as keyword arguments, like `drawText` on the Zig side, and returns the size it drew:

```python
self.text.draw("Score: 40", 8, 8, color=(255, 220, 0))
self.text.draw("PAUSED", 160, 90, scale=2, align=TextAlign.CENTER, shadow=(0, 0, 0))
self.text.draw(long_line, 10, 40, font="small", clip=(10, 40, 200, 20))
w, h = self.text.measure("Score: 40")
```

Positions are floats. `y` is the top of the line box and `align` says whether `x` is the left edge, middle or right edge.

### Render Targets and Shaders

Draw into an offscreen image, then draw that image, for example to scale a low-resolution scene up through a post-processing shader:

```python
self.scene = self.create_render_target(320, 180, TargetFilter.NEAREST)
self.create_shader("scanlines", SCANLINES_GLSL)

def render(self, alpha):
    self.set_target(self.scene)
    self.render_begin()
    ...                                  # the game at 320x180
    self.render_end()
    self.set_target(None)

    w, h = self.window.framebuffer_size
    self.render_begin_screen()
    self.set_shader("scanlines")
    self.set_uniform("strength", 0.25)
    self.scene.draw(0, 0, w, h)
    self.render_end()
```

What a fragment shader receives is the same as on the Zig side; see [Rendering](page:rendering). `python/examples/effects_example.py` puts targets, a shader, additive blending, a fade, sequences and a state stack together.

### Sequences

A sequence is a generator. Code between `yield`s runs straight away, and each yielded step takes its time, with leftover time carried into what follows, the same as the Zig sequencer:

```python
from pixzig.sequence import SequencePlayer, move_to, parallel, tween_attr, wait

def open_door(self):
    self.audio.play("creak")
    yield tween_attr(self, "door_open", 1.0, 400, Ease.QUAD_OUT)
    yield wait(1000)
    yield parallel(move_to(self.hero, 80, 16, 300), self.fade_music())

self.seq = SequencePlayer()
self.seq.play(self.open_door(), tag="door")   # start it
self.seq.update(dt_ms)                         # every tick
```

`tween(apply, start, to, ms, ease)` calls a function with each value instead. A bare `yield` waits one tick, and yielding another generator runs it as a sub-sequence. `is_running(tag)`, `cancel(tag)` and `clear()` work as on the Zig side. Subclass `pixzig.sequence.Step` for steps of your own.

### Game States

`StateStack` is the Zig `GameStateMgr` with objects for states: `push(paused, render_below=True, update_below=False)` lays a pause menu over the game, `pop()` removes it, `set_state(title)` replaces everything. States have `update(dt_ms)` and `render(alpha)`, plus optional `activate`, `deactivate`, `pause` and `resume` hooks; subclass `State` for empty defaults.

An action map in Python:

```python
self.actions = self.create_action_map()
self.actions.bind_key("jump", Key.SPACE)
self.actions.bind_gamepad_button("jump", GamepadButton.A)
self.actions.bind_axis_buttons("move_x", Key.A, Key.D)

# In update:
self.actions.update()
if self.actions.pressed("jump"):
    self.jump()
self.x += self.actions.axis("move_x") * 0.3 * dt_ms
```

## Cleaning Up

`run()` shuts the engine down when the game ends. Objects you created, like sprites and actors, are freed with it. Calling a method on one afterwards raises instead of crashing. If you build an app but don't run it, use it as a context manager so it closes:

```python
with MyGame() as game:
    ...
```

The examples in `python/examples/` cover action maps, animation, audio, tile maps and effects.

## Updating the Bindings

The bindings are a C API in `src/pixzig/c_api.zig` with Python wrappers in `python/pixzig/`. `python/pixzig/constants.py` is generated from the engine's enums: input, event kinds, `Ease`, `BlendMode`, `TextAlign`, `TargetFilter` and `InputDevice`. After changing one of them, regenerate it with `zig build py-constants` and commit the result.

`just py_test` builds the library and runs `python/tests/test_pure.py`, which covers what doesn't need a window: sequences, the state stack, colors, easing, collision and saves.
