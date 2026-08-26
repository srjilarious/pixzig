"""Tiled map loading and chunked rendering. Load a map with
`PixzigApp.load_tilemap(name, path)`, then create a renderer for it with
`PixzigApp.create_tilemap_renderer(map_name, texture_name)`.
"""
import ctypes

from . import _native as _n
from .camera import Camera


class TileMapRenderer:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.PixzigError("tilemap renderer already destroyed")

    def pixel_size(self, layer_index: int):
        """Returns the (width, height) of `layer_index` in pixels, useful for
        setting a camera's bounds to the map's extents."""
        self._check_alive()
        w, h = ctypes.c_float(), ctypes.c_float()
        _n.pz_tilemap_pixel_size(self._handle, int(layer_index), ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    def render(self, camera: Camera) -> None:
        self._check_alive()
        _n.pz_tilemap_render(self._handle, camera._handle)

    def render_below(self, camera: Camera, z: float) -> None:
        """Renders layers with z < `z_threshold`, for background layers."""
        self._check_alive()
        _n.pz_tilemap_render_below(self._handle, camera._handle, float(z))

    def render_above(self, camera: Camera, z: float) -> None:
        """Renders layers with z >= `z_threshold`, for foreground layers."""
        self._check_alive()
        _n.pz_tilemap_render_above(self._handle, camera._handle, float(z))

    def check_reload(self) -> bool:
        """Call once per frame; reloads the renderer if the underlying map
        file changed on disk (debug builds only). Returns whether it reloaded,
        so callers know to re-read `pixel_size` for camera bounds."""
        self._check_alive()
        return bool(_n.pz_tilemap_check_reload(self._handle))

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_tilemap_renderer_destroy(self._handle)
            self._destroyed = True
