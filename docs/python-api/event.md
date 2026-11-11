# Events

Module `pixzig.event`. Generated from its docstrings by `tools/gen_py_docs.py`.

Engine events: window, drag-and-drop, gamepad hot-plug and app lifecycle.

Override [`App.on_event`](page:python-api/app#h3-app-on-event) to receive them. Keyboard, mouse and text input aren't events here; read those each tick through `app.keyboard`, `app.mouse` and action maps, so `pressed` stays a one-tick edge.

## `Event`

One engine event, handed to [`App.on_event`](page:python-api/app#h3-app-on-event).

| Attribute | Description |
|---|---|
| `kind` | An [`EventKind`](page:python-api/constants#h2-eventkind). |
| `size` | For `WINDOW_RESIZED`, the new `(width, height)` in window coordinates. `app.window` already reflects it. |
| `pos` | For `DROP_FILE` and `DROP_TEXT`, where it was dropped in window coordinates. Pass it to [`App.screen_to_logical`](page:python-api/app#h3-app-screen-to-logical) for game coordinates. |
| `path` | For `DROP_FILE`, the dropped file's path. |
| `text` | For `DROP_TEXT`, the dropped text. |
| `gamepad_id` | For `GAMEPAD_ADDED` and `GAMEPAD_REMOVED`, the pad's id. |

**Example:**

```python
def on_event(self, event):
    if event.kind == EventKind.CLOSE_REQUESTED and self.unsaved:
        self.cancel_close()
        self.show_save_prompt = True
    elif event.kind == EventKind.DROP_FILE:
        self.load_level(event.path)
```
