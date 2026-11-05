"""Narrow-phase collision tests between simple shapes, the engine's own
`pixzig.collision` functions. Coordinates grow downward like the rest of
pixzig, and shapes that only touch don't collide.

Shapes are plain tuples:

* a circle is (x, y, radius), x and y its center,
* a rect is (x, y, w, h), axis-aligned,
* a segment is ((x1, y1), (x2, y2)), e.g. a bullet's path over one tick,
* a point is (x, y), and a polygon a list of points.

    hit = collision.circle_rect(ball, paddle)
    if hit:
        ball_x += hit.mtv[0]
        ball_y += hit.mtv[1]
"""
import ctypes
from collections import namedtuple

from . import _native as _n


class Overlap(namedtuple("Overlap", ["normal", "depth"])):
    """How two overlapping shapes collide. `normal` is a unit (x, y) vector
    pointing from the second shape toward the first, and `depth` how far
    they overlap along it."""

    __slots__ = ()

    @property
    def mtv(self):
        """The minimum translation vector: move the first shape by this to
        separate them."""
        return (self.normal[0] * self.depth, self.normal[1] * self.depth)


#: Where a segment first enters a shape: `t` along it (0 is its start, 1 its
#: end), the `point` there, and the shape's outward `normal`. A segment that
#: starts inside the shape hits at t = 0 with a (0, 0) normal.
SegmentHit = namedtuple("SegmentHit", ["t", "point", "normal"])


def _overlap(found: bool, out: _n.PzOverlap):
    return Overlap((out.nx, out.ny), out.depth) if found else None


def _hit(found: bool, out: _n.PzSegmentHit):
    return SegmentHit(out.t, (out.x, out.y), (out.nx, out.ny)) if found else None


def circle_circle(a, b):
    """An `Overlap` when circles `a` and `b` overlap, else None."""
    out = _n.PzOverlap()
    return _overlap(_n.pz_circle_circle(*map(float, a), *map(float, b), ctypes.byref(out)), out)


def circle_rect(circle, rect):
    """An `Overlap` (normal pointing from the rect toward the circle) when
    they overlap, else None."""
    out = _n.PzOverlap()
    return _overlap(_n.pz_circle_rect(*map(float, circle), *map(float, rect), ctypes.byref(out)), out)


def rect_rect(a, b):
    """An `Overlap` when rects `a` and `b` overlap, along the axis they
    overlap least on, else None."""
    out = _n.PzOverlap()
    return _overlap(_n.pz_rect_rect(*map(float, a), *map(float, b), ctypes.byref(out)), out)


def segment_circle(segment, circle):
    """A `SegmentHit` where the segment first enters the circle, else None."""
    (x1, y1), (x2, y2) = segment
    out = _n.PzSegmentHit()
    found = _n.pz_segment_circle(
        float(x1), float(y1), float(x2), float(y2), *map(float, circle), ctypes.byref(out)
    )
    return _hit(found, out)


def segment_rect(segment, rect):
    """A `SegmentHit` where the segment first enters the rect, else None."""
    (x1, y1), (x2, y2) = segment
    out = _n.PzSegmentHit()
    found = _n.pz_segment_rect(float(x1), float(y1), float(x2), float(y2), *map(float, rect), ctypes.byref(out))
    return _hit(found, out)


def point_in_circle(point, circle) -> bool:
    """Whether `point` is inside the circle (its edge counts as inside)."""
    return bool(_n.pz_point_in_circle(float(point[0]), float(point[1]), *map(float, circle)))


def point_in_polygon(point, polygon) -> bool:
    """Whether `point` is inside `polygon`, a list of three or more (x, y)
    corners in order."""
    coords = (ctypes.c_float * (2 * len(polygon)))(*[float(v) for p in polygon for v in p])
    return bool(_n.pz_point_in_polygon(float(point[0]), float(point[1]), coords, len(polygon)))
