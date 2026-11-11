# Shapes

Module `pixzig.shapes`. Generated from its docstrings by `tools/gen_py_docs.py`.

Rectangle drawing, reached as `App.shapes`.

Colors are `(r, g, b)` or `(r, g, b, a)` tuples of 0-255 values. Draw inside a pass ([`App.render_begin`](page:python-api/app#h3-app-render-begin) ... [`App.render_end`](page:python-api/app#h3-app-render-end)).

## `Shapes`

Draws filled and outlined rectangles. Reached as `App.shapes`.

### `Shapes.filled_rect`

```python
filled_rect(x, y, w, h, color) -> None
```

Fills a rect.

| Argument | Description |
|---|---|
| `x` | The left edge. |
| `y` | The top edge. |
| `w` | The width. |
| `h` | The height. |
| `color` | An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. |

### `Shapes.rect`

```python
rect(x, y, w, h, color, line_width: int = 1) -> None
```

Outlines a rect, the line drawn inside its bounds.

| Argument | Type | Default | Description |
|---|---|---|---|
| `x` |  |  | The left edge. |
| `y` |  |  | The top edge. |
| `w` |  |  | The width. |
| `h` |  |  | The height. |
| `color` |  |  | An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. |
| `line_width` | `int` | `1` | The line's thickness, in pixels. |

### `Shapes.enclosing_rect`

```python
enclosing_rect(x, y, w, h, color, line_width: int = 1) -> None
```

Outlines a rect, the line drawn outside its bounds.

The rect itself stays fully visible, so use it to frame something without covering its edges.

| Argument | Type | Default | Description |
|---|---|---|---|
| `x` |  |  | The left edge. |
| `y` |  |  | The top edge. |
| `w` |  |  | The width. |
| `h` |  |  | The height. |
| `color` |  |  | An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. |
| `line_width` | `int` | `1` | The line's thickness, in pixels. |
