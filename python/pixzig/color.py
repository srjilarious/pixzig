"""Color helpers. Colors everywhere in pixzig's Python API are (r, g, b) or
(r, g, b, a) tuples of 0-255 components; these build and blend them, like
`Color` on the Zig side.

    from pixzig import color

    sky = color.hex("#3a6ea5")
    dim = color.with_alpha(color.BLACK, 128)
    mid = color.lerp(color.RED, color.YELLOW, 0.5)
"""

WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
TRANSPARENT = (0, 0, 0, 0)
RED = (255, 0, 0, 255)
GREEN = (0, 255, 0, 255)
BLUE = (0, 0, 255, 255)
YELLOW = (255, 255, 0, 255)
CYAN = (0, 255, 255, 255)
MAGENTA = (255, 0, 255, 255)
GRAY = (128, 128, 128, 255)


def _rgba(c):
    """`c` as a 4-tuple, opaque when it has no alpha."""
    if len(c) == 3:
        return (c[0], c[1], c[2], 255)
    return tuple(c)


def rgb(r: int, g: int, b: int, a: int = 255):
    """An (r, g, b, a) color from 0-255 components."""
    return (int(r), int(g), int(b), int(a))


def hex(code):  # noqa: A001 - mirrors Color.hex on the Zig side
    """A color from a hex string ("#ff8800", "ff8800", "#ff880080" with
    alpha, or the short "#f80") or an int (0xff8800, opaque)."""
    if isinstance(code, int):
        return ((code >> 16) & 0xFF, (code >> 8) & 0xFF, code & 0xFF, 255)
    digits = code[1:] if code.startswith("#") else code
    if len(digits) in (3, 4):
        digits = "".join(ch * 2 for ch in digits)
    if len(digits) not in (6, 8):
        raise ValueError(f"not a hex color: {code!r}")
    r, g, b = int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16)
    a = int(digits[6:8], 16) if len(digits) == 8 else 255
    return (r, g, b, a)


def with_alpha(c, a: int):
    """`c` with its alpha replaced by `a` (0-255)."""
    r, g, b, _ = _rgba(c)
    return (r, g, b, int(a))


def lerp(a, b, t: float):
    """The color `t` of the way from `a` to `b` (0 is `a`, 1 is `b`),
    alpha included. `t` is clamped to [0, 1]."""
    t = min(max(float(t), 0.0), 1.0)
    ca, cb = _rgba(a), _rgba(b)
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(ca, cb))
