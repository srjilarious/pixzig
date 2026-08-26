"""Sprites. Create via `PixzigApp.load_sprite(texture_name)`."""
from . import _native as _n


class Sprite:
    def __init__(self, eng, sprite_id: int):
        self._eng = eng
        self._id = sprite_id
        self._destroyed = False

    def set_pos(self, x: int, y: int) -> None:
        _n.pz_sprite_set_pos(self._eng, self._id, int(x), int(y))

    def draw(self) -> None:
        _n.pz_sprite_draw(self._eng, self._id)

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_sprite_destroy(self._eng, self._id)
            self._destroyed = True
