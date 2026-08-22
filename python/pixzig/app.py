"""PixzigApp: the base class for a pixzig game written in Python.

Subclass it, override `update` and `render`, and call `run()`. The fixed-
timestep loop below mirrors pixzig's own `PixzigAppRunner.gameLoopCore`
(src/pixzig/pixzig.zig), just owned by Python instead of Zig.
"""
import os
import time

from . import _native as _n
from .camera import Camera
from .input import Gamepad, Keyboard, Mouse
from .manifest import AssetManifest
from .shapes import Shapes
from .sprite import Sprite
from .text import Text
from .tilemap import TileMapRenderer


class PixzigApp:
    def __init__(self, title: str, width: int = 800, height: int = 480, update_hz: float = 120.0):
        eng = _n.pz_init(title.encode("utf-8"), int(width), int(height))
        if not eng:
            raise _n.PixzigError(_n.last_error())
        self._eng = eng
        self._update_step_ms = 1000.0 / update_hz
        self._lag = 0.0
        self._curr_time = time.perf_counter() * 1000.0
        self._running = True

        self.keyboard = Keyboard(eng)
        self.mouse = Mouse(eng)
        self.shapes = Shapes(eng)
        self.text = Text(eng)

    def gamepad(self, index: int) -> Gamepad:
        return Gamepad(self._eng, index)

    # --- Resources -----------------------------------------------------

    def load_texture(self, name: str, path: str) -> None:
        _n.check(_n.pz_load_texture(self._eng, name.encode("utf-8"), path.encode("utf-8")) == 0)

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
            raise _n.PixzigError(_n.last_error())
        return Sprite(handle)

    def load_tilemap(self, name: str, path: str) -> None:
        _n.check(_n.pz_load_tilemap(self._eng, name.encode("utf-8"), path.encode("utf-8")) == 0)

    def create_tilemap_renderer(self, map_name: str, texture_name: str) -> TileMapRenderer:
        handle = _n.pz_tilemap_renderer_create(self._eng, map_name.encode("utf-8"), texture_name.encode("utf-8"))
        if not handle:
            raise _n.PixzigError(_n.last_error())
        return TileMapRenderer(handle)

    def load_manifest(self, path: str) -> AssetManifest:
        # A relative path is resolved (by AssetManifest.loadFromFile, Zig
        # side) against the running executable's own directory -- for a
        # packaged Zig build that's the game, but under Python it would be
        # the Python interpreter's install directory. Resolve to an absolute
        # path against the current working directory here instead, matching
        # the cwd-relative convention load_texture/load_tilemap already use.
        abs_path = os.path.abspath(path)
        handle = _n.pz_manifest_load(self._eng, abs_path.encode("utf-8"))
        if not handle:
            raise _n.PixzigError(_n.last_error())
        return AssetManifest(handle)

    # --- Camera ----------------------------------------------------------

    def create_camera(self) -> Camera:
        handle = _n.pz_camera_create(self._eng)
        if not handle:
            raise _n.PixzigError(_n.last_error())
        return Camera(handle)

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

    def update(self, dt_ms: float) -> bool:
        """Called at a fixed timestep. Return False to quit."""
        return True

    def render(self) -> None:
        """Called once per displayed frame, after the screen is cleared."""
        pass

    # --- Loop --------------------------------------------------------------

    def quit(self) -> None:
        self._running = False

    def run(self) -> None:
        try:
            while self._running and not _n.pz_should_close(self._eng):
                now = time.perf_counter() * 1000.0
                self._lag += now - self._curr_time
                self._curr_time = now

                _n.pz_poll_events(self._eng)

                while self._lag > self._update_step_ms:
                    self._lag -= self._update_step_ms
                    _n.pz_update_input(self._eng)
                    if not self.update(self._update_step_ms):
                        return

                _n.pz_render_clear(self._eng, 0.0, 0.0, 0.0, 1.0)
                self.render()
                _n.pz_swap_buffers(self._eng)
        finally:
            _n.pz_deinit(self._eng)
