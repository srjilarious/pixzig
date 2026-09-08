"""Window and viewport state. Access via `PixzigApp.window`.

Coordinate spaces:
  * **window**   - OS window coordinates, what the mouse reports.
  * **framebuffer** - actual pixels drawn (window * dpi scale).
  * **logical**  - the fixed game resolution passes are drawn in; equals the
    framebuffer size unless a logical size was requested.
"""
import ctypes

from . import _native as _n


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
