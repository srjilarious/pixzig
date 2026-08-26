"""Sprites. Create via `PixzigApp.load_sprite(texture_name)`."""
import ctypes

from . import _native as _n


class Sprite:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.PixzigError("sprite already destroyed")

    def set_pos(self, x: int, y: int) -> None:
        self._check_alive()
        _n.pz_sprite_set_pos(self._handle, int(x), int(y))

    @property
    def rect(self):
        self._check_alive()
        x, y, w, h = ctypes.c_float(), ctypes.c_float(), ctypes.c_float(), ctypes.c_float()
        _n.pz_sprite_get_rect(self._handle, ctypes.byref(x), ctypes.byref(y), ctypes.byref(w), ctypes.byref(h))
        return (x.value, y.value, w.value, h.value)

    @property
    def pos(self):
        x, y, _, _ = self.rect
        return (x, y)

    @property
    def width(self) -> float:
        return self.rect[2]

    @property
    def height(self) -> float:
        return self.rect[3]

    def draw(self) -> None:
        self._check_alive()
        _n.pz_sprite_draw(self._handle)

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_sprite_destroy(self._handle)
            self._destroyed = True
