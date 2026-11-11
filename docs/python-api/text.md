# Text

Module `pixzig.text`. Generated from its docstrings by `tools/gen_py_docs.py`.

TrueType text, reached as `App.text`.

A draw takes the style as keyword arguments, like the engine's
`drawText(text, pos, TextStyle)`. `y` is the top of the text's line box, and
`x` is its left edge, middle or right edge by `align`. Coordinates are in
the current pass's space and may be fractional.

**Example:**

```python
app.text.load_font("ui", "assets/Roboto-Medium.ttf", 16)
app.text.set_font("ui")
app.text.draw("Score: 40", 8, 8, color=(255, 220, 0))
app.text.draw("PAUSED", 160, 100, scale=2, align=TextAlign.CENTER, shadow=(0, 0, 0))
```

## `Text`

Loads fonts and draws text. Reached as `App.text`.

The engine's embedded default font (Karla, 20 pixels) is ready without
loading anything.

### `Text.load_font`

```python
load_font(name: str, ttf_path: str, size: float) -> None
```

Loads a TrueType or OpenType font at a pixel size.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The name to register it under, for [`set_font`](page:python-api/text#h3-text-set-font) and `font=`. |
| `ttf_path` | `str` | The font file, relative to the app's asset root. |
| `size` | `float` | The pixel size to rasterize at. Load the size you'll draw at for crisp text rather than scaling. |

**Raises:**

- `FileNotFoundError`: The file doesn't exist; the message names the resolved path and the asset root.
- `pixzig.Error`: The font couldn't be read.

### `Text.set_font`

```python
set_font(name: str) -> None
```

Makes a font the default, used by [`draw`](page:python-api/text#h3-text-draw) and [`measure`](page:python-api/text#h3-text-measure) without `font=`.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | A font from [`load_font`](page:python-api/text#h3-text-load-font) or a manifest. |

**Raises:**

- `pixzig.Error`: No font has that name.

### `Text.set_pixelated`

```python
set_pixelated(name: str, pixelated: bool = True) -> None
```

Switches a font between hard pixel edges and smooth sampling.

Pixel-art fonts drawn at a `scale` above 1 want hard edges.

| Argument | Type | Default | Description |
|---|---|---|---|
| `name` | `str` |  | The font's name. |
| `pixelated` | `bool` | `True` | True for hard edges, False for smooth sampling. |

**Raises:**

- `pixzig.Error`: No font has that name.

### `Text.draw`

```python
draw(
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
)
```

Draws a string. Call it inside a render pass.

| Argument | Type | Default | Description |
|---|---|---|---|
| `text` | `str` |  | The UTF-8 string. Glyphs the font lacks draw as empty boxes. |
| `x` | `float` |  | The left edge, middle or right edge, by `align`. |
| `y` | `float` |  | The top of the line box. |
| `color` |  | `(255, 255, 255)` | An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. |
| `scale` | `float` | `1.0` | Stretches the font's own pixels, so large scales get soft. |
| `font` | `str` | `None` | A font name, or None for the default font. |
| `align` | `int` | `TextAlign.LEFT` | A [`TextAlign`](page:python-api/constants#h2-textalign): whether `x` is the left edge, middle or right edge. |
| `clip` |  | `None` | An `(x, y, w, h)` rect the glyphs are cut to, for text in a scrolling panel. |
| `shadow` |  | `None` | A color to draw a drop shadow in, or None for no shadow. |
| `shadow_offset` |  | `(1, 1)` | How far the shadow sits from the text, as `(dx, dy)`. |

**Returns:** The `(width, height)` it took, the same as [`measure`](page:python-api/text#h3-text-measure).

**Raises:**

- `pixzig.Error`: No font has the name given.

### `Text.measure`

```python
measure(text: str, scale: float = 1.0, font: str = None)
```

Measures a string without drawing it.

The height is the font's line box (ascent plus descent), so every string in
one font measures the same height and centering a measured string centers
it as drawn.

| Argument | Type | Default | Description |
|---|---|---|---|
| `text` | `str` |  | The UTF-8 string. |
| `scale` | `float` | `1.0` | The scale it would be drawn at. |
| `font` | `str` | `None` | A font name, or None for the default font. |

**Returns:** The `(width, height)`, or `(0, 0)` when there's no font.

**Raises:**

- `pixzig.Error`: No font has the name given.

### `Text.line_height`

```python
line_height(font: str = None)
```

A font's line spacing at scale 1, for stacking rows of text.

| Argument | Type | Default | Description |
|---|---|---|---|
| `font` | `str` | `None` | A font name, or None for the default font. |

**Returns:** The spacing in pixels (ascent, descent and line gap), or None when
there's no such font.
