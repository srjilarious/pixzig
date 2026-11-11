# Render Targets

Module `pixzig.render_target`. Generated from its docstrings by `tools/gen_py_docs.py`.

Offscreen images to draw into, then draw like a texture.

Create one with [`App.create_render_target`](page:python-api/app#h3-app-create-render-target) and send passes into it with [`App.set_target`](page:python-api/app#h3-app-set-target). Use one to render a low-resolution game and scale it up, to run a shader over the whole frame, or to draw something once and reuse it.

**Example:**

```python
self.scene = self.create_render_target(320, 180)

def render(self, alpha):
    self.set_target(self.scene)   # later passes draw into the image
    self.render_begin()
    ...                           # the game at 320x180
    self.render_end()
    self.set_target(None)         # back to the screen

    w, h = self.window.framebuffer_size
    self.render_begin_screen()
    self.set_shader("crt")        # post-process the whole frame
    self.scene.draw(0, 0, w, h)
    self.render_end()
```

## `RenderTarget`

An offscreen image. Create one with [`App.create_render_target`](page:python-api/app#h3-app-create-render-target).

### `RenderTarget.size`

```python
size  # property
```

The image's `(width, height)`, in pixels.

### `RenderTarget.resize`

```python
resize(w: int, h: int) -> None
```

Reallocates the image at a new size, e.g. to follow the window.

What was drawn is discarded and it starts transparent. Call it outside any pass that draws into it.

| Argument | Type | Description |
|---|---|---|
| `w` | `int` | The new width, in pixels. |
| `h` | `int` | The new height, in pixels. |

**Raises:**

- `pixzig.Error`: The new image couldn't be created.

### `RenderTarget.draw`

```python
draw(x: float, y: float, w: float, h: float, tint=(255, 255, 255, 255)) -> None
```

Draws the image upright into a rect of the current pass.

To draw a target cleared to a transparent color without dark edges, call `set_blend(BlendMode.PREMULTIPLIED)` first.

| Argument | Type | Default | Description |
|---|---|---|---|
| `x` | `float` |  | The rect's left edge. |
| `y` | `float` |  | The rect's top edge. |
| `w` | `float` |  | The rect's width. |
| `h` | `float` |  | The rect's height. |
| `tint` |  | `(255, 255, 255, 255)` | Multiplies the image, an `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. |

### `RenderTarget.destroy`

```python
destroy() -> None
```

Frees the target now instead of when the app shuts down.

Calling it twice does nothing. Using it afterwards raises.
