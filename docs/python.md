# Python Bindings

Pixzig can also be driven from Python. The `pixzig` Python package talks to a shared library build of the engine through `ctypes`, so it works on any Python 3.9 or newer without compiling an extension. It covers the parts most small games need: sprites, animation, shapes, text, input, action maps, audio, cameras, tile maps and manifests.

## Installing

Build a wheel from a pixzig checkout. This builds the native library with `zig build python-ffi` and packages it:

```sh
python3 python/build_wheels.py
```

That writes Linux and Windows wheels to `python/dist/`. Install the one for your platform into a virtual environment. With [uv](https://docs.astral.sh/uv/) and `just`, `just py_install` does both steps into `.venv`, and `just py hello_pixzig` runs an example from `python/examples/`.

The Linux wheel is built against the glibc on the machine that built it, so build it on a system at least as old as the ones you want to run on.

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

    def render(self) -> None:
        self.render_begin()
        self.player.draw()
        self.text.draw("Esc to quit", 20, 440)
        self.render_end()


if __name__ == "__main__":
    MyGame().run()
```

It's the same model as the Zig side (see [The Game Loop](page:app-runner)): `update` runs at a fixed rate, 120 Hz by default, and `render` runs once per frame. A few differences:

- Call `self.quit()` to stop. `update`'s return value is ignored.
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
| `create_camera` | A `Camera` with position, zoom and bounds. |
| `load_tilemap`, `create_tilemap_renderer` | Tiled maps, with tile, flag and object access. |
| `load_manifest` | An `AssetManifest` with `load_group` and `unload_group`. |
| `screen_to_world`, `world_to_screen`, `screen_to_logical`, `logical_to_screen` | Coordinate conversion. |

| Subsystem | What it is |
|---|---|
| `app.keyboard`, `app.mouse`, `app.gamepad(i)` | Raw input. |
| `app.shapes` | `filled_rect`, `rect` and `enclosing_rect`. |
| `app.text` | `load_font`, `set_font`, `draw`, `draw_colored`, `draw_scaled`, `measure`. |
| `app.audio` | Sounds (`load`, `play` with volume/pan/pitch/loop, `stop`), music (`load_music`, `play_music` with fades, `stop_music`), `set_bus_volume`, `pause_all`, and `play_stream` for generated audio. |
| `app.window` | Size, title, fullscreen and vsync. |

Colors are `(r, g, b)` or `(r, g, b, a)` tuples of 0-255 values. Keys and buttons are the `Key`, `MouseButton`, `GamepadButton` and `GamepadAxis` enums, generated from the engine's own.

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

The examples in `python/examples/` cover action maps, animation, audio and tile maps.

## Updating the Bindings

The bindings are a C API in `src/pixzig/c_api.zig` with Python wrappers in `python/pixzig/`. `python/pixzig/constants.py` is generated from the engine's input enums and event kinds. After changing `src/pixzig/input/keys.zig` or the `Event` union in `src/pixzig/platform/event.zig`, regenerate it with `zig build py-constants` and commit the result.
