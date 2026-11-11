"""Easing curves, the engine's own `Ease`.

`ease(Ease.QUAD_OUT, t)` maps progress `t` from 0 to 1 along a curve, and
`tween` interpolates between two values with one. `pixzig.sequence` uses
them to animate over time.

Example:
        t = self.elapsed_ms / 400
        y = easing.tween(Ease.BOUNCE_OUT, start_y, floor_y, t)
"""
from . import _native as _n
from .constants import Ease


def ease(curve: int, t: float) -> float:
    """Maps progress along a curve.

    Args:
        curve: An `Ease`.
        t: The progress, clamped to 0-1 first.

    Returns:
        The eased value, 0 at the start and 1 at the end. `BACK_*` and
        `ELASTIC_OUT` overshoot past 0 or 1 on the way.
    """
    return _n.pz_ease(int(curve), float(t))


def tween(curve: int, a: float, b: float, t: float) -> float:
    """Interpolates between two values along a curve.

    Args:
        curve: An `Ease`.
        a: The value at `t = 0`.
        b: The value at `t = 1`.
        t: The progress, clamped to 0-1.

    Returns:
        The value `t` of the way from `a` to `b`.
    """
    return a + (b - a) * ease(curve, t)


__all__ = ["Ease", "ease", "tween"]
