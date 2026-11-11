"""Offscreen images to draw into, then draw like a texture.

Create one with `App.create_render_target` and send passes into it with
`App.set_target`. Use one to render a low-resolution game and scale it up,
to run a shader over the whole frame, or to draw something once and reuse it.

Example:
        self.scene = self.create_render_target(320, 180)

        def render(self, alpha):
            self.set_target(self.scene)   # later passes draw into the image
            self.render_begin()
            ...                           # the game at 320x180
            self.render_end()
            self.set_target(None)         # back to the screen

            w, h = self.window.framebuffer_size
            self.render_begin_screen()
            self.set_shader("crt")        # post-process the whole frame
            self.scene.draw(0, 0, w, h)
            self.render_end()
"""
import ctypes

from . import _native as _n
from .shapes import _normalize_color


class RenderTarget:
    """An offscreen image. Create one with `App.create_render_target()`."""
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.Error("render target already destroyed (or the app has shut down)")

    @property
    def size(self):
        """The image's `(width, height)`, in pixels."""
        self._check_alive()
        w, h = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_render_target_size(self._handle, ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    def resize(self, w: int, h: int) -> None:
        """Reallocates the image at a new size, e.g. to follow the window.

        What was drawn is discarded and it starts transparent. Call it outside any
        pass that draws into it.

        Args:
            w: The new width, in pixels.
            h: The new height, in pixels.

        Raises:
            pixzig.Error: The new image couldn't be created.
        """
        self._check_alive()
        _n.check(_n.pz_render_target_resize(self._handle, int(w), int(h)) == 0)

    def draw(self, x: float, y: float, w: float, h: float, tint=(255, 255, 255, 255)) -> None:
        """Draws the image upright into a rect of the current pass.

        To draw a target cleared to a transparent color without dark edges, call
        `set_blend(BlendMode.PREMULTIPLIED)` first.

        Args:
            x: The rect's left edge.
            y: The rect's top edge.
            w: The rect's width.
            h: The rect's height.
            tint: Multiplies the image, an `(r, g, b)` or `(r, g, b, a)` tuple of
                0-255 values.
        """
        self._check_alive()
        r, g, b, a = _normalize_color(tint)
        _n.pz_render_target_draw(self._handle, float(x), float(y), float(w), float(h), r, g, b, a)

    def destroy(self) -> None:
        """Frees the target now instead of when the app shuts down.

        Calling it twice does nothing. Using it afterwards raises.
        """
        if not self._destroyed:
            _n.pz_render_target_destroy(self._handle)
            self._destroyed = True
