"""TrueType text, reached as `App.text`.

A draw takes the style as keyword arguments, like the engine's
`drawText(text, pos, TextStyle)`. `y` is the top of the text's line box, and
`x` is its left edge, middle or right edge by `align`. Coordinates are in
the current pass's space and may be fractional.

Example:
        app.text.load_font("ui", "assets/Roboto-Medium.ttf", 16)
        app.text.set_font("ui")
        app.text.draw("Score: 40", 8, 8, color=(255, 220, 0))
        app.text.draw("PAUSED", 160, 100, scale=2, align=TextAlign.CENTER, shadow=(0, 0, 0))
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
    """Loads fonts and draws text. Reached as `App.text`.

    The engine's embedded default font (Karla, 20 pixels) is ready without
    loading anything.
    """
    def __init__(self, eng, paths):
        self._eng = eng
        self._paths = paths

    def load_font(self, name: str, ttf_path: str, size: float) -> None:
        """Loads a TrueType or OpenType font at a pixel size.

        Args:
            name: The name to register it under, for `set_font` and `font=`.
            ttf_path: The font file, relative to the app's asset root.
            size: The pixel size to rasterize at. Load the size you'll draw at for
                crisp text rather than scaling.

        Raises:
            FileNotFoundError: The file doesn't exist; the message names the
                resolved path and the asset root.
            pixzig.Error: The font couldn't be read.
        """
        _n.check(
            _n.pz_load_font(self._eng, name.encode("utf-8"), self._paths.encode(ttf_path), float(size)) == 0
        )

    def set_font(self, name: str) -> None:
        """Makes a font the default, used by `draw` and `measure` without `font=`.

        Args:
            name: A font from `load_font` or a manifest.

        Raises:
            pixzig.Error: No font has that name.
        """
        _n.check(_n.pz_set_default_font(self._eng, name.encode("utf-8")) == 0)

    def set_pixelated(self, name: str, pixelated: bool = True) -> None:
        """Switches a font between hard pixel edges and smooth sampling.

        Pixel-art fonts drawn at a `scale` above 1 want hard edges.

        Args:
            name: The font's name.
            pixelated: True for hard edges, False for smooth sampling.

        Raises:
            pixzig.Error: No font has that name.
        """
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
        """Draws a string. Call it inside a render pass.

        Args:
            text: The UTF-8 string. Glyphs the font lacks draw as empty boxes.
            x: The left edge, middle or right edge, by `align`.
            y: The top of the line box.
            color: An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values.
            scale: Stretches the font's own pixels, so large scales get soft.
            font: A font name, or None for the default font.
            align: A `TextAlign`: whether `x` is the left edge, middle or right edge.
            clip: An `(x, y, w, h)` rect the glyphs are cut to, for text in a
                scrolling panel.
            shadow: A color to draw a drop shadow in, or None for no shadow.
            shadow_offset: How far the shadow sits from the text, as `(dx, dy)`.

        Returns:
            The `(width, height)` it took, the same as `measure`.

        Raises:
            pixzig.Error: No font has the name given.
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
        """Measures a string without drawing it.

        The height is the font's line box (ascent plus descent), so every string in
        one font measures the same height and centering a measured string centers
        it as drawn.

        Args:
            text: The UTF-8 string.
            scale: The scale it would be drawn at.
            font: A font name, or None for the default font.

        Returns:
            The `(width, height)`, or `(0, 0)` when there's no font.

        Raises:
            pixzig.Error: No font has the name given.
        """
        style = _style(font, (255, 255, 255), scale, TextAlign.LEFT, None, None, (0, 0))
        w, h = ctypes.c_float(), ctypes.c_float()
        _n.check(
            _n.pz_measure_text(self._eng, text.encode("utf-8"), ctypes.byref(style), ctypes.byref(w), ctypes.byref(h))
            == 0
        )
        return (w.value, h.value)

    def line_height(self, font: str = None):
        """A font's line spacing at scale 1, for stacking rows of text.

        Args:
            font: A font name, or None for the default font.

        Returns:
            The spacing in pixels (ascent, descent and line gap), or None when
            there's no such font.
        """
        name = font.encode("utf-8") if font is not None else None
        h = _n.pz_font_line_height(self._eng, name)
        return None if h < 0 else h
