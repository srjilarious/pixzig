"""Keyboard, mouse, gamepad and touch input, reached through the app.

`App.keyboard`, `App.mouse` and `App.touch` are created with the app;
`App.gamepad(i)` returns a pad slot. The engine latches input once per
update tick, so `pressed` and `released` are true for exactly one tick.
For game controls, an `ActionMap` is usually nicer than reading devices
directly.
"""
import ctypes
from collections import namedtuple

from . import _native as _n


class Finger(namedtuple("Finger", ["id", "pos", "start", "on_control"])):
    """One finger on the screen, from `Touch.fingers()`.

    Attributes:
        id: Stays the same from when the finger lands until it lifts.
        pos: Where it is, as `(x, y)` in logical game coordinates, or None
            over a letterbox bar.
        start: Where it landed, the same way.
        on_control: Whether it landed on a virtual pad control.
    """

    __slots__ = ()


class Keyboard:
    """Keyboard state, reached as `App.keyboard`.

    Keys are `Key` values naming physical positions: `Key.W` is where W sits on
    a US QWERTY board whatever the layout, so WASD stays under the same fingers
    on AZERTY or Dvorak. Read typed text with `text()`.
    """
    def __init__(self, eng):
        self._eng = eng

    def down(self, key: int) -> bool:
        """Whether a key is held.

        Args:
            key: A `Key`.

        Returns:
            True while it's held.
        """
        return bool(_n.pz_key_down(self._eng, key))

    def pressed(self, key: int) -> bool:
        """Whether a key went down this tick.

        Args:
            key: A `Key`.

        Returns:
            True for exactly one tick.
        """
        return bool(_n.pz_key_pressed(self._eng, key))

    def released(self, key: int) -> bool:
        """Whether a key went up this tick.

        Args:
            key: A `Key`.

        Returns:
            True for exactly one tick.
        """
        return bool(_n.pz_key_released(self._eng, key))

    def text(self) -> str:
        """The text typed this tick, for names, chat lines and text fields.

        It's already run through the keyboard layout, dead keys and IME, so it's
        correct for every language. Only meaningful while `update` is running.

        Returns:
            The UTF-8 text, or "" when nothing was typed.
        """
        raw = _n.pz_key_text(self._eng)
        return raw.decode("utf-8") if raw else ""

    @property
    def shift(self) -> bool:
        """Whether either Shift key is held."""
        return bool(_n.pz_key_shift(self._eng))

    @property
    def ctrl(self) -> bool:
        """Whether either Ctrl key is held."""
        return bool(_n.pz_key_ctrl(self._eng))

    @property
    def alt(self) -> bool:
        """Whether either Alt key is held."""
        return bool(_n.pz_key_alt(self._eng))

    @property
    def super(self) -> bool:
        """Whether a Super, Windows or Command key is held."""
        return bool(_n.pz_key_super(self._eng))


class Mouse:
    """Mouse state, reached as `App.mouse`."""
    def __init__(self, eng):
        self._eng = eng

    def _pair(self, fn):
        x = ctypes.c_float()
        y = ctypes.c_float()
        fn(self._eng, ctypes.byref(x), ctypes.byref(y))
        return (x.value, y.value)

    @property
    def pos(self):
        """The cursor's position in logical game coordinates, as `(x, y)`.

        `(-1, -1)` while the cursor is over a letterbox bar, outside the game area.
        """
        return self._pair(_n.pz_mouse_pos)

    @property
    def raw_pos(self):
        """The cursor's position in window coordinates, as `(x, y)`, never clamped."""
        return self._pair(_n.pz_mouse_raw_pos)

    @property
    def scroll(self):
        """The scroll wheel's movement this tick, as `(horizontal, vertical)`."""
        return self._pair(_n.pz_mouse_scroll)

    @property
    def delta(self):
        """The mouse's movement this tick in window coordinates, as `(dx, dy)`.

        In relative mode it's the unbounded motion, for mouse look.
        """
        return self._pair(_n.pz_mouse_delta)

    def down(self, button: int) -> bool:
        """Whether a mouse button is held.

        Args:
            button: A `MouseButton`.

        Returns:
            True while it's held.
        """
        return bool(_n.pz_mouse_button_down(self._eng, button))

    def pressed(self, button: int) -> bool:
        """Whether a mouse button went down this tick.

        Args:
            button: A `MouseButton`.

        Returns:
            True for exactly one tick.
        """
        return bool(_n.pz_mouse_button_pressed(self._eng, button))

    def released(self, button: int) -> bool:
        """Whether a mouse button went up this tick.

        Args:
            button: A `MouseButton`.

        Returns:
            True for exactly one tick.
        """
        return bool(_n.pz_mouse_button_released(self._eng, button))

    @property
    def relative(self) -> bool:
        """Whether relative (captured) mouse mode is on."""
        return bool(_n.pz_mouse_relative(self._eng))

    def set_relative(self, enabled: bool) -> None:
        """Turns relative mouse mode on or off.

        In relative mode the cursor is hidden and the window edge no longer stops
        it, and `delta` reports unbounded motion. Good for first-person cameras.

        Args:
            enabled: True to capture the mouse, False to release it.

        Raises:
            pixzig.Error: The platform refused.
        """
        _n.check(_n.pz_mouse_set_relative(self._eng, bool(enabled)) == 0)

    def show_cursor(self, visible: bool) -> None:
        """Shows or hides the system cursor. It applies process-wide.

        Args:
            visible: True to show it.
        """
        _n.pz_cursor_show(self._eng, bool(visible))


class Touch:
    """Touchscreen input, reached as `App.touch`.

    Positions are in logical game coordinates, the same space as `mouse.pos`,
    or None over a letterbox bar.
    """

    def __init__(self, eng):
        self._eng = eng

    def tapped(self):
        """Where a finger landed this tick, like `mouse.pressed` for touch.

        A landing counts the moment the finger touches down, so a tap shorter than a
        tick still counts, and so does one that then drags.

        Returns:
            The first landing inside the game area as `(x, y)`, or None. See `taps`
            for every landing when several fingers touch down at once.
        """
        x, y = ctypes.c_float(), ctypes.c_float()
        if _n.pz_touch_tapped(self._eng, ctypes.byref(x), ctypes.byref(y)):
            return (x.value, y.value)
        return None

    def taps(self):
        """Every finger landing this tick inside the game area.

        Returns:
            A list of `(x, y)`.
        """
        out = []
        x, y = ctypes.c_float(), ctypes.c_float()
        for index in range(_n.pz_touch_tap_count(self._eng)):
            if _n.pz_touch_tap_at(self._eng, index, ctypes.byref(x), ctypes.byref(y)):
                out.append((x.value, y.value))
        return out

    @property
    def finger_count(self) -> int:
        """How many fingers are on the screen."""
        return _n.pz_touch_finger_count(self._eng)

    def fingers(self):
        """The fingers on the screen right now.

        Returns:
            A list of `Finger`.
        """
        out = []
        f = _n.PzFinger()
        index = 0
        while _n.pz_touch_finger(self._eng, index, ctypes.byref(f)):
            out.append(
                Finger(
                    id=f.id,
                    pos=(f.x, f.y) if f.has_pos else None,
                    start=(f.start_x, f.start_y) if f.has_start else None,
                    on_control=bool(f.on_control),
                )
            )
            index += 1
        return out


class Gamepad:
    """One gamepad slot. Get it with `App.gamepad(index)`.

    Buttons use positional names (`GamepadButton.A` is the bottom face button).
    Pads can be plugged in and out while the game runs; `EventKind.GAMEPAD_ADDED`
    and `GAMEPAD_REMOVED` arrive through `App.on_event`.

    Attributes:
        index: The slot this reads.
    """
    def __init__(self, eng, index: int):
        self._eng = eng
        self.index = index

    @property
    def connected(self) -> bool:
        """Whether a pad is plugged into this slot."""
        return bool(_n.pz_gamepad_connected(self._eng, self.index))

    def down(self, button: int) -> bool:
        """Whether a button is held.

        Args:
            button: A `GamepadButton`.

        Returns:
            True while it's held.
        """
        return bool(_n.pz_gamepad_button_down(self._eng, self.index, button))

    def pressed(self, button: int) -> bool:
        """Whether a button went down this tick.

        Args:
            button: A `GamepadButton`.

        Returns:
            True for exactly one tick.
        """
        return bool(_n.pz_gamepad_button_pressed(self._eng, self.index, button))

    def released(self, button: int) -> bool:
        """Whether a button went up this tick.

        Args:
            button: A `GamepadButton`.

        Returns:
            True for exactly one tick.
        """
        return bool(_n.pz_gamepad_button_released(self._eng, self.index, button))

    def axis(self, axis: int) -> float:
        """Reads a stick or trigger.

        Args:
            axis: A `GamepadAxis`.

        Returns:
            -1 to 1 for sticks, 0 to 1 for triggers. No deadzone is applied; an
            `ActionMap` axis binding adds one.
        """
        return _n.pz_gamepad_axis(self._eng, self.index, axis)
