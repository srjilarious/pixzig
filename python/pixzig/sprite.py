"""Sprites. Create via `App.load_sprite(texture_name)`."""
import ctypes
from enum import IntEnum

from . import _native as _n


class Rotate(IntEnum):
    """90-degree rotation / flip applied when a sprite is drawn. Matches the
    engine's `Rotate` enum order."""

    NONE = 0
    ROT90 = 1
    ROT180 = 2
    ROT270 = 3
    FLIP_HORZ = 4
    FLIP_VERT = 5


class Flip(IntEnum):
    """Per-frame flip for animation frames. Matches the engine's `Flip` enum."""

    NONE = 0
    HORZ = 1
    VERT = 2
    BOTH = 3


class Sprite:
    def __init__(self, handle, owner=None):
        self._handle = handle
        self._destroyed = False
        # The Actor this sprite belongs to, or None for a standalone sprite.
        # An actor's sprite lives and dies with the actor.
        self._owner = owner

    def _check_alive(self) -> None:
        if self._destroyed or (self._owner is not None and self._owner._destroyed):
            raise _n.Error("sprite already destroyed (or the app has shut down)")

    def set_pos(self, x: float, y: float) -> None:
        """Moves the sprite's origin (top-left corner unless `set_origin` was
        called). Fractional positions are kept."""
        self._check_alive()
        _n.pz_sprite_set_pos(self._handle, float(x), float(y))

    def set_origin(self, x: float, y: float) -> None:
        """Sets the pivot in texture-frame pixels (e.g. (8, 16) is the
        bottom-center of a 16x16 frame). `set_pos` places this point and
        scaling grows around it. The sprite's position stays the same."""
        self._check_alive()
        _n.pz_sprite_set_origin(self._handle, float(x), float(y))

    def set_size(self, w: float, h: float) -> None:
        """Resizes the on-screen rectangle around the origin."""
        self._check_alive()
        _n.pz_sprite_set_size(self._handle, float(w), float(h))

    def set_scale(self, sx: float, sy: float = None) -> None:
        """Scales relative to the sprite's creation size (the full texture
        frame), around the origin. `set_scale(2)` doubles it; `set_scale(1)`
        restores it. Pass a single value for a uniform scale."""
        self._check_alive()
        if sy is None:
            sy = sx
        _n.pz_sprite_set_scale(self._handle, float(sx), float(sy))

    def set_rotate(self, rotate: Rotate) -> None:
        """Sets a 90-degree rotation / flip (a `Rotate` value)."""
        self._check_alive()
        _n.pz_sprite_set_rotate(self._handle, int(rotate))

    def set_src_rect(self, x: int, y: int, w: int, h: int) -> None:
        """Draws only a sub-region of the sprite's texture, in texture pixels."""
        self._check_alive()
        _n.pz_sprite_set_src_rect(self._handle, int(x), int(y), int(w), int(h))

    def set_tint(self, color) -> None:
        """Multiplies the sprite by an (r, g, b) or (r, g, b, a) colour, 0-255.
        (255, 255, 255) or (255, 255, 255, 255) clears the tint."""
        self._check_alive()
        if len(color) == 3:
            r, g, b = color
            a = 255
        else:
            r, g, b, a = color
        _n.pz_sprite_set_tint(self._handle, r / 255.0, g / 255.0, b / 255.0, a / 255.0)

    def clear_tint(self) -> None:
        self._check_alive()
        _n.pz_sprite_set_tint(self._handle, 1.0, 1.0, 1.0, 1.0)

    @property
    def rect(self):
        self._check_alive()
        x, y, w, h = ctypes.c_float(), ctypes.c_float(), ctypes.c_float(), ctypes.c_float()
        _n.pz_sprite_get_rect(self._handle, ctypes.byref(x), ctypes.byref(y), ctypes.byref(w), ctypes.byref(h))
        return (x.value, y.value, w.value, h.value)

    @property
    def pos(self):
        """The origin's position (what `set_pos` set)."""
        self._check_alive()
        x, y = ctypes.c_float(), ctypes.c_float()
        _n.pz_sprite_get_pos(self._handle, ctypes.byref(x), ctypes.byref(y))
        return (x.value, y.value)

    @property
    def size(self):
        self._check_alive()
        w, h = ctypes.c_float(), ctypes.c_float()
        _n.pz_sprite_get_size(self._handle, ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

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
        """Frees the sprite. An actor's sprite is freed with its actor, so
        this does nothing for one."""
        if self._owner is not None:
            return
        if not self._destroyed:
            _n.pz_sprite_destroy(self._handle)
            self._destroyed = True
