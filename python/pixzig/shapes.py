"""Rectangle drawing. Colors are (r, g, b) or (r, g, b, a) tuples, 0-255."""
from . import _native as _n


def _normalize_color(color):
    if len(color) == 3:
        r, g, b = color
        a = 255
    else:
        r, g, b, a = color
    return r / 255.0, g / 255.0, b / 255.0, a / 255.0


class Shapes:
    def __init__(self, eng):
        self._eng = eng

    def filled_rect(self, x, y, w, h, color) -> None:
        r, g, b, a = _normalize_color(color)
        _n.pz_draw_filled_rect(self._eng, x, y, w, h, r, g, b, a)

    def rect(self, x, y, w, h, color, line_width: int = 1) -> None:
        """Outlines the rect, the line drawn `line_width` pixels *inside*
        the given bounds."""
        r, g, b, a = _normalize_color(color)
        _n.pz_draw_rect(self._eng, x, y, w, h, r, g, b, a, line_width)

    def enclosing_rect(self, x, y, w, h, color, line_width: int = 1) -> None:
        """Like `rect`, but the line sits `line_width` pixels *outside* the
        given bounds, so the rect itself stays fully visible. Use it to
        frame something without covering its edges."""
        r, g, b, a = _normalize_color(color)
        _n.pz_draw_enclosing_rect(self._eng, x, y, w, h, r, g, b, a, line_width)
