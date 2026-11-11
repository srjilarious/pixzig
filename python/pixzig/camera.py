"""A 2D camera for drawing a world larger than the screen.

Create one with `App.create_camera()` and draw through it with
`App.render_begin(camera)`.
"""
import ctypes

from . import _native as _n


class Camera:
    """Looks at a point in the world, with zoom and optional bounds.

    Its position is the world point shown at the center of the screen.
    """
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.Error("camera already destroyed (or the app has shut down)")

    def set_pos(self, x: float, y: float) -> None:
        """Centers the camera on a world point.

        Args:
            x: The world x.
            y: The world y.
        """
        self._check_alive()
        _n.pz_camera_set_pos(self._handle, float(x), float(y))

    @property
    def pos(self):
        """The world point at the center of the screen, as `(x, y)`."""
        self._check_alive()
        x, y = ctypes.c_float(), ctypes.c_float()
        _n.pz_camera_get_pos(self._handle, ctypes.byref(x), ctypes.byref(y))
        return (x.value, y.value)

    def set_zoom(self, zoom: float) -> None:
        """Sets the zoom.

        Args:
            zoom: 2.0 shows everything twice as big. The default is 1.
        """
        self._check_alive()
        _n.pz_camera_set_zoom(self._handle, float(zoom))

    @property
    def zoom(self) -> float:
        """The zoom; 2.0 shows everything twice as big."""
        self._check_alive()
        return _n.pz_camera_get_zoom(self._handle)

    def set_bounds(self, l: float, t: float, r: float, b: float) -> None:
        """Keeps the camera from showing anything outside a world rect.

        Usually the map's size. The camera stops at the edges instead of showing
        empty space, and centers on the bounds on an axis where the view is bigger
        than they are.

        Args:
            l: The left edge.
            t: The top edge.
            r: The right edge.
            b: The bottom edge.
        """
        self._check_alive()
        _n.pz_camera_set_bounds(self._handle, float(l), float(t), float(r), float(b))

    def clear_bounds(self) -> None:
        """Removes the bounds set with `set_bounds`."""
        self._check_alive()
        _n.pz_camera_clear_bounds(self._handle)

    def follow(self, x: float, y: float, dt_ms: float, deadzone=(0.0, 0.0), smoothing: float = None) -> None:
        """Moves the camera toward a target, such as the player, for one tick.

        Call it from `update` with that tick's `dt_ms`. Bounds set with
        `set_bounds` still apply when drawing.

        Args:
            x: The target's world x.
            y: The target's world y.
            dt_ms: The tick's length, in milliseconds.
            deadzone: The half-size `(w, h)`, in world units, of a box around the
                camera's center the target can move in without moving the camera.
                `(0, 0)` keeps the target centered.
            smoothing: How fast the camera closes the gap, per second: after one
                second `exp(-smoothing)` of it remains, so 5 is snappy and 2 is
                floaty. None jumps straight to the target.
        """
        self._check_alive()
        rate = float(smoothing) if smoothing is not None else 0.0
        _n.pz_camera_follow(
            self._handle, float(x), float(y), float(dt_ms), float(deadzone[0]), float(deadzone[1]), rate
        )

    def destroy(self) -> None:
        """Frees the camera now instead of when the app shuts down.

        Calling it twice does nothing. Using the camera afterwards raises.
        """
        if not self._destroyed:
            _n.pz_camera_destroy(self._handle)
            self._destroyed = True
