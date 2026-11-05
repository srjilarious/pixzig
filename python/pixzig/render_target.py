"""Offscreen images to draw into. Create via `App.create_render_target`.

    self.scene = self.create_render_target(320, 180)

    def render(self, alpha):
        self.set_target(self.scene)      # later passes draw into the image
        self.render_begin()
        ...                              # draw the game at 320x180
        self.render_end()
        self.set_target(None)            # back to the screen

        self.render_begin_screen()
        w, h = self.window.framebuffer_size
        self.set_shader("crt")           # post-process the whole frame
        self.scene.draw(0, 0, w, h)
        self.render_end()
"""
import ctypes

from . import _native as _n
from .shapes import _normalize_color


class RenderTarget:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.Error("render target already destroyed (or the app has shut down)")

    @property
    def size(self):
        """The image's (width, height) in pixels."""
        self._check_alive()
        w, h = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_render_target_size(self._handle, ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    def resize(self, w: int, h: int) -> None:
        """Reallocates the image at a new size, discarding what was drawn
        (it starts transparent). Call it outside a pass drawing into it."""
        self._check_alive()
        _n.check(_n.pz_render_target_resize(self._handle, int(w), int(h)) == 0)

    def draw(self, x: float, y: float, w: float, h: float, tint=(255, 255, 255, 255)) -> None:
        """Draws the image upright into the rect (x, y, w, h) of the current
        pass, multiplied by `tint`. To draw one cleared transparent without
        dark edges, `set_blend(BlendMode.PREMULTIPLIED)` first."""
        self._check_alive()
        r, g, b, a = _normalize_color(tint)
        _n.pz_render_target_draw(self._handle, float(x), float(y), float(w), float(h), r, g, b, a)

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_render_target_destroy(self._handle)
            self._destroyed = True
