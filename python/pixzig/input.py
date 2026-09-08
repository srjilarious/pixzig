"""Keyboard, mouse, and gamepad state, read each frame from the engine."""
import ctypes

from . import _native as _n


class Keyboard:
    def __init__(self, eng):
        self._eng = eng

    def down(self, key: int) -> bool:
        return bool(_n.pz_key_down(self._eng, key))

    def pressed(self, key: int) -> bool:
        return bool(_n.pz_key_pressed(self._eng, key))

    def released(self, key: int) -> bool:
        return bool(_n.pz_key_released(self._eng, key))

    def text(self) -> str:
        """UTF-8 text typed this tick (layout- and IME-correct), or "" if
        none. Only meaningful while `update` is running."""
        raw = _n.pz_key_text(self._eng)
        return raw.decode("utf-8") if raw else ""

    @property
    def shift(self) -> bool:
        return bool(_n.pz_key_shift(self._eng))

    @property
    def ctrl(self) -> bool:
        return bool(_n.pz_key_ctrl(self._eng))

    @property
    def alt(self) -> bool:
        return bool(_n.pz_key_alt(self._eng))

    @property
    def super(self) -> bool:
        """Whether a super / Windows / Command key is down."""
        return bool(_n.pz_key_super(self._eng))


class Mouse:
    def __init__(self, eng):
        self._eng = eng

    def _pair(self, fn):
        x = ctypes.c_float()
        y = ctypes.c_float()
        fn(self._eng, ctypes.byref(x), ctypes.byref(y))
        return (x.value, y.value)

    @property
    def pos(self):
        """Cursor position in logical game coordinates. (-1, -1) when the
        cursor is over a letterbox / pillarbox band."""
        return self._pair(_n.pz_mouse_pos)

    @property
    def raw_pos(self):
        """Cursor position in raw window coordinates (never letterbox-clamped)."""
        return self._pair(_n.pz_mouse_raw_pos)

    @property
    def scroll(self):
        """Scroll-wheel delta accumulated this tick: (x horizontal, y vertical)."""
        return self._pair(_n.pz_mouse_scroll)

    @property
    def delta(self):
        """Mouse movement this tick, in window coordinates. In relative mode
        this is the unbounded motion."""
        return self._pair(_n.pz_mouse_delta)

    def down(self, button: int) -> bool:
        return bool(_n.pz_mouse_button_down(self._eng, button))

    def pressed(self, button: int) -> bool:
        return bool(_n.pz_mouse_button_pressed(self._eng, button))

    def released(self, button: int) -> bool:
        return bool(_n.pz_mouse_button_released(self._eng, button))

    @property
    def relative(self) -> bool:
        """Whether relative (captured) mouse mode is on."""
        return bool(_n.pz_mouse_relative(self._eng))

    def set_relative(self, enabled: bool) -> None:
        """Turns relative mouse mode on/off: the OS cursor is hidden and
        `delta` reports unbounded motion. Good for FPS-style camera control."""
        _n.check(_n.pz_mouse_set_relative(self._eng, bool(enabled)) == 0)

    def show_cursor(self, visible: bool) -> None:
        """Shows or hides the system cursor (applies process-wide)."""
        _n.pz_cursor_show(self._eng, bool(visible))


class Gamepad:
    def __init__(self, eng, index: int):
        self._eng = eng
        self.index = index

    @property
    def connected(self) -> bool:
        return bool(_n.pz_gamepad_connected(self._eng, self.index))

    def down(self, button: int) -> bool:
        return bool(_n.pz_gamepad_button_down(self._eng, self.index, button))

    def pressed(self, button: int) -> bool:
        return bool(_n.pz_gamepad_button_pressed(self._eng, self.index, button))

    def released(self, button: int) -> bool:
        return bool(_n.pz_gamepad_button_released(self._eng, self.index, button))

    def axis(self, axis: int) -> float:
        return _n.pz_gamepad_axis(self._eng, self.index, axis)
