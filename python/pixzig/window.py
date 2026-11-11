"""Window and viewport state, reached as `App.window`.

There are three coordinate spaces:

* **Window**: OS window coordinates, what `mouse.raw_pos` reports.
* **Framebuffer**: real pixels drawn, the window size times the display's
  scale on HiDPI screens.
* **Logical**: the game resolution passes draw in. It equals the
  framebuffer size unless `App(..., logical_size=...)` set one.
"""
import ctypes

from . import _native as _n


class ScalePolicy:
    """How the logical game resolution maps onto the window.

    Pass one to `App(..., scale_policy=...)` alongside a `logical_size`; without
    one it has no effect, since logical space then is the framebuffer. Mirrors
    `ScalePolicy` in src/pixzig/window.zig.

    Attributes:
        STRETCH: Fill the window, ignoring the aspect ratio.
        FIT: Scale evenly so the whole game fits, with black bars on two sides
            when the aspect ratios differ.
        FILL: Scale evenly to cover the window, cropping what doesn't fit.
        INTEGER_FIT: `FIT` by whole multiples only, so pixel art stays crisp.
        INTEGER_FILL: `FILL` by whole multiples.
        FIXED: A constant scale from `App(..., scale_factor=...)`, centered.
    """

    STRETCH = 0
    FIT = 1
    FILL = 2
    INTEGER_FIT = 3
    INTEGER_FILL = 4
    FIXED = 5


def _pair_i(fn, eng):
    a, b = ctypes.c_int32(), ctypes.c_int32()
    fn(eng, ctypes.byref(a), ctypes.byref(b))
    return (a.value, b.value)


class Window:
    """The game window. Reached as `App.window`."""
    def __init__(self, eng):
        self._eng = eng

    @property
    def size(self):
        """The window's `(width, height)`, in window coordinates."""
        return _pair_i(_n.pz_window_size, self._eng)

    @property
    def framebuffer_size(self):
        """The drawable framebuffer's `(width, height)`, in pixels."""
        return _pair_i(_n.pz_framebuffer_size, self._eng)

    @property
    def logical_size(self):
        """The logical game resolution's `(width, height)`.

        When `App` wasn't given a `logical_size`, it follows the window, so read it
        rather than caching it.
        """
        return _pair_i(_n.pz_logical_size, self._eng)

    @property
    def scale_factor(self) -> float:
        """Framebuffer pixels per window coordinate: 1.0 normally, 2.0 on a 2x display."""
        return _n.pz_window_scale_factor(self._eng)

    def set_title(self, title: str) -> None:
        """Changes the window's title.

        Args:
            title: The new title.
        """
        _n.pz_window_set_title(self._eng, title.encode("utf-8"))

    def set_size(self, width: int, height: int) -> None:
        """Resizes the window.

        Args:
            width: The width, in window coordinates (not framebuffer pixels).
            height: The height, in window coordinates.
        """
        _n.pz_window_set_size(self._eng, int(width), int(height))

    @property
    def fullscreen(self) -> bool:
        """Whether the window is fullscreen. Assign to switch.

        Raises:
            pixzig.Error: On assignment, when the platform refused.
        """
        return bool(_n.pz_window_is_fullscreen(self._eng))

    @fullscreen.setter
    def fullscreen(self, enabled: bool) -> None:
        _n.check(_n.pz_window_set_fullscreen(self._eng, bool(enabled)) == 0)

    def set_vsync(self, enabled: bool) -> None:
        """Turns vsync on or off, e.g. from a settings menu.

        The starting value comes from `App(..., vsync=...)`. There's no getter: the
        driver may refuse, so what was asked for isn't necessarily what's in effect.

        Args:
            enabled: True to wait for the display's refresh.
        """
        _n.pz_window_set_vsync(self._eng, bool(enabled))
