"""2D camera. Create via `PixzigApp.create_camera()`."""
import ctypes

from . import _native as _n


class Camera:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.PixzigError("camera already destroyed")

    def set_pos(self, x: float, y: float) -> None:
        self._check_alive()
        _n.pz_camera_set_pos(self._handle, float(x), float(y))

    @property
    def pos(self):
        self._check_alive()
        x, y = ctypes.c_float(), ctypes.c_float()
        _n.pz_camera_get_pos(self._handle, ctypes.byref(x), ctypes.byref(y))
        return (x.value, y.value)

    def set_zoom(self, zoom: float) -> None:
        self._check_alive()
        _n.pz_camera_set_zoom(self._handle, float(zoom))

    @property
    def zoom(self) -> float:
        self._check_alive()
        return _n.pz_camera_get_zoom(self._handle)

    def set_bounds(self, l: float, t: float, r: float, b: float) -> None:
        self._check_alive()
        _n.pz_camera_set_bounds(self._handle, float(l), float(t), float(r), float(b))

    def clear_bounds(self) -> None:
        self._check_alive()
        _n.pz_camera_clear_bounds(self._handle)

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_camera_destroy(self._handle)
            self._destroyed = True
