"""Rectangle drawing, reached as `App.shapes`.

Colors are `(r, g, b)` or `(r, g, b, a)` tuples of 0-255 values. Draw
inside a pass (`App.render_begin` ... `App.render_end`).
"""
from . import _native as _n


def _normalize_color(color):
    if len(color) == 3:
        r, g, b = color
        a = 255
    else:
        r, g, b, a = color
    return r / 255.0, g / 255.0, b / 255.0, a / 255.0


class Shapes:
    """Draws filled and outlined rectangles. Reached as `App.shapes`."""
    def __init__(self, eng):
        self._eng = eng

    def filled_rect(self, x, y, w, h, color) -> None:
        """Fills a rect.

        Args:
            x: The left edge.
            y: The top edge.
            w: The width.
            h: The height.
            color: An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values.
        """
        r, g, b, a = _normalize_color(color)
        _n.pz_draw_filled_rect(self._eng, x, y, w, h, r, g, b, a)

    def rect(self, x, y, w, h, color, line_width: int = 1) -> None:
        """Outlines a rect, the line drawn inside its bounds.

        Args:
            x: The left edge.
            y: The top edge.
            w: The width.
            h: The height.
            color: An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values.
            line_width: The line's thickness, in pixels.
        """
        r, g, b, a = _normalize_color(color)
        _n.pz_draw_rect(self._eng, x, y, w, h, r, g, b, a, line_width)

    def enclosing_rect(self, x, y, w, h, color, line_width: int = 1) -> None:
        """Outlines a rect, the line drawn outside its bounds.

        The rect itself stays fully visible, so use it to frame something without
        covering its edges.

        Args:
            x: The left edge.
            y: The top edge.
            w: The width.
            h: The height.
            color: An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values.
            line_width: The line's thickness, in pixels.
        """
        r, g, b, a = _normalize_color(color)
        _n.pz_draw_enclosing_rect(self._eng, x, y, w, h, r, g, b, a, line_width)
