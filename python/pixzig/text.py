"""TrueType text rendering."""
from . import _native as _n


class Text:
    def __init__(self, eng):
        self._eng = eng

    def load_font(self, name: str, ttf_path: str, size: float) -> None:
        _n.check(_n.pz_load_font(self._eng, name.encode("utf-8"), ttf_path.encode("utf-8"), float(size)) == 0)

    def set_font(self, name: str) -> None:
        _n.check(_n.pz_set_default_font(self._eng, name.encode("utf-8")) == 0)

    def draw(self, text: str, x: int, y: int) -> None:
        _n.pz_draw_string(self._eng, text.encode("utf-8"), int(x), int(y))
