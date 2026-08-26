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


class Mouse:
    def __init__(self, eng):
        self._eng = eng

    @property
    def pos(self):
        x = ctypes.c_float()
        y = ctypes.c_float()
        _n.pz_mouse_pos(self._eng, ctypes.byref(x), ctypes.byref(y))
        return (x.value, y.value)

    def down(self, button: int) -> bool:
        return bool(_n.pz_mouse_button_down(self._eng, button))

    def pressed(self, button: int) -> bool:
        return bool(_n.pz_mouse_button_pressed(self._eng, button))

    def released(self, button: int) -> bool:
        return bool(_n.pz_mouse_button_released(self._eng, button))


class Gamepad:
    def __init__(self, eng, index: int):
        self._eng = eng
        self.index = index

    @property
    def connected(self) -> bool:
        return bool(_n.pz_gamepad_connected(self._eng, self.index))

    def down(self, button: int) -> bool:
        return bool(_n.pz_gamepad_button_down(self._eng, self.index, button))

    def axis(self, axis: int) -> float:
        return _n.pz_gamepad_axis(self._eng, self.index, axis)
