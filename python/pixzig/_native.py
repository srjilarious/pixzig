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


class _PzSprite(ctypes.Structure):
    """Opaque sprite handle; never inspected from Python."""


PzSpritePtr = ctypes.POINTER(_PzSprite)


class _PzCamera(ctypes.Structure):
    """Opaque camera handle; never inspected from Python."""


PzCameraPtr = ctypes.POINTER(_PzCamera)


class _PzTilemapRenderer(ctypes.Structure):
    """Opaque tilemap renderer handle; never inspected from Python."""


PzTilemapRendererPtr = ctypes.POINTER(_PzTilemapRenderer)


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
pz_render_begin_world = _sig("pz_render_begin_world", [PzEnginePtr, PzCameraPtr], None)
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
pz_gamepad_button_pressed = _sig("pz_gamepad_button_pressed", [PzEnginePtr, c_int, c_int], c_bool)
pz_gamepad_button_released = _sig("pz_gamepad_button_released", [PzEnginePtr, c_int, c_int], c_bool)
pz_gamepad_axis = _sig("pz_gamepad_axis", [PzEnginePtr, c_int, c_int], c_float)

# --- Resources -------------------------------------------------------------
pz_load_texture = _sig("pz_load_texture", [PzEnginePtr, c_char_p, c_char_p], c_int32)
pz_texture_sub = _sig("pz_texture_sub", [PzEnginePtr, c_char_p, c_char_p, c_int32, c_int32, c_int32, c_int32], c_int32)
pz_load_font = _sig("pz_load_font", [PzEnginePtr, c_char_p, c_char_p, c_float], c_int32)
pz_set_default_font = _sig("pz_set_default_font", [PzEnginePtr, c_char_p], c_int32)

# --- Sprites -----------------------------------------------------------
pz_sprite_create = _sig("pz_sprite_create", [PzEnginePtr, c_char_p], PzSpritePtr)
pz_sprite_set_pos = _sig("pz_sprite_set_pos", [PzSpritePtr, c_int32, c_int32], None)
pz_sprite_get_rect = _sig(
    "pz_sprite_get_rect",
    [PzSpritePtr, ctypes.POINTER(c_float), ctypes.POINTER(c_float), ctypes.POINTER(c_float), ctypes.POINTER(c_float)],
    None,
)
pz_sprite_draw = _sig("pz_sprite_draw", [PzSpritePtr], None)
pz_sprite_destroy = _sig("pz_sprite_destroy", [PzSpritePtr], None)

# --- Camera ----------------------------------------------------------------
pz_camera_create = _sig("pz_camera_create", [PzEnginePtr], PzCameraPtr)
pz_camera_destroy = _sig("pz_camera_destroy", [PzCameraPtr], None)
pz_camera_set_pos = _sig("pz_camera_set_pos", [PzCameraPtr, c_float, c_float], None)
pz_camera_get_pos = _sig("pz_camera_get_pos", [PzCameraPtr, ctypes.POINTER(c_float), ctypes.POINTER(c_float)], None)
pz_camera_set_zoom = _sig("pz_camera_set_zoom", [PzCameraPtr, c_float], None)
pz_camera_get_zoom = _sig("pz_camera_get_zoom", [PzCameraPtr], c_float)
pz_camera_set_bounds = _sig("pz_camera_set_bounds", [PzCameraPtr, c_float, c_float, c_float, c_float], None)
pz_camera_clear_bounds = _sig("pz_camera_clear_bounds", [PzCameraPtr], None)

# --- Tilemap -----------------------------------------------------------
pz_load_tilemap = _sig("pz_load_tilemap", [PzEnginePtr, c_char_p, c_char_p], c_int32)
pz_tilemap_renderer_create = _sig(
    "pz_tilemap_renderer_create", [PzEnginePtr, c_char_p, c_char_p], PzTilemapRendererPtr
)
pz_tilemap_renderer_destroy = _sig("pz_tilemap_renderer_destroy", [PzTilemapRendererPtr], None)
pz_tilemap_pixel_size = _sig(
    "pz_tilemap_pixel_size",
    [PzTilemapRendererPtr, c_int32, ctypes.POINTER(c_float), ctypes.POINTER(c_float)],
    None,
)
pz_tilemap_render = _sig("pz_tilemap_render", [PzTilemapRendererPtr, PzCameraPtr], None)
pz_tilemap_render_below = _sig("pz_tilemap_render_below", [PzTilemapRendererPtr, PzCameraPtr, c_float], None)
pz_tilemap_render_above = _sig("pz_tilemap_render_above", [PzTilemapRendererPtr, PzCameraPtr, c_float], None)
pz_tilemap_check_reload = _sig("pz_tilemap_check_reload", [PzTilemapRendererPtr], c_bool)

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
