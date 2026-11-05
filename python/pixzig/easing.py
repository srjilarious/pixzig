"""Easing curves, the engine's own `Ease`. `ease(Ease.QUAD_OUT, t)` maps
progress `t` (0 to 1) along the curve; `tween` interpolates between two
values with one. `pixzig.sequence.tween` uses them to animate over time."""
from . import _native as _n
from .constants import Ease


def ease(curve: int, t: float) -> float:
    """Applies the curve (an `Ease` value) to `t`, which is clamped to
    [0, 1] first. The `BACK_*` and `ELASTIC_OUT` curves overshoot past 0 or
    1 on the way."""
    return _n.pz_ease(int(curve), float(t))


def tween(curve: int, a: float, b: float, t: float) -> float:
    """The value `t` of the way from `a` to `b` along the curve."""
    return a + (b - a) * ease(curve, t)


__all__ = ["Ease", "ease", "tween"]
