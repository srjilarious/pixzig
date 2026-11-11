# pixzig.collision

Module `pixzig.collision`. Generated from its docstrings by `tools/gen_py_docs.py`.

Collision tests between simple shapes, the engine's own [`pixzig.collision`](page:python-api/collision).

Use these to decide whether two things really touch and how to push them
apart. Coordinates grow downward like the rest of pixzig, and shapes that
only touch don't collide. Shapes are plain tuples:

* a circle is `(x, y, radius)`, with `x` and `y` its center,
* a rect is `(x, y, w, h)`, axis-aligned,
* a segment is `((x1, y1), (x2, y2))`, e.g. a bullet's path over one tick,
* a point is `(x, y)`, and a polygon a list of points.

**Example:**

```python
hit = collision.circle_rect(ball, paddle)
if hit:
    ball_x += hit.mtv[0]
    ball_y += hit.mtv[1]
```

## `Overlap`

How two overlapping shapes collide.

| Attribute | Description |
|---|---|
| `normal` | A unit `(x, y)` vector pointing from the second shape toward the first. |
| `depth` | How far they overlap along `normal`. |

### `Overlap.mtv`

```python
mtv  # property
```

The minimum translation vector, `normal * depth`.

Moving the first shape by it separates them.

## `SegmentHit`

Where a segment first enters a shape.

A segment that starts inside the shape hits at `t = 0` with a `(0, 0)`
normal. With several targets, the smallest `t` is the one hit first.

| Attribute | Description |
|---|---|
| `t` | How far along the segment the hit is, from 0 (its start) to 1 (its end). |
| `point` | The `(x, y)` where it enters. |
| `normal` | The shape's outward unit normal there, as `(x, y)`. |

## `circle_circle`

```python
circle_circle(a, b)
```

Tests two circles.

| Argument | Description |
|---|---|
| `a` | The first circle, `(x, y, radius)`. |
| `b` | The second circle. |

**Returns:** An [`Overlap`](page:python-api/collision#h2-overlap) pointing from `b` toward `a`, or None when they're apart.

## `circle_rect`

```python
circle_rect(circle, rect)
```

Tests a circle against a rect.

| Argument | Description |
|---|---|
| `circle` | The circle, `(x, y, radius)`. |
| `rect` | The rect, `(x, y, w, h)`. |

**Returns:** An [`Overlap`](page:python-api/collision#h2-overlap) pointing from the rect toward the circle, or None.

## `rect_rect`

```python
rect_rect(a, b)
```

Tests two rects.

| Argument | Description |
|---|---|
| `a` | The first rect, `(x, y, w, h)`. |
| `b` | The second rect. |

**Returns:** An [`Overlap`](page:python-api/collision#h2-overlap) along the axis they overlap least on, pointing from `b`
toward `a`, or None.

## `segment_circle`

```python
segment_circle(segment, circle)
```

Finds where a segment first enters a circle.

Test a fast object's path over one tick rather than where it ends up, so it
can't skip over a thin target.

| Argument | Description |
|---|---|
| `segment` | The segment, `((x1, y1), (x2, y2))`. |
| `circle` | The circle, `(x, y, radius)`. |

**Returns:** A [`SegmentHit`](page:python-api/collision#h2-segmenthit), or None when the segment misses.

## `segment_rect`

```python
segment_rect(segment, rect)
```

Finds where a segment first enters a rect.

| Argument | Description |
|---|---|
| `segment` | The segment, `((x1, y1), (x2, y2))`. |
| `rect` | The rect, `(x, y, w, h)`. |

**Returns:** A [`SegmentHit`](page:python-api/collision#h2-segmenthit), or None when the segment misses.

## `point_in_circle`

```python
point_in_circle(point, circle) -> bool
```

Whether a point is inside a circle. The edge counts as inside.

| Argument | Description |
|---|---|
| `point` | The point, `(x, y)`. |
| `circle` | The circle, `(x, y, radius)`. |

**Returns:** True when it's inside.

## `point_in_polygon`

```python
point_in_polygon(point, polygon) -> bool
```

Whether a point is inside a polygon.

| Argument | Description |
|---|---|
| `point` | The point, `(x, y)`. |
| `polygon` | Three or more `(x, y)` corners, in order. |

**Returns:** True when it's inside.
