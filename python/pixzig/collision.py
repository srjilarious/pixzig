"""Collision tests between simple shapes, the engine's own `pixzig.collision`.

Use these to decide whether two things really touch and how to push them
apart. Coordinates grow downward like the rest of pixzig, and shapes that
only touch don't collide. Shapes are plain tuples:

* a circle is `(x, y, radius)`, with `x` and `y` its center,
* a rect is `(x, y, w, h)`, axis-aligned,
* a segment is `((x1, y1), (x2, y2))`, e.g. a bullet's path over one tick,
* a point is `(x, y)`, and a polygon a list of points.

Example:
        hit = collision.circle_rect(ball, paddle)
        if hit:
            ball_x += hit.mtv[0]
            ball_y += hit.mtv[1]
"""
import ctypes
from collections import namedtuple

from . import _native as _n


class Overlap(namedtuple("Overlap", ["normal", "depth"])):
    """How two overlapping shapes collide.

    Attributes:
        normal: A unit `(x, y)` vector pointing from the second shape toward
            the first.
        depth: How far they overlap along `normal`.
    """

    __slots__ = ()

    @property
    def mtv(self):
        """The minimum translation vector, `normal * depth`.

        Moving the first shape by it separates them.
        """
        return (self.normal[0] * self.depth, self.normal[1] * self.depth)


class SegmentHit(namedtuple("SegmentHit", ["t", "point", "normal"])):
    """Where a segment first enters a shape.

    A segment that starts inside the shape hits at `t = 0` with a `(0, 0)`
    normal. With several targets, the smallest `t` is the one hit first.

    Attributes:
        t: How far along the segment the hit is, from 0 (its start) to 1
            (its end).
        point: The `(x, y)` where it enters.
        normal: The shape's outward unit normal there, as `(x, y)`.
    """

    __slots__ = ()


def _overlap(found: bool, out: _n.PzOverlap):
    return Overlap((out.nx, out.ny), out.depth) if found else None


def _hit(found: bool, out: _n.PzSegmentHit):
    return SegmentHit(out.t, (out.x, out.y), (out.nx, out.ny)) if found else None


def circle_circle(a, b):
    """Tests two circles.

    Args:
        a: The first circle, `(x, y, radius)`.
        b: The second circle.

    Returns:
        An `Overlap` pointing from `b` toward `a`, or None when they're apart.
    """
    out = _n.PzOverlap()
    return _overlap(_n.pz_circle_circle(*map(float, a), *map(float, b), ctypes.byref(out)), out)


def circle_rect(circle, rect):
    """Tests a circle against a rect.

    Args:
        circle: The circle, `(x, y, radius)`.
        rect: The rect, `(x, y, w, h)`.

    Returns:
        An `Overlap` pointing from the rect toward the circle, or None.
    """
    out = _n.PzOverlap()
    return _overlap(_n.pz_circle_rect(*map(float, circle), *map(float, rect), ctypes.byref(out)), out)


def rect_rect(a, b):
    """Tests two rects.

    Args:
        a: The first rect, `(x, y, w, h)`.
        b: The second rect.

    Returns:
        An `Overlap` along the axis they overlap least on, pointing from `b`
        toward `a`, or None.
    """
    out = _n.PzOverlap()
    return _overlap(_n.pz_rect_rect(*map(float, a), *map(float, b), ctypes.byref(out)), out)


def segment_circle(segment, circle):
    """Finds where a segment first enters a circle.

    Test a fast object's path over one tick rather than where it ends up, so it
    can't skip over a thin target.

    Args:
        segment: The segment, `((x1, y1), (x2, y2))`.
        circle: The circle, `(x, y, radius)`.

    Returns:
        A `SegmentHit`, or None when the segment misses.
    """
    (x1, y1), (x2, y2) = segment
    out = _n.PzSegmentHit()
    found = _n.pz_segment_circle(
        float(x1), float(y1), float(x2), float(y2), *map(float, circle), ctypes.byref(out)
    )
    return _hit(found, out)


def segment_rect(segment, rect):
    """Finds where a segment first enters a rect.

    Args:
        segment: The segment, `((x1, y1), (x2, y2))`.
        rect: The rect, `(x, y, w, h)`.

    Returns:
        A `SegmentHit`, or None when the segment misses.
    """
    (x1, y1), (x2, y2) = segment
    out = _n.PzSegmentHit()
    found = _n.pz_segment_rect(float(x1), float(y1), float(x2), float(y2), *map(float, rect), ctypes.byref(out))
    return _hit(found, out)


def point_in_circle(point, circle) -> bool:
    """Whether a point is inside a circle. The edge counts as inside.

    Args:
        point: The point, `(x, y)`.
        circle: The circle, `(x, y, radius)`.

    Returns:
        True when it's inside.
    """
    return bool(_n.pz_point_in_circle(float(point[0]), float(point[1]), *map(float, circle)))


def point_in_polygon(point, polygon) -> bool:
    """Whether a point is inside a polygon.

    Args:
        point: The point, `(x, y)`.
        polygon: Three or more `(x, y)` corners, in order.

    Returns:
        True when it's inside.
    """
    coords = (ctypes.c_float * (2 * len(polygon)))(*[float(v) for p in polygon for v in p])
    return bool(_n.pz_point_in_polygon(float(point[0]), float(point[1]), coords, len(polygon)))
