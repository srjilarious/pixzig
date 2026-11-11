# pixzig.color

Module `pixzig.color`. Generated from its docstrings by `tools/gen_py_docs.py`.

Color helpers, like `Color` on the Zig side.

Colors everywhere in pixzig's Python API are `(r, g, b)` or `(r, g, b, a)`
tuples of 0-255 values; these build and blend them. The module also has
opaque constants `WHITE`, `BLACK`, `RED`, `GREEN`, `BLUE`, `YELLOW`,
`CYAN`, `MAGENTA` and `GRAY`, plus `TRANSPARENT`.

**Example:**

```python
from pixzig import color

sky = color.hex("#3a6ea5")
dim = color.with_alpha(color.BLACK, 128)
mid = color.lerp(color.RED, color.YELLOW, 0.5)
```

## `rgb`

```python
rgb(r: int, g: int, b: int, a: int = 255)
```

Builds a color from 0-255 values.

| Argument | Type | Default | Description |
|---|---|---|---|
| `r` | `int` |  | Red. |
| `g` | `int` |  | Green. |
| `b` | `int` |  | Blue. |
| `a` | `int` | `255` | Alpha; opaque by default. |

**Returns:** The `(r, g, b, a)` tuple.

## `hex`

```python
hex(code)
```

Builds a color from a hex code.

| Argument | Description |
|---|---|
| `code` | A string (`"#ff8800"`, `"ff8800"`, `"#ff880080"` with alpha, or the short `"#f80"`) or an int (`0xff8800`, opaque). |

**Returns:** The `(r, g, b, a)` tuple.

**Raises:**

- `ValueError`: The string isn't a hex color.

## `with_alpha`

```python
with_alpha(c, a: int)
```

A color with its alpha replaced.

| Argument | Type | Description |
|---|---|---|
| `c` |  | The color. |
| `a` | `int` | The new alpha, 0-255. |

**Returns:** The `(r, g, b, a)` tuple.

## `lerp`

```python
lerp(a, b, t: float)
```

Blends between two colors, alpha included.

| Argument | Type | Description |
|---|---|---|
| `a` |  | The color at `t = 0`. |
| `b` |  | The color at `t = 1`. |
| `t` | `float` | How far from `a` to `b`, clamped to 0-1. |

**Returns:** The `(r, g, b, a)` tuple.
