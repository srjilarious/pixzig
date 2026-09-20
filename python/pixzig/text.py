"""TrueType text rendering. Access via `App.text`.

The three draw calls mirror the engine's three text paths, which are
separate batches and can't be combined: plain, colored, and scaled. There is
no colored *and* scaled call yet.

    app.text.load_font("ui", "assets/Roboto.ttf", 16)
    app.text.set_font("ui")
    app.text.draw_colored("Score: 40", 8, 8, (255, 220, 0))

Coordinates are the top-left of the text, in whatever space the current
render pass is using.
"""
import ctypes

from . import _native as _n
from .shapes import _normalize_color


class Text:
    def __init__(self, eng, paths):
        self._eng = eng
        self._paths = paths

    def load_font(self, name: str, ttf_path: str, size: float) -> None:
        """Loads a TTF at `size` pixels and registers it under `name`. A
        relative path is resolved against the app's asset root."""
        _n.check(
            _n.pz_load_font(self._eng, name.encode("utf-8"), self._paths.encode(ttf_path), float(size)) == 0
        )

    def set_font(self, name: str) -> None:
        """Makes `name` (a font from `load_font` or a manifest) the font the
        draw calls below use."""
        _n.check(_n.pz_set_default_font(self._eng, name.encode("utf-8")) == 0)

    def draw(self, text: str, x: int, y: int) -> None:
        _n.pz_draw_string(self._eng, text.encode("utf-8"), int(x), int(y))

    def draw_colored(self, text: str, x: int, y: int, color) -> None:
        """Draws `text` with every glyph tinted by `color`, an (r, g, b) or
        (r, g, b, a) tuple of 0-255 components. Expects a TTF font (the
        alpha-mask atlas the colored batch samples), not a bitmap font."""
        r, g, b, a = _normalize_color(color)
        _n.pz_draw_string_colored(self._eng, text.encode("utf-8"), int(x), int(y), r, g, b, a)

    def draw_scaled(self, text: str, x: int, y: int, scale: float) -> None:
        """Draws `text` scaled uniformly about (x, y). The glyphs are the
        atlas's own pixels stretched, so large scales get soft; load the
        font at the size you want for crisp text."""
        _n.pz_draw_string_scaled(self._eng, text.encode("utf-8"), int(x), int(y), float(scale))

    def measure(self, text: str):
        """Returns the (width, height) `text` would occupy, without drawing
        it. Width is the sum of the glyph advances; height is the tallest
        glyph, so it varies with the string ("ace" is shorter than "Ace")."""
        w, h = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_measure_string(self._eng, text.encode("utf-8"), ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    def line_height(self):
        """The current font's line height in pixels -- the spacing to use
        between rows of text -- or None when no font is set."""
        h = _n.pz_font_line_height(self._eng)
        return None if h < 0 else h
