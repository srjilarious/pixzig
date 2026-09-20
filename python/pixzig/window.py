"""Window and viewport state. Access via `App.window`.

Coordinate spaces:
  * **window**   - OS window coordinates, what the mouse reports.
  * **framebuffer** - actual pixels drawn (window * dpi scale).
  * **logical**  - the fixed game resolution passes are drawn in; equals the
    framebuffer size unless a logical size was requested.
"""
import ctypes

from . import _native as _n


class ScalePolicy:
    """How the logical game resolution maps onto the framebuffer. Pass one
    to `App(..., scale_policy=...)` alongside a `logical_size`; it has no
    effect without one, since logical space then *is* the framebuffer.

    Mirrors `ScalePolicy` in src/pixzig/window.zig -- the values are the
    union's declaration order and cross the FFI as plain ints.
    """

    #: Fills the framebuffer, ignoring aspect ratio.
    STRETCH = 0
    #: Scales uniformly to fit entirely, letterboxing/pillarboxing the rest.
    FIT = 1
    #: Scales uniformly to cover the framebuffer, cropping the overflow.
    FILL = 2
    #: `FIT` rounded down to a whole multiple -- what pixel art wants.
    INTEGER_FIT = 3
    #: `FILL` rounded up to a whole multiple.
    INTEGER_FILL = 4
    #: A constant scale, taken from `App(..., scale_factor=...)`.
    FIXED = 5


def _pair_i(fn, eng):
    a, b = ctypes.c_int32(), ctypes.c_int32()
    fn(eng, ctypes.byref(a), ctypes.byref(b))
    return (a.value, b.value)


class Window:
    def __init__(self, eng):
        self._eng = eng

    @property
    def size(self):
        """(width, height) of the OS window, in window coordinates."""
        return _pair_i(_n.pz_window_size, self._eng)

    @property
    def framebuffer_size(self):
        """(width, height) of the drawable framebuffer, in pixels."""
        return _pair_i(_n.pz_framebuffer_size, self._eng)

    @property
    def logical_size(self):
        """(width, height) of the logical game coordinate space."""
        return _pair_i(_n.pz_logical_size, self._eng)

    @property
    def scale_factor(self) -> float:
        """Framebuffer pixels per window coordinate (1.0 normal, 2.0 retina)."""
        return _n.pz_window_scale_factor(self._eng)

    def set_title(self, title: str) -> None:
        _n.pz_window_set_title(self._eng, title.encode("utf-8"))

    def set_size(self, width: int, height: int) -> None:
        """Resizes the OS window (window coordinates, not framebuffer pixels)."""
        _n.pz_window_set_size(self._eng, int(width), int(height))

    @property
    def fullscreen(self) -> bool:
        return bool(_n.pz_window_is_fullscreen(self._eng))

    @fullscreen.setter
    def fullscreen(self, enabled: bool) -> None:
        _n.check(_n.pz_window_set_fullscreen(self._eng, bool(enabled)) == 0)

    def set_vsync(self, enabled: bool) -> None:
        """Turns vsync on or off on the live graphics context, e.g. from a
        settings menu. The starting value comes from `App(..., vsync=...)`.
        There is no getter: the driver may refuse, so what was asked for
        isn't necessarily what's in effect."""
        _n.pz_window_set_vsync(self._eng, bool(enabled))
