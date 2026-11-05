"""TrueType text rendering. Access via `App.text`.

One draw call takes the style as keyword arguments, like the engine's
`drawText(text, pos, TextStyle)`:

    app.text.load_font("ui", "assets/Roboto.ttf", 16)
    app.text.set_font("ui")
    app.text.draw("Score: 40", 8, 8, color=(255, 220, 0))
    app.text.draw("PAUSED", 160, 100, scale=2, align=TextAlign.CENTER, shadow=(0, 0, 0))

`y` is the top of the text's line box. `x` is its left edge, middle or right
edge, by `align`. Coordinates are in whatever space the current render pass
is using, and may be fractional.
"""
import ctypes

from . import _native as _n
from .constants import TextAlign
from .shapes import _normalize_color


def _style(font, color, scale, align, clip, shadow, shadow_offset) -> _n.PzTextStyle:
    """Fills a `PzTextStyle` from `draw`/`measure`'s keyword arguments."""
    style = _n.PzTextStyle()
    style.font = font.encode("utf-8") if font is not None else None
    style.r, style.g, style.b, style.a = _normalize_color(color)
    style.scale = float(scale)
    style.alignment = int(align)
    if clip is not None:
        x, y, w, h = clip
        style.has_clip = True
        style.clip_l, style.clip_t = float(x), float(y)
        style.clip_r, style.clip_b = float(x) + float(w), float(y) + float(h)
    if shadow is not None:
        style.has_shadow = True
        style.shadow_r, style.shadow_g, style.shadow_b, style.shadow_a = _normalize_color(shadow)
        style.shadow_dx, style.shadow_dy = float(shadow_offset[0]), float(shadow_offset[1])
    return style


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
        """Makes `name` (a font from `load_font` or a manifest) the default
        font: the one `draw` and `measure` use when not given `font=`."""
        _n.check(_n.pz_set_default_font(self._eng, name.encode("utf-8")) == 0)

    def set_pixelated(self, name: str, pixelated: bool = True) -> None:
        """Samples the font `name` with hard pixel edges, for a pixel font
        drawn scaled up. `False` goes back to smooth sampling."""
        _n.check(_n.pz_font_set_pixelated(self._eng, name.encode("utf-8"), bool(pixelated)) == 0)

    def draw(
        self,
        text: str,
        x: float,
        y: float,
        color=(255, 255, 255),
        scale: float = 1.0,
        font: str = None,
        align: int = TextAlign.LEFT,
        clip=None,
        shadow=None,
        shadow_offset=(1, 1),
    ):
        """Draws `text` and returns the (width, height) it took, the same as
        `measure`.

        * `color` -- an (r, g, b) or (r, g, b, a) tuple of 0-255 components.
        * `scale` -- the atlas's own pixels stretched, so large scales get
          soft; load the font at the size you want for crisp text.
        * `font` -- a font name, or None for the default font.
        * `align` -- a `TextAlign`: whether `x` is the left edge, the middle
          or the right edge.
        * `clip` -- an (x, y, w, h) rect the glyphs are cut to.
        * `shadow` -- a color to draw a drop shadow in, `shadow_offset`
          pixels away.
        """
        style = _style(font, color, scale, align, clip, shadow, shadow_offset)
        w, h = ctypes.c_float(), ctypes.c_float()
        _n.check(
            _n.pz_draw_text(
                self._eng, text.encode("utf-8"), float(x), float(y), ctypes.byref(style), ctypes.byref(w), ctypes.byref(h)
            )
            == 0
        )
        return (w.value, h.value)

    def measure(self, text: str, scale: float = 1.0, font: str = None):
        """Returns the (width, height) `text` would take, without drawing
        it: the glyph advances wide, and the font's line box (ascent plus
        descent) tall, so every string in one font measures the same
        height. (0, 0) when there's no font."""
        style = _style(font, (255, 255, 255), scale, TextAlign.LEFT, None, None, (0, 0))
        w, h = ctypes.c_float(), ctypes.c_float()
        _n.check(
            _n.pz_measure_text(self._eng, text.encode("utf-8"), ctypes.byref(style), ctypes.byref(w), ctypes.byref(h))
            == 0
        )
        return (w.value, h.value)

    def line_height(self, font: str = None):
        """A font's line spacing in pixels at scale 1 -- how far apart to
        put rows of text -- or None when there's no such font. `font` is a
        font name, or None for the default font."""
        name = font.encode("utf-8") if font is not None else None
        h = _n.pz_font_line_height(self._eng, name)
        return None if h < 0 else h
