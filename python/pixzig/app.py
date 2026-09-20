"""App: the base class for a pixzig game written in Python.

Subclass it, override `update` and `render`, and call `run()`. The fixed-
timestep loop below mirrors pixzig's own `AppRunner.gameLoopCore`
(src/pixzig/pixzig.zig), just owned by Python instead of Zig.
"""
import atexit
import ctypes
import functools
import time
import weakref

from . import _native as _n
from .action import ActionMap
from .anim import Actor
from .audio import Audio
from .camera import Camera
from .input import Gamepad, Keyboard, Mouse
from .manifest import AssetManifest
from .paths import AssetPaths
from .shapes import Shapes
from .sprite import Flip, Sprite
from .text import Text
from .tilemap import TileMapRenderer
from .window import ScalePolicy, Window


def _close_at_exit(app_ref):
    """atexit backstop: shut an app down that was built but never run."""
    app = app_ref()
    if app is not None:
        app.close()


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
    """A pixzig game. Subclass, override `update`/`render`, call `run()`.

    The window arguments mirror `EngineInitOptions` on the Zig side:

    * `width`/`height` -- the OS window, in window coordinates.
    * `logical_size` -- a fixed (width, height) game resolution that draw
      calls address, scaled to the window by `scale_policy`. Leave it None
      and logical space tracks the framebuffer, so one unit is one pixel.
    * `scale_policy` -- one of `ScalePolicy`; only meaningful together with
      `logical_size`. Pixel art usually wants `ScalePolicy.INTEGER_FIT`,
      which scales by whole multiples so pixels stay square and crisp.
    * `scale_factor` -- the constant scale for `ScalePolicy.FIXED`.
    * `asset_root` -- the directory relative asset paths resolve against.
      Defaults to the main script's directory; see `pixzig.paths`.

    A 320x240 game upscaled to a 960x720 window, with sound:

        class MyGame(App):
            def __init__(self):
                super().__init__(
                    "My Game", 960, 720,
                    logical_size=(320, 240),
                    scale_policy=ScalePolicy.INTEGER_FIT,
                )
                self.clear_color = (24, 24, 32)
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

        self.keyboard = Keyboard(eng)
        self.mouse = Mouse(eng)
        self.shapes = Shapes(eng)
        self.text = Text(eng, self._paths)
        self.audio = Audio(eng, self._paths)
        self.window = Window(eng)

    def _track(self, wrapper):
        self._handles.add(wrapper)
        return wrapper

    @property
    def asset_root(self) -> str:
        """The directory relative asset paths resolve against. Defaults to
        the main script's directory; assign to point somewhere else (a
        packaged install, a mod directory). Applies to every later load,
        including through `app.audio` and `app.text`."""
        return self._paths.root

    @asset_root.setter
    def asset_root(self, root: str) -> None:
        self._paths.root = root

    def gamepad(self, index: int) -> Gamepad:
        return Gamepad(self._eng, index)

    # --- Resources -----------------------------------------------------

    # Every loader below takes a path relative to `asset_root` (the main
    # script's directory by default) and hands the engine an absolute one.
    # The engine would otherwise resolve a relative path against the running
    # executable's directory, which under Python is wherever the interpreter
    # is installed. Absolute paths pass through untouched. See `pixzig.paths`.

    def load_texture(self, name: str, path: str) -> None:
        _n.check(_n.pz_load_texture(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def create_subtexture(self, base_name: str, new_name: str, x: int, y: int, w: int, h: int) -> None:
        _n.check(
            _n.pz_texture_sub(
                self._eng, base_name.encode("utf-8"), new_name.encode("utf-8"), int(x), int(y), int(w), int(h)
            )
            == 0
        )

    def load_sprite(self, texture_name: str) -> Sprite:
        handle = _n.pz_sprite_create(self._eng, texture_name.encode("utf-8"))
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(Sprite(handle))

    def load_tilemap(self, name: str, path: str) -> None:
        _n.check(_n.pz_load_tilemap(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def create_tilemap_renderer(self, map_name: str, texture_name: str) -> TileMapRenderer:
        handle = _n.pz_tilemap_renderer_create(self._eng, map_name.encode("utf-8"), texture_name.encode("utf-8"))
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(TileMapRenderer(handle))

    def load_manifest(self, path: str) -> AssetManifest:
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
        """Loads a JSON frame-sequence + actor-state file into the shared
        animation library. Frame textures must already be loaded."""
        _n.check(_n.pz_anim_load_file(self._eng, self._paths.encode(path)) == 0)

    def create_sequence(self, name: str, loop: bool = True) -> None:
        """Registers an empty frame sequence; add frames with `add_frame`."""
        _n.check(_n.pz_anim_new_sequence(self._eng, name.encode("utf-8"), bool(loop)) == 0)

    def add_frame(self, sequence: str, texture_name: str, frame_ms: float, flip: Flip = Flip.NONE) -> None:
        """Appends a frame (a loaded texture shown for `frame_ms`) to a
        sequence made with `create_sequence`."""
        _n.check(
            _n.pz_anim_seq_add_frame(
                self._eng, sequence.encode("utf-8"), texture_name.encode("utf-8"), float(frame_ms), int(flip)
            )
            == 0
        )

    def add_anim_state(self, name: str, sequence: str, next_state: str = None, flip: Flip = Flip.NONE) -> None:
        """Registers a named actor state that plays `sequence`. `flip` is
        applied on top of each frame's own flip."""
        ns = next_state.encode("utf-8") if next_state is not None else None
        _n.check(
            _n.pz_anim_add_state(self._eng, name.encode("utf-8"), sequence.encode("utf-8"), ns, int(flip)) == 0
        )

    def create_actor(self, texture_name: str) -> Actor:
        """Creates an actor whose sprite (`actor.sprite`) starts on the
        texture `texture_name`."""
        handle = _n.pz_actor_create(self._eng, texture_name.encode("utf-8"))
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(Actor(handle))

    # --- Action mapping ---------------------------------------------------

    def create_action_map(self) -> ActionMap:
        handle = _n.pz_action_map_create(self._eng)
        if not handle:
            raise _n.Error(_n.last_error())
        return self._track(ActionMap(handle))

    # --- Camera ----------------------------------------------------------

    def create_camera(self) -> Camera:
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
        lx, ly = ctypes.c_float(), ctypes.c_float()
        ok = _n.pz_screen_to_logical(self._eng, float(x), float(y), ctypes.byref(lx), ctypes.byref(ly))
        return (lx.value, ly.value) if ok else None

    def logical_to_screen(self, x: float, y: float):
        sx, sy = ctypes.c_float(), ctypes.c_float()
        _n.pz_logical_to_screen(self._eng, float(x), float(y), ctypes.byref(sx), ctypes.byref(sy))
        return (sx.value, sy.value)

    def screen_to_world(self, camera: Camera, x: float, y: float):
        wx, wy = ctypes.c_float(), ctypes.c_float()
        ok = _n.pz_screen_to_world(
            self._eng, camera._handle, float(x), float(y), ctypes.byref(wx), ctypes.byref(wy)
        )
        return (wx.value, wy.value) if ok else None

    def world_to_screen(self, camera: Camera, x: float, y: float):
        sx, sy = ctypes.c_float(), ctypes.c_float()
        _n.pz_world_to_screen(
            self._eng, camera._handle, float(x), float(y), ctypes.byref(sx), ctypes.byref(sy)
        )
        return (sx.value, sy.value)

    # --- Rendering ---------------------------------------------------------
    # `render()` must bracket its own drawing with `render_begin()`/`render_end()`
    # -- there's no implicit pass around it. Call `render_begin()` with no
    # arguments for screen-space (UI) drawing, or `render_begin(camera)` for
    # world-space drawing -- e.g. interleaved with
    # `TileMapRenderer.render_below`/`render_above`:
    #
    #   def render(self):
    #       self.render_begin(self.camera)
    #       self.tilemap_renderer.render_below(self.camera, 1.0)
    #       self.player_sprite.draw()
    #       self.tilemap_renderer.render_above(self.camera, 1.0)
    #       self.render_end()
    #       self.render_begin()
    #       self.text.draw("HUD text", 10, 10)
    #       self.render_end()

    def render_begin(self, camera: Camera = None) -> None:
        if camera is None:
            _n.pz_render_begin(self._eng)
        else:
            _n.pz_render_begin_world(self._eng, camera._handle)

    def render_end(self) -> None:
        _n.pz_render_end(self._eng)

    # --- Overridable hooks -----------------------------------------------

    def update(self, dt_ms: float) -> None:
        """Called at a fixed timestep (`update_hz`). Call `self.quit()` to
        end the game; the return value is ignored."""
        pass

    def render(self) -> None:
        """Called once per displayed frame, after the screen is cleared."""
        pass

    # --- Loop --------------------------------------------------------------

    def quit(self) -> None:
        """Ends the game after the current tick. The only way to quit from
        `update` -- the return value isn't looked at."""
        self._running = False

    def close(self) -> None:
        """Shuts the engine down and frees every native handle this app
        handed out. Idempotent: calling it again, or after `run()` has
        returned, does nothing.

        Called for you by `run()`, by `with App(...) as app:`, and --
        as a backstop -- when the app is garbage collected or the
        interpreter exits."""
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
        if self._eng is None:
            raise _n.Error("run() called after the app has already shut down")
        # Time spent before run() (a subclass __init__ loading assets) is not
        # game time, so start the clock fresh.
        self._curr_time = time.perf_counter() * 1000.0
        self._lag = 0.0
        try:
            while self._running and not _n.pz_should_close(self._eng):
                now = time.perf_counter() * 1000.0
                self._lag = min(self._lag + now - self._curr_time, self._max_lag_ms)
                self._curr_time = now

                _n.pz_poll_events(self._eng)

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
                self.render()
                _n.pz_swap_buffers(self._eng)
        finally:
            self.close()
