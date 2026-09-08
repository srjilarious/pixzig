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


class _PzAssetManifest(ctypes.Structure):
    """Opaque asset manifest handle; never inspected from Python."""


PzAssetManifestPtr = ctypes.POINTER(_PzAssetManifest)


class _PzActionMap(ctypes.Structure):
    """Opaque action map handle; never inspected from Python."""


PzActionMapPtr = ctypes.POINTER(_PzActionMap)


class _PzActor(ctypes.Structure):
    """Opaque animated-actor handle; never inspected from Python."""


PzActorPtr = ctypes.POINTER(_PzActor)


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
_ip = ctypes.POINTER(c_int32)
_fp = ctypes.POINTER(c_float)

# --- Lifecycle ---------------------------------------------------------
pz_last_error = _sig("pz_last_error", [], c_char_p)
pz_init = _sig("pz_init", [c_char_p, c_int32, c_int32], PzEnginePtr)
pz_deinit = _sig("pz_deinit", [PzEnginePtr], None)

# --- Frame stepping ------------------------------------------------------
pz_should_close = _sig("pz_should_close", [PzEnginePtr], c_bool)
pz_poll_events = _sig("pz_poll_events", [PzEnginePtr], None)
pz_update_input = _sig("pz_update_input", [PzEnginePtr], None)
pz_finish_tick = _sig("pz_finish_tick", [PzEnginePtr], None)
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
pz_sprite_set_size = _sig("pz_sprite_set_size", [PzSpritePtr, c_float, c_float], None)
pz_sprite_set_scale = _sig("pz_sprite_set_scale", [PzSpritePtr, c_float, c_float], None)
pz_sprite_set_rotate = _sig("pz_sprite_set_rotate", [PzSpritePtr, c_int], None)
pz_sprite_set_src_rect = _sig(
    "pz_sprite_set_src_rect", [PzSpritePtr, c_int32, c_int32, c_int32, c_int32], None
)
pz_sprite_set_tint = _sig("pz_sprite_set_tint", [PzSpritePtr, c_float, c_float, c_float, c_float], None)
pz_sprite_get_size = _sig(
    "pz_sprite_get_size", [PzSpritePtr, ctypes.POINTER(c_float), ctypes.POINTER(c_float)], None
)

# --- Audio -----------------------------------------------------------------
pz_audio_load = _sig("pz_audio_load", [PzEnginePtr, c_char_p, c_char_p], c_int32)
pz_audio_play = _sig("pz_audio_play", [PzEnginePtr, c_char_p], c_int32)

# --- Sprite animation ----------------------------------------------------
pz_anim_load_file = _sig("pz_anim_load_file", [PzEnginePtr, c_char_p], c_int32)
pz_anim_new_sequence = _sig("pz_anim_new_sequence", [PzEnginePtr, c_char_p, c_bool], c_int32)
pz_anim_seq_add_frame = _sig(
    "pz_anim_seq_add_frame", [PzEnginePtr, c_char_p, c_char_p, ctypes.c_double, c_int], c_int32
)
pz_anim_add_state = _sig(
    "pz_anim_add_state", [PzEnginePtr, c_char_p, c_char_p, c_char_p, c_int], c_int32
)
pz_actor_create = _sig("pz_actor_create", [PzEnginePtr], PzActorPtr)
pz_actor_destroy = _sig("pz_actor_destroy", [PzActorPtr], None)
pz_actor_add_state = _sig("pz_actor_add_state", [PzActorPtr, c_char_p], c_int32)
pz_actor_set_state = _sig("pz_actor_set_state", [PzActorPtr, c_char_p, PzSpritePtr], None)
pz_actor_update = _sig("pz_actor_update", [PzActorPtr, ctypes.c_double, PzSpritePtr], None)

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


class _PzTileObject(ctypes.Structure):
    _fields_ = [
        ("id", c_int32),
        ("gid", c_int32),
        ("x", c_int32),
        ("y", c_int32),
        ("w", c_int32),
        ("h", c_int32),
    ]


# --- Tilemap runtime access -------------------------------------------------
pz_tilemap_layer_count = _sig("pz_tilemap_layer_count", [PzTilemapRendererPtr], c_int32)
pz_tilemap_layer_index = _sig("pz_tilemap_layer_index", [PzTilemapRendererPtr, c_char_p], c_int32)
pz_tilemap_layer_size = _sig("pz_tilemap_layer_size", [PzTilemapRendererPtr, c_int32, _ip, _ip], None)
pz_tilemap_tile_size = _sig("pz_tilemap_tile_size", [PzTilemapRendererPtr, c_int32, _ip, _ip], None)
pz_tilemap_get_tile = _sig("pz_tilemap_get_tile", [PzTilemapRendererPtr, c_int32, c_int32, c_int32], c_int32)
pz_tilemap_set_tile = _sig(
    "pz_tilemap_set_tile", [PzTilemapRendererPtr, c_int32, c_int32, c_int32, c_int32], None
)
pz_tilemap_refresh = _sig("pz_tilemap_refresh", [PzTilemapRendererPtr], None)
pz_tilemap_tile_flags = _sig(
    "pz_tilemap_tile_flags", [PzTilemapRendererPtr, c_int32, c_int32, c_int32], c_int32
)
pz_tilemap_tile_blocked = _sig(
    "pz_tilemap_tile_blocked", [PzTilemapRendererPtr, c_int32, c_int32, c_int32], c_bool
)
pz_tilemap_tile_prop = _sig(
    "pz_tilemap_tile_prop", [PzTilemapRendererPtr, c_int32, c_int32, c_int32, c_char_p], c_char_p
)
pz_tilemap_world_to_tile = _sig(
    "pz_tilemap_world_to_tile", [PzTilemapRendererPtr, c_int32, c_float, c_float, _ip, _ip], None
)
pz_tilemap_tile_to_world = _sig(
    "pz_tilemap_tile_to_world", [PzTilemapRendererPtr, c_int32, c_int32, c_int32, _fp, _fp], None
)
pz_tilemap_object_group_count = _sig("pz_tilemap_object_group_count", [PzTilemapRendererPtr], c_int32)
pz_tilemap_object_group_index = _sig(
    "pz_tilemap_object_group_index", [PzTilemapRendererPtr, c_char_p], c_int32
)
pz_tilemap_object_count = _sig("pz_tilemap_object_count", [PzTilemapRendererPtr, c_int32], c_int32)
pz_tilemap_object_index = _sig(
    "pz_tilemap_object_index", [PzTilemapRendererPtr, c_int32, c_char_p], c_int32
)
pz_tilemap_object_get = _sig(
    "pz_tilemap_object_get",
    [PzTilemapRendererPtr, c_int32, c_int32, ctypes.POINTER(_PzTileObject)],
    c_bool,
)
pz_tilemap_object_name = _sig(
    "pz_tilemap_object_name", [PzTilemapRendererPtr, c_int32, c_int32], c_char_p
)
pz_tilemap_object_class = _sig(
    "pz_tilemap_object_class", [PzTilemapRendererPtr, c_int32, c_int32], c_char_p
)
pz_tilemap_object_prop = _sig(
    "pz_tilemap_object_prop", [PzTilemapRendererPtr, c_int32, c_int32, c_char_p], c_char_p
)

# --- Asset manifests ---------------------------------------------------
pz_manifest_load = _sig("pz_manifest_load", [PzEnginePtr, c_char_p], PzAssetManifestPtr)
pz_manifest_load_group = _sig("pz_manifest_load_group", [PzAssetManifestPtr, c_char_p], c_int32)
pz_manifest_unload_group = _sig("pz_manifest_unload_group", [PzAssetManifestPtr, c_char_p], None)
pz_manifest_destroy = _sig("pz_manifest_destroy", [PzAssetManifestPtr], None)

# --- Action maps ---------------------------------------------------------
pz_action_map_create = _sig("pz_action_map_create", [PzEnginePtr], PzActionMapPtr)
pz_action_map_destroy = _sig("pz_action_map_destroy", [PzActionMapPtr], None)
pz_action_map_update = _sig("pz_action_map_update", [PzActionMapPtr, ctypes.c_double], None)
pz_action_bind_key = _sig("pz_action_bind_key", [PzActionMapPtr, c_int32, c_int], c_int32)
pz_action_bind_mouse_button = _sig("pz_action_bind_mouse_button", [PzActionMapPtr, c_int32, c_int], c_int32)
pz_action_bind_gamepad_button = _sig("pz_action_bind_gamepad_button", [PzActionMapPtr, c_int32, c_int], c_int32)
pz_action_bind_axis_buttons = _sig(
    "pz_action_bind_axis_buttons", [PzActionMapPtr, c_int32, c_int, c_int], c_int32
)
pz_action_bind_axis_gamepad = _sig(
    "pz_action_bind_axis_gamepad", [PzActionMapPtr, c_int32, c_int, c_float], c_int32
)
pz_action_bind_axis_mouse = _sig(
    "pz_action_bind_axis_mouse", [PzActionMapPtr, c_int32, c_int, c_float, c_float], c_int32
)
pz_action_up = _sig("pz_action_up", [PzActionMapPtr, c_int32], c_bool)
pz_action_down = _sig("pz_action_down", [PzActionMapPtr, c_int32], c_bool)
pz_action_pressed = _sig("pz_action_pressed", [PzActionMapPtr, c_int32], c_bool)
pz_action_released = _sig("pz_action_released", [PzActionMapPtr, c_int32], c_bool)
pz_action_axis = _sig("pz_action_axis", [PzActionMapPtr, c_int32], c_float)

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

# --- Window / viewport -------------------------------------------------
pz_window_size = _sig("pz_window_size", [PzEnginePtr, _ip, _ip], None)
pz_framebuffer_size = _sig("pz_framebuffer_size", [PzEnginePtr, _ip, _ip], None)
pz_logical_size = _sig("pz_logical_size", [PzEnginePtr, _ip, _ip], None)
pz_window_scale_factor = _sig("pz_window_scale_factor", [PzEnginePtr], c_float)
pz_window_set_title = _sig("pz_window_set_title", [PzEnginePtr, c_char_p], None)
pz_window_set_size = _sig("pz_window_set_size", [PzEnginePtr, c_int32, c_int32], None)
pz_window_set_fullscreen = _sig("pz_window_set_fullscreen", [PzEnginePtr, c_bool], c_int32)
pz_window_is_fullscreen = _sig("pz_window_is_fullscreen", [PzEnginePtr], c_bool)

# --- Coordinate transforms -------------------------------------------------
pz_screen_to_logical = _sig("pz_screen_to_logical", [PzEnginePtr, c_float, c_float, _fp, _fp], c_bool)
pz_logical_to_screen = _sig("pz_logical_to_screen", [PzEnginePtr, c_float, c_float, _fp, _fp], None)
pz_screen_to_world = _sig(
    "pz_screen_to_world", [PzEnginePtr, PzCameraPtr, c_float, c_float, _fp, _fp], c_bool
)
pz_world_to_screen = _sig(
    "pz_world_to_screen", [PzEnginePtr, PzCameraPtr, c_float, c_float, _fp, _fp], None
)

# --- Mouse extras --------------------------------------------------------
pz_mouse_scroll = _sig("pz_mouse_scroll", [PzEnginePtr, _fp, _fp], None)
pz_mouse_delta = _sig("pz_mouse_delta", [PzEnginePtr, _fp, _fp], None)
pz_mouse_raw_pos = _sig("pz_mouse_raw_pos", [PzEnginePtr, _fp, _fp], None)
pz_mouse_set_relative = _sig("pz_mouse_set_relative", [PzEnginePtr, c_bool], c_int32)
pz_mouse_relative = _sig("pz_mouse_relative", [PzEnginePtr], c_bool)
pz_cursor_show = _sig("pz_cursor_show", [PzEnginePtr, c_bool], None)

# --- Keyboard text + modifiers -----------------------------------------
pz_key_text = _sig("pz_key_text", [PzEnginePtr], c_char_p)
pz_key_shift = _sig("pz_key_shift", [PzEnginePtr], c_bool)
pz_key_ctrl = _sig("pz_key_ctrl", [PzEnginePtr], c_bool)
pz_key_alt = _sig("pz_key_alt", [PzEnginePtr], c_bool)
pz_key_super = _sig("pz_key_super", [PzEnginePtr], c_bool)
