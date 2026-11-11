"""Engine events: window, drag-and-drop, gamepad hot-plug and app lifecycle.

Override `App.on_event` to receive them. Keyboard, mouse and text input
aren't events here; read those each tick through `app.keyboard`,
`app.mouse` and action maps, so `pressed` stays a one-tick edge.
"""
from .constants import EventKind


class Event:
    """One engine event, handed to `App.on_event`.

    Attributes:
        kind: An `EventKind`.
        size: For `WINDOW_RESIZED`, the new `(width, height)` in window
            coordinates. `app.window` already reflects it.
        pos: For `DROP_FILE` and `DROP_TEXT`, where it was dropped in window
            coordinates. Pass it to `App.screen_to_logical` for game
            coordinates.
        path: For `DROP_FILE`, the dropped file's path.
        text: For `DROP_TEXT`, the dropped text.
        gamepad_id: For `GAMEPAD_ADDED` and `GAMEPAD_REMOVED`, the pad's id.

    Example:
            def on_event(self, event):
                if event.kind == EventKind.CLOSE_REQUESTED and self.unsaved:
                    self.cancel_close()
                    self.show_save_prompt = True
                elif event.kind == EventKind.DROP_FILE:
                    self.load_level(event.path)
    """

    __slots__ = ("kind", "size", "pos", "path", "text", "gamepad_id")

    def __init__(self, kind, size=None, pos=None, path=None, text=None, gamepad_id=None):
        self.kind = kind
        self.size = size
        self.pos = pos
        self.path = path
        self.text = text
        self.gamepad_id = gamepad_id

    @classmethod
    def _from_native(cls, ev) -> "Event":
        """Copies a borrowed `PzEvent` into a Python object that outlives
        the callback."""
        kind = ev.kind
        if kind == EventKind.WINDOW_RESIZED:
            return cls(kind, size=(ev.width, ev.height))
        if kind == EventKind.DROP_FILE:
            # Paths aren't guaranteed to be UTF-8; keep undecodable bytes
            # round-trippable the way `os.fsdecode` does.
            return cls(kind, pos=(ev.x, ev.y), path=ev.text.decode("utf-8", "surrogateescape"))
        if kind == EventKind.DROP_TEXT:
            return cls(kind, pos=(ev.x, ev.y), text=ev.text.decode("utf-8", "replace"))
        if kind in (EventKind.GAMEPAD_ADDED, EventKind.GAMEPAD_REMOVED):
            return cls(kind, gamepad_id=ev.gamepad_id)
        return cls(kind)

    def __repr__(self) -> str:
        parts = [_KIND_NAMES.get(self.kind, str(self.kind))]
        for attr in ("size", "pos", "path", "text", "gamepad_id"):
            value = getattr(self, attr)
            if value is not None:
                parts.append(f"{attr}={value!r}")
        return f"Event({', '.join(parts)})"


# EventKind value -> name, for `Event.__repr__`.
_KIND_NAMES = {value: name for name, value in vars(EventKind).items() if not name.startswith("_")}
