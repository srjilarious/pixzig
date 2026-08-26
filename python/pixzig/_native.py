"""Low-level ctypes bindings to libpixzig_ffi.

Internal module: game code should use the classes in `pixzig` (App, Sprite,
shapes, text, input, keyboard/mouse/gamepad, constants) instead of calling
anything here directly.
"""
import ctypes
import os
import sys


class PixzigError(Exception):
    """Raised when a pixzig engine call fails."""


def _library_filename() -> str:
    if sys.platform == "darwin":
        return "libpixzig_ffi.dylib"
    if sys.platform == "win32":
        return "pixzig_ffi.dll"
    return "libpixzig_ffi.so"


def _find_library() -> str:
    name = _library_filename()
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(here, name),
        os.path.join(here, "..", "..", "zig-out", "python", name),
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    raise OSError(
        f"Could not find {name}. Build it with 'zig build python-ffi' from "
        f"the pixzig repo root, or place a copy next to {__file__}."
    )


_lib = ctypes.CDLL(_find_library())


class _PzEngine(ctypes.Structure):
    """Opaque engine handle; never inspected from Python."""


PzEnginePtr = ctypes.POINTER(_PzEngine)


def _sig(name, argtypes, restype):
    fn = getattr(_lib, name)
    fn.argtypes = argtypes
    fn.restype = restype
    return fn


def last_error() -> str:
    msg = _lib.pz_last_error()
    return msg.decode("utf-8") if msg else "unknown error"


def check(ok: bool) -> None:
    """Raises PixzigError with the engine's last error message if `ok` is falsy."""
    if not ok:
        raise PixzigError(last_error())


c_float = ctypes.c_float
c_int = ctypes.c_int
c_int32 = ctypes.c_int32
c_uint8 = ctypes.c_uint8
c_bool = ctypes.c_bool
c_char_p = ctypes.c_char_p

# --- Lifecycle ---------------------------------------------------------
pz_last_error = _sig("pz_last_error", [], c_char_p)
pz_init = _sig("pz_init", [c_char_p, c_int32, c_int32], PzEnginePtr)
pz_deinit = _sig("pz_deinit", [PzEnginePtr], None)

# --- Frame stepping ------------------------------------------------------
pz_should_close = _sig("pz_should_close", [PzEnginePtr], c_bool)
pz_poll_events = _sig("pz_poll_events", [PzEnginePtr], None)
pz_update_input = _sig("pz_update_input", [PzEnginePtr], None)
pz_swap_buffers = _sig("pz_swap_buffers", [PzEnginePtr], None)
pz_render_begin = _sig("pz_render_begin", [PzEnginePtr], None)
pz_render_clear = _sig("pz_render_clear", [PzEnginePtr, c_float, c_float, c_float, c_float], None)
pz_render_end = _sig("pz_render_end", [PzEnginePtr], None)

# --- Input ---------------------------------------------------------------
pz_key_down = _sig("pz_key_down", [PzEnginePtr, c_int], c_bool)
pz_key_pressed = _sig("pz_key_pressed", [PzEnginePtr, c_int], c_bool)
pz_key_released = _sig("pz_key_released", [PzEnginePtr, c_int], c_bool)
pz_mouse_pos = _sig("pz_mouse_pos", [PzEnginePtr, ctypes.POINTER(c_float), ctypes.POINTER(c_float)], None)
pz_mouse_button_down = _sig("pz_mouse_button_down", [PzEnginePtr, c_int], c_bool)
pz_mouse_button_pressed = _sig("pz_mouse_button_pressed", [PzEnginePtr, c_int], c_bool)
pz_mouse_button_released = _sig("pz_mouse_button_released", [PzEnginePtr, c_int], c_bool)
pz_gamepad_connected = _sig("pz_gamepad_connected", [PzEnginePtr, c_int], c_bool)
pz_gamepad_button_down = _sig("pz_gamepad_button_down", [PzEnginePtr, c_int, c_int], c_bool)
pz_gamepad_axis = _sig("pz_gamepad_axis", [PzEnginePtr, c_int, c_int], c_float)

# --- Resources -------------------------------------------------------------
pz_load_texture = _sig("pz_load_texture", [PzEnginePtr, c_char_p, c_char_p], c_int32)
pz_load_font = _sig("pz_load_font", [PzEnginePtr, c_char_p, c_char_p, c_float], c_int32)
pz_set_default_font = _sig("pz_set_default_font", [PzEnginePtr, c_char_p], c_int32)

# --- Sprites -----------------------------------------------------------
pz_sprite_create = _sig("pz_sprite_create", [PzEnginePtr, c_char_p], c_int32)
pz_sprite_set_pos = _sig("pz_sprite_set_pos", [PzEnginePtr, c_int32, c_int32, c_int32], None)
pz_sprite_draw = _sig("pz_sprite_draw", [PzEnginePtr, c_int32], None)
pz_sprite_destroy = _sig("pz_sprite_destroy", [PzEnginePtr, c_int32], None)

# --- Shapes and text -----------------------------------------------------
pz_draw_filled_rect = _sig(
    "pz_draw_filled_rect",
    [PzEnginePtr, c_float, c_float, c_float, c_float, c_float, c_float, c_float, c_float],
    None,
)
pz_draw_rect = _sig(
    "pz_draw_rect",
    [PzEnginePtr, c_float, c_float, c_float, c_float, c_float, c_float, c_float, c_float, c_uint8],
    None,
)
pz_draw_string = _sig("pz_draw_string", [PzEnginePtr, c_char_p, c_int32, c_int32], None)
