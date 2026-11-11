# pixzig.easing

Module `pixzig.easing`. Generated from its docstrings by `tools/gen_py_docs.py`.

Easing curves, the engine's own [`Ease`](page:python-api/constants#h2-ease).

`ease(Ease.QUAD_OUT, t)` maps progress `t` from 0 to 1 along a curve, and
`tween` interpolates between two values with one. [`pixzig.sequence`](page:python-api/sequence) uses
them to animate over time.

**Example:**

```python
t = self.elapsed_ms / 400
y = easing.tween(Ease.BOUNCE_OUT, start_y, floor_y, t)
```

## `ease`

```python
ease(curve: int, t: float) -> float
```

Maps progress along a curve.

| Argument | Type | Description |
|---|---|---|
| `curve` | `int` | An [`Ease`](page:python-api/constants#h2-ease). |
| `t` | `float` | The progress, clamped to 0-1 first. |

**Returns:** The eased value, 0 at the start and 1 at the end. `BACK_*` and
`ELASTIC_OUT` overshoot past 0 or 1 on the way.

## `tween`

```python
tween(curve: int, a: float, b: float, t: float) -> float
```

Interpolates between two values along a curve.

| Argument | Type | Description |
|---|---|---|
| `curve` | `int` | An [`Ease`](page:python-api/constants#h2-ease). |
| `a` | `float` | The value at `t = 0`. |
| `b` | `float` | The value at `t = 1`. |
| `t` | `float` | The progress, clamped to 0-1. |

**Returns:** The value `t` of the way from `a` to `b`.
