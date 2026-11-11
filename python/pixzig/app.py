"""The base class for a pixzig game written in Python.

Subclass `App`, override `update` and `render`, and call `run()`. The
fixed-timestep loop mirrors pixzig's own `AppRunner.gameLoopCore`
(src/pixzig/pixzig.zig), just owned by Python instead of Zig.
"""
import atexit
import ctypes
import functools
import inspect
import time
import weakref

from . import _native as _n
from .action import ActionMap
from .anim import Actor
from .audio import Audio
from .camera import Camera
from .event import Event
from .input import Gamepad, Keyboard, Mouse, Touch
from .manifest import AssetManifest
from .paths import AssetPaths
from .render_target import RenderTarget
from .shapes import Shapes, _normalize_color
from .sprite import Flip, Sprite
from .text import Text
from .tilemap import TileMapRenderer
from .window import ScalePolicy, Window


def _close_at_exit(app_ref):
    """atexit backstop: shut an app down that was built but never run."""
    app = app_ref()
    if app is not None:
        app.close()


def _takes_alpha(render) -> bool:
    """Whether a bound `render` method accepts the interpolation alpha."""
    try:
        params = inspect.signature(render).parameters.values()
    except (TypeError, ValueError):
        return True
    positional = [p for p in params if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD, p.VAR_POSITIONAL)]
    return len(positional) >= 1


def _clear_rgba(color):
    """Splits an (r, g, b) or (r, g, b, a) 0-255 tuple into four ints, the
    form `pz_render_clear` takes."""
    if len(color) == 3:
        r, g, b = color
        a = 255
    else:
        r, g, b, a = color
    return int(r), int(g), int(b), int(a)


class App:
    """A pixzig game. Subclass it, override `update` and `render`, and call `run()`.

    Creating an `App` opens the window and starts the engine, so a subclass can
    load assets in its own `__init__` right after calling `super().__init__`.
    The window options mirror `EngineInitOptions` on the Zig side.

    Args:
        title: The window title.
        width: The window width, in window coordinates.
        height: The window height, in window coordinates.
        update_hz: How many times a second `update` runs.
        max_lag_ms: The most time one frame catches up on. Any backlog past it
            (a hitch, a debugger pause) is dropped, so the game slows down
            briefly instead of running hundreds of updates at once.
        logical_size: A fixed `(width, height)` game resolution that draw calls
            address, scaled to the window by `scale_policy`. None makes logical
            space track the framebuffer, one unit per pixel.
        scale_policy: How `logical_size` scales to the window, a `ScalePolicy`.
            Pixel art usually wants `ScalePolicy.INTEGER_FIT`, which scales by
            whole multiples so pixels stay square and crisp.
        scale_factor: The constant scale for `ScalePolicy.FIXED`.
        fullscreen: Start fullscreen.
        resizable: Let the user resize the window.
        vsync: Wait for the display's refresh before showing each frame.
        asset_root: The directory relative asset paths resolve against. None
            uses the main script's directory; see `pixzig.paths`.

    Attributes:
        clear_color: What `run()` clears the screen to before each `render`, an
            `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values.
        keyboard: The `Keyboard`.
        mouse: The `Mouse`.
        touch: The `Touch` screen.
        shapes: `Shapes`, for rectangles.
        text: `Text`, for fonts and drawing text.
        audio: `Audio`, for sounds and music.
        window: The `Window`.

    Raises:
        pixzig.Error: The engine couldn't start, e.g. no OpenGL context.

    Example:
        A 320x240 game upscaled to a 960x720 window:

            class MyGame(App):
                def __init__(self):
                    super().__init__(
                        "My Game", 960, 720,
                        logical_size=(320, 240),
                        scale_policy=ScalePolicy.INTEGER_FIT,
                    )
                    self.clear_color = (24, 24, 32)

            MyGame().run()
    """

    def __init__(
        self,
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
    ):
        # Where relative asset paths resolve from. Set up before the engine
        # so it's there for a subclass that loads during its own __init__.
        self._paths = AssetPaths(asset_root)

        logical_w, logical_h = logical_size if logical_size is not None else (0, 0)
        opts = _n.PzInitOptions(
            title=title.encode("utf-8"),
            width=int(width),
            height=int(height),
            logical_width=int(logical_w),
            logical_height=int(logical_h),
            scale_policy=int(scale_policy),
            scale_factor=float(scale_factor),
            fullscreen=bool(fullscreen),
            resizable=bool(resizable),
            vsync=bool(vsync),
        )
        eng = _n.pz_init(ctypes.byref(opts))
        if not eng:
            raise _n.Error(_n.last_error())
        self._eng = eng
        # What `run()` clears the screen to each frame, as an (r, g, b) or
        # (r, g, b, a) tuple of 0-255 components. Assign any time.
        self.clear_color = (0, 0, 0)
        # Every handle-owning wrapper handed out (sprites, actors, cameras,
        # ...). `pz_deinit` frees their native objects, so `close()` marks
        # them destroyed on the way out; a later `sprite.destroy()` is then a
        # no-op and other calls raise instead of touching freed memory.
        self._handles = weakref.WeakSet()
        # A subclass __init__ that raises after this point -- a missing
        # texture, say -- never reaches run(), so without these nothing would
        # ever call pz_deinit: the window would stay open and the native
        # engine would leak for the rest of the process. `__del__` covers the
        # usual case (the half-built app is collected as the exception
        # unwinds, which closes it right away, so a retry can create a new
        # engine); this atexit hook is the backstop for an app something
        # still holds a reference to. Registered before any other setup so it
        # covers the whole constructor. Prefer
        # `with App(...) as app:`, which closes at the end of the block.
        self._atexit_hook = functools.partial(_close_at_exit, weakref.ref(self))
        atexit.register(self._atexit_hook)

        self._update_step_ms = 1000.0 / update_hz
        # Cap on how much time one frame catches up on; the rest is dropped
        # so a hitch or debugger pause slows the game instead of stalling it.
        self._max_lag_ms = max_lag_ms
        self._lag = 0.0
        self._curr_time = time.perf_counter() * 1000.0
        self._running = True
        # The engine calls this during the event pump. It only copies each
        # event into `_pending_events`; `run()` hands them to `on_event`
        # once the pump returns, so an exception in `on_event` propagates
        # normally instead of being swallowed at the ctypes boundary. Held
        # on self so ctypes doesn't free the trampoline while it's in use.
        # It closes over the list rather than `self`: a bound method would
        # make a reference cycle, and a half-built app would then wait for
        # the cycle collector instead of closing as soon as it's dropped.
        pending = []
        self._pending_events = pending
        self._event_cb = _n.PzEventFn(lambda _user, event: pending.append(Event._from_native(event.contents)))

        self.keyboard = Keyboard(eng)
        self.mouse = Mouse(eng)
        self.touch = Touch(eng)
        self.shapes = Shapes(eng)
        self.text = Text(eng, self._paths)
        self.audio = Audio(eng, self._paths)
        self.window = Window(eng)

    def _track(self, wrapper):
        self._handles.add(wrapper)
        return wrapper

    @property
    def asset_root(self) -> str:
        """The directory relative asset paths resolve against.

        Defaults to the main script's directory. Assign it to point somewhere else,
        such as a packaged install or a mod directory. It applies to every later
        load, including through `app.audio` and `app.text`.
        """
        return self._paths.root

    @asset_root.setter
    def asset_root(self, root: str) -> None:
        self._paths.root = root

    def gamepad(self, index: int) -> Gamepad:
        """Returns the gamepad in a slot.

        Args:
            index: The slot, from 0.

        Returns:
            The `Gamepad` in that slot. Check `connected` before reading it.
        """
        return Gamepad(self._eng, index)

    @property
    def last_device(self) -> int:
        """The input device the player used last, an `InputDevice`.

        Use it to word prompts to match ("Press A" or "Press Space") or to hide
        touch hints.
        """
        return _n.pz_input_last_device(self._eng)

    # --- Resources -----------------------------------------------------

    # Every loader below takes a path relative to `asset_root` (the main
    # script's directory by default) and hands the engine an absolute one.
    # The engine would otherwise resolve a relative path against the running
    # executable's directory, which under Python is wherever the interpreter
    # is installed. Absolute paths pass through untouched. See `pixzig.paths`.

    def load_texture(self, name: str, path: str) -> None:
        """Loads an image file as a texture.

        Args:
            name: The name to register it under, for `load_sprite` and friends.
            path: The image file, relative to `asset_root`.

        Raises:
            FileNotFoundError: The file doesn't exist; the message names the
                resolved path and the asset root.
            pixzig.Error: The file couldn't be read or decoded.
        """
        _n.check(_n.pz_load_texture(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def create_subtexture(self, base_name: str, new_name: str, x: int, y: int, w: int, h: int) -> None:
        """Registers part of a loaded texture as its own texture.

        Args:
            base_name: The texture to take the region from.
            new_name: The name for the new texture.
            x: The region's left edge, in pixels.
            y: The region's top edge, in pixels.
            w: The region's width, in pixels.
            h: The region's height, in pixels.

        Raises:
            pixzig.Error: `base_name` isn't loaded.
        """
        _n.check(
            _n.pz_texture_sub(
                self._eng, base_name.encode("utf-8"), new_name.encode("utf-8"), int(x), int(y), int(w), int(h)
            )
            == 0
        )

    def load_sprite(self, texture_name: str) -> Sprite:
        """Creates a sprite showing a loaded texture.

        Args:
            texture_name: The texture, atlas frame or subtexture to show.

        Returns:
            A new `Sprite`, freed with the app.

        Raises:
            pixzig.Error: No texture has that name.
        """
        handle = _n.pz_sprite_create(self._eng, texture_name.encode("utf-8"))
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(Sprite(handle))

    def load_tilemap(self, name: str, path: str) -> None:
        """Loads a Tiled `.tmx` map.

        Args:
            name: The name to register it under, for `create_tilemap_renderer`.
            path: The `.tmx` file, relative to `asset_root`.

        Raises:
            FileNotFoundError: The file doesn't exist; the message names the
                resolved path and the asset root.
            pixzig.Error: The map couldn't be read, or uses an unsupported feature.
        """
        _n.check(_n.pz_load_tilemap(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def create_tilemap_renderer(self, map_name: str) -> TileMapRenderer:
        """Builds a renderer for a map loaded with `load_tilemap`.

        The tileset texture comes from the `<image source>` in the `.tmx`, so there
        is nothing else to pass in. A texture already loaded under that image's base
        name (`tiles` for `art/tiles.png`) is reused.

        Args:
            map_name: The map's name from `load_tilemap`.

        Returns:
            A new `TileMapRenderer`, freed with the app.

        Raises:
            pixzig.Error: No map has that name, or its tileset image can't be loaded.
        """
        handle = _n.pz_tilemap_renderer_create(self._eng, map_name.encode("utf-8"))
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(TileMapRenderer(handle))

    def read_file(self, path: str) -> bytes:
        """Reads a whole file the way the engine reads its assets.

        For a game's own data files (JSON, text, level data). With a manifest,
        `AssetManifest.read_raw` reads one by id instead.

        Args:
            path: The file, relative to `asset_root`.

        Returns:
            The file's contents.

        Raises:
            FileNotFoundError: The file doesn't exist; the message names the
                resolved path and the asset root.
            pixzig.Error: The file couldn't be read.
        """
        return _n.read_buffer(_n.pz_read_file, self._paths.encode(path))

    def load_manifest(self, path: str) -> AssetManifest:
        """Opens an asset manifest JSON file.

        Its `boot` group loads right away. The manifest file is resolved against
        `asset_root`; the asset paths inside it are resolved by the engine, against
        the manifest's own `root`.

        Args:
            path: The manifest file.

        Returns:
            An `AssetManifest`, freed with the app.

        Raises:
            FileNotFoundError: The file doesn't exist; the message names the
                resolved path and the asset root.
            pixzig.Error: The manifest couldn't be read or a boot asset failed to load.
        """
        # Note this resolves the manifest file itself. The asset paths
        # *inside* it are resolved by the engine, against the manifest's own
        # `root` plus the build's asset base.
        handle = _n.pz_manifest_load(self._eng, self._paths.encode(path))
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(AssetManifest(handle))

    # --- Sprite animation -----------------------------------------------
    # Frame sequences and actor states live in one shared library owned by
    # the app. Build it here (from a file or frame by frame), then attach
    # states to actors created with `create_actor()`. See `pixzig.anim`.

    def load_anim_file(self, path: str) -> None:
        """Loads a JSON file of frame sequences and actor states.

        They go into the app's shared animation library, for `Actor.add_state`. The
        textures the frames name must already be loaded.

        Args:
            path: The JSON file, relative to `asset_root`.

        Raises:
            FileNotFoundError: The file doesn't exist; the message names the
                resolved path and the asset root.
            pixzig.Error: The file couldn't be read, or names an unknown texture or
                sequence.
        """
        _n.check(_n.pz_anim_load_file(self._eng, self._paths.encode(path)) == 0)

    def create_sequence(self, name: str, loop: bool = True) -> None:
        """Registers an empty frame sequence in the animation library.

        Add frames to it with `add_frame`.

        Args:
            name: The sequence's name.
            loop: Whether it loops. A play-once sequence switches its actor to the
                state's `next_state` when it ends.

        Raises:
            pixzig.Error: The sequence couldn't be created.
        """
        _n.check(_n.pz_anim_new_sequence(self._eng, name.encode("utf-8"), bool(loop)) == 0)

    def add_frame(self, sequence: str, texture_name: str, frame_ms: float, flip: Flip = Flip.NONE) -> None:
        """Appends a frame to a sequence made with `create_sequence`.

        Args:
            sequence: The sequence's name.
            texture_name: The loaded texture the frame shows.
            frame_ms: How long the frame shows, in milliseconds.
            flip: How to flip the frame, a `Flip`.

        Raises:
            pixzig.Error: The sequence or texture doesn't exist.
        """
        _n.check(
            _n.pz_anim_seq_add_frame(
                self._eng, sequence.encode("utf-8"), texture_name.encode("utf-8"), float(frame_ms), int(flip)
            )
            == 0
        )

    def add_anim_state(self, name: str, sequence: str, next_state: str = None, flip: Flip = Flip.NONE) -> None:
        """Registers a named actor state that plays a sequence.

        Args:
            name: The state's name, e.g. `"walk_left"`.
            sequence: The sequence it plays.
            next_state: The state to switch to when a play-once sequence ends. None
                holds the last frame instead. Looping sequences ignore it.
            flip: A flip applied on top of each frame's own, so one sequence can
                drive both directions.

        Raises:
            pixzig.Error: The sequence doesn't exist.
        """
        ns = next_state.encode("utf-8") if next_state is not None else None
        _n.check(
            _n.pz_anim_add_state(self._eng, name.encode("utf-8"), sequence.encode("utf-8"), ns, int(flip)) == 0
        )

    def create_actor(self, texture_name: str) -> Actor:
        """Creates an actor, a sprite that plays animation states.

        Args:
            texture_name: The texture its sprite (`actor.sprite`) starts on.

        Returns:
            A new `Actor`, freed with the app.

        Raises:
            pixzig.Error: No texture has that name.
        """
        handle = _n.pz_actor_create(self._eng, texture_name.encode("utf-8"))
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(Actor(handle))

    # --- Action mapping ---------------------------------------------------

    def create_action_map(self) -> ActionMap:
        """Creates an action map, for named actions and axes bound to any device.

        Returns:
            A new `ActionMap`, freed with the app.

        Raises:
            pixzig.Error: The map couldn't be created.
        """
        handle = _n.pz_action_map_create(self._eng)
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(ActionMap(handle))

    # --- Camera ----------------------------------------------------------

    def create_camera(self) -> Camera:
        """Creates a 2D camera, for drawing a world larger than the screen.

        Returns:
            A new `Camera` looking at (0, 0), freed with the app.

        Raises:
            pixzig.Error: The camera couldn't be created.
        """
        handle = _n.pz_camera_create(self._eng)
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(Camera(handle))

    # --- Coordinate transforms -----------------------------------------
    # "screen" = window coordinates (what `mouse.raw_pos` reports), "logical"
    # = the game-resolution space passes draw in, "world" additionally
    # accounts for a camera. The screen_to_* calls return None for a point in
    # a letterbox / pillarbox band.

    def screen_to_logical(self, x: float, y: float):
        """Converts a point from window coordinates to logical coordinates.

        Args:
            x: The point's x, in window coordinates (as `mouse.raw_pos` reports).
            y: The point's y.

        Returns:
            The logical `(x, y)`, or None for a point in a letterbox bar.
        """
        lx, ly = ctypes.c_float(), ctypes.c_float()
        ok = _n.pz_screen_to_logical(self._eng, float(x), float(y), ctypes.byref(lx), ctypes.byref(ly))
        return (lx.value, ly.value) if ok else None

    def logical_to_screen(self, x: float, y: float):
        """Converts a point from logical coordinates to window coordinates.

        Args:
            x: The point's logical x.
            y: The point's logical y.

        Returns:
            The `(x, y)` in window coordinates.
        """
        sx, sy = ctypes.c_float(), ctypes.c_float()
        _n.pz_logical_to_screen(self._eng, float(x), float(y), ctypes.byref(sx), ctypes.byref(sy))
        return (sx.value, sy.value)

    def screen_to_world(self, camera: Camera, x: float, y: float):
        """Converts a point from window coordinates to world coordinates.

        Args:
            camera: The `Camera` the world is seen through.
            x: The point's x, in window coordinates.
            y: The point's y.

        Returns:
            The world `(x, y)`, accounting for the camera's position, zoom and
            rotation, or None for a point in a letterbox bar.
        """
        wx, wy = ctypes.c_float(), ctypes.c_float()
        ok = _n.pz_screen_to_world(
            self._eng, camera._handle, float(x), float(y), ctypes.byref(wx), ctypes.byref(wy)
        )
        return (wx.value, wy.value) if ok else None

    def world_to_screen(self, camera: Camera, x: float, y: float):
        """Converts a point from world coordinates to window coordinates.

        Args:
            camera: The `Camera` the world is seen through.
            x: The point's world x.
            y: The point's world y.

        Returns:
            The `(x, y)` in window coordinates.
        """
        sx, sy = ctypes.c_float(), ctypes.c_float()
        _n.pz_world_to_screen(
            self._eng, camera._handle, float(x), float(y), ctypes.byref(sx), ctypes.byref(sy)
        )
        return (sx.value, sy.value)

    # --- Rendering ---------------------------------------------------------
    # `render()` must bracket its own drawing with `render_begin()`/`render_end()`
    # -- there's no implicit pass around it. Call `render_begin()` with no
    # arguments for logical-coordinate UI/HUD drawing, or `render_begin(camera)`
    # for world-space drawing -- e.g. interleaved with
    # `TileMapRenderer.render_below`/`render_above`:
    #
    #   def render(self, alpha):
    #       self.render_begin(self.camera)
    #       self.tilemap_renderer.render_below(self.camera, 1.0)
    #       self.player_sprite.draw()
    #       self.tilemap_renderer.render_above(self.camera, 1.0)
    #       self.render_end()
    #       self.render_begin()
    #       self.text.draw("HUD text", 10, 10)
    #       self.render_end()

    def render_begin(self, camera: Camera = None) -> None:
        """Begins a render pass. Every draw goes between this and `render_end`.

        There is no pass around `render` by default, so it must open its own. Run as
        many passes as you like in one frame, e.g. a world pass then a HUD pass.

        Args:
            camera: Draw in world space through this `Camera`. None draws in
                logical coordinates, for UI and HUDs.

        Example:
                def render(self, alpha):
                    self.render_begin(self.camera)
                    self.map.render_below(self.camera, 1.0)
                    self.player.draw()
                    self.map.render_above(self.camera, 1.0)
                    self.render_end()

                    self.render_begin()
                    self.text.draw("HUD text", 10, 10)
                    self.render_end()
        """
        if camera is None:
            _n.pz_render_begin(self._eng)
        else:
            _n.pz_render_begin_world(self._eng, camera._handle)

    def render_begin_screen(self) -> None:
        """Begins a pass in framebuffer pixels, ignoring the logical size.

        Inside a render target it uses the target's own pixels. Useful for debug
        overlays and for drawing a render target over the whole window. See
        `window.framebuffer_size`.
        """
        _n.pz_render_begin_screen(self._eng)

    def render_end(self) -> None:
        """Ends the current render pass, sending its queued draws to the GPU."""
        _n.pz_render_end(self._eng)

    def set_blend(self, mode: int) -> None:
        """Sets how later draws in this pass blend with what's behind them.

        Every pass starts at `BlendMode.ALPHA`, and the mode ends with the pass.

        Args:
            mode: A `BlendMode`: `ADDITIVE` for glows and lasers, `MULTIPLY` for
                shadows, `PREMULTIPLIED` for drawing a render target cleared
                transparent.

        Raises:
            pixzig.Error: Called outside a pass, or with an unknown mode.
        """
        _n.check(_n.pz_render_set_blend(self._eng, int(mode)) == 0)

    def fade(self, color, amount: float) -> None:
        """Covers the logical screen with a color.

        It's a pass of its own, so call it between passes, usually last in
        `render`: a fade to black, a hit flash, a dimmed pause screen.

        Args:
            color: An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values.
            amount: Scales the color's alpha, from 0 (draws nothing) to 1.
        """
        r, g, b, a = _normalize_color(color)
        _n.pz_render_fade(self._eng, r, g, b, a, float(amount))

    # --- Render targets and shaders ------------------------------------

    def create_render_target(self, width: int, height: int, filter: int = 0) -> RenderTarget:
        """Creates an offscreen image to draw into with `set_target`.

        Args:
            width: The target's width, in pixels.
            height: The target's height, in pixels.
            filter: A `TargetFilter`. `NEAREST` keeps a low-resolution target
                blocky when drawn scaled up; `LINEAR` smooths it.

        Returns:
            A new `RenderTarget`, freed with the app.

        Raises:
            pixzig.Error: The target couldn't be created.
        """
        handle = _n.pz_render_target_create(self._eng, int(width), int(height), int(filter))
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(RenderTarget(handle))

    def set_target(self, target) -> None:
        """Sends later passes into a render target, or back to the screen.

        Call it between passes. Inside a target, `render_begin()` and
        `render_begin(camera)` stretch the logical screen over the whole target.

        Args:
            target: The `RenderTarget` to draw into, or None for the screen.
        """
        _n.pz_render_set_target(self._eng, target._handle if target is not None else None)

    def create_shader(self, name: str, fragment_source: str) -> None:
        """Compiles a custom fragment shader for `set_shader`.

        The shader is GLSL ES 3.00. It gets `in vec2 Texcoord`, `in vec4 Col` (the
        draw's color), `flat in float Mode` and `uniform sampler2D tex`, and writes
        `out vec4 fragColor`. `texture(tex, Texcoord) * Col` is the plain sprite
        result to build on. Compiling a name again replaces it.

        Args:
            name: The shader's name.
            fragment_source: The GLSL source.

        Raises:
            pixzig.Error: The shader failed to compile; the message has the log.
        """
        _n.check(_n.pz_shader_create(self._eng, name.encode("utf-8"), fragment_source.encode("utf-8")) == 0)

    def set_shader(self, name) -> None:
        """Draws the rest of this pass with a custom shader.

        Every pass starts with the default shader.

        Args:
            name: A shader from `create_shader`, or None for the default.

        Raises:
            pixzig.Error: No shader has that name.
        """
        _n.check(_n.pz_render_set_shader(self._eng, name.encode("utf-8") if name is not None else None) == 0)

    def set_uniform(self, name: str, value) -> None:
        """Sets a uniform on the active shader.

        A name the shader doesn't use is ignored.

        Args:
            name: The uniform's name.
            value: An int sets an `int`, a float a `float`, a 2-tuple a `vec2` and
                a 4-tuple a `vec4`. Pass colors as 0-1 floats here.

        Raises:
            TypeError: The value isn't one of those types.
        """
        key = name.encode("utf-8")
        if isinstance(value, bool) or not isinstance(value, (int, float, tuple, list)):
            raise TypeError(f"set_uniform: unsupported value {value!r}")
        if isinstance(value, int):
            _n.pz_render_set_uniform_int(self._eng, key, value)
        elif isinstance(value, float):
            _n.pz_render_set_uniform_float(self._eng, key, value)
        elif len(value) == 2:
            _n.pz_render_set_uniform_vec2(self._eng, key, float(value[0]), float(value[1]))
        elif len(value) == 4:
            _n.pz_render_set_uniform_vec4(self._eng, key, *(float(v) for v in value))
        else:
            raise TypeError(f"set_uniform: a tuple uniform needs 2 or 4 values, got {len(value)}")

    # --- Events --------------------------------------------------------

    def _pump_events(self) -> None:
        _n.pz_poll_events_cb(self._eng, self._event_cb, None)
        events = list(self._pending_events)
        self._pending_events.clear()
        for event in events:
            self.on_event(event)

    def cancel_close(self) -> None:
        """Keeps the window open after a close request.

        Call it from `on_event` while handling `EventKind.CLOSE_REQUESTED`, e.g. to
        ask about unsaved changes first.
        """
        _n.pz_cancel_close(self._eng)

    # --- Overridable hooks -----------------------------------------------

    def update(self, dt_ms: float) -> None:
        """Called at a fixed rate with the game's logic. Override it.

        Call `self.quit()` to end the game; the return value is ignored.

        Args:
            dt_ms: The step length in milliseconds, always `1000 / update_hz`.
        """
        pass

    def render(self, alpha: float) -> None:
        """Called once per displayed frame to draw it. Override it.

        The screen is already cleared to `clear_color`. A `render(self)` without
        `alpha` still works.

        Args:
            alpha: How far the frame sits between the last two updates, from 0 to
                1. Draw moving things at `prev + (curr - prev) * alpha` for smooth
                motion at any frame rate.
        """
        pass

    def on_event(self, event: Event) -> None:
        """Called for window, drag-and-drop, gamepad and lifecycle events. Override it.

        Events arrive once per frame, before the frame's updates. A close request
        closes the window afterwards unless this calls `cancel_close()`.

        Args:
            event: The `Event`.
        """
        pass

    # --- Loop --------------------------------------------------------------

    def quit(self) -> None:
        """Ends the game after the current tick.

        This is the only way to quit from `update`; its return value isn't looked at.
        """
        self._running = False

    def close(self) -> None:
        """Shuts the engine down and frees every native object this app handed out.

        Calling it again, or after `run()` has returned, does nothing. `run()`,
        `with App(...) as app:`, garbage collection and interpreter exit all call it
        for you. Sprites, actors and other wrappers raise if used afterwards.
        """
        # getattr guards the case where pz_init itself failed, so __del__
        # runs against an object whose attributes were never assigned.
        hook = getattr(self, "_atexit_hook", None)
        if hook is not None:
            atexit.unregister(hook)
            self._atexit_hook = None
        if getattr(self, "_eng", None) is None:
            return
        for wrapper in list(self._handles):
            wrapper._destroyed = True
        self._handles.clear()
        _n.pz_deinit(self._eng)
        self._eng = None

    def __enter__(self) -> "App":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        self.close()
        return False

    def __del__(self):
        # Runs when a never-run app is collected, e.g. while an exception
        # raised by a subclass __init__ unwinds. Everything here is
        # best-effort: during interpreter shutdown the module globals it
        # needs may already be gone.
        try:
            self.close()
        except Exception:
            pass

    def run(self) -> None:
        """Runs the game loop until `quit()` is called or the window closes.

        Each frame pumps events to `on_event`, runs `update` in fixed steps to catch
        up with real time, clears the screen and calls `render`. The engine is shut
        down when it returns.

        Raises:
            pixzig.Error: The app has already shut down.
        """
        if self._eng is None:
            raise _n.Error("run() called after the app has already shut down")
        # Time spent before run() (a subclass __init__ loading assets) is not
        # game time, so start the clock fresh.
        self._curr_time = time.perf_counter() * 1000.0
        self._lag = 0.0
        render_takes_alpha = _takes_alpha(self.render)
        try:
            while self._running and not _n.pz_should_close(self._eng):
                now = time.perf_counter() * 1000.0
                self._lag = min(self._lag + now - self._curr_time, self._max_lag_ms)
                self._curr_time = now

                self._pump_events()

                while self._lag > self._update_step_ms and self._running:
                    self._lag -= self._update_step_ms
                    _n.pz_update_input(self._eng)
                    self.update(self._update_step_ms)
                    # Closes the input tick: without it, key_pressed() would
                    # keep reporting the same press on every later tick.
                    _n.pz_finish_tick(self._eng)

                # An update that called quit() ends the game right there,
                # without drawing a frame of the state it just abandoned.
                if not self._running:
                    break

                r, g, b, a = _clear_rgba(self.clear_color)
                _n.pz_render_clear(self._eng, r, g, b, a)
                if render_takes_alpha:
                    # The ticks above leave 0 < lag <= one step: how far the
                    # frame sits past the previous tick, toward the latest.
                    self.render(min(max(self._lag / self._update_step_ms, 0.0), 1.0))
                else:
                    self.render()
                _n.pz_swap_buffers(self._eng)
        finally:
            self.close()
