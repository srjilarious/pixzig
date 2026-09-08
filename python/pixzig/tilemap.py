"""Tiled map loading, chunked rendering, and runtime access. Load a map with
`PixzigApp.load_tilemap(name, path)`, then create a renderer for it with
`PixzigApp.create_tilemap_renderer(map_name, texture_name)`.

Beyond rendering, `TileMapRenderer` exposes the loaded map data: read/write
tiles by tile coordinate, query per-tile collision flags, convert between
tile and world-pixel coordinates, and walk Tiled object layers.

`layer_index` / `group_index` are raw indices into the map's layer and
object-group lists (use `layer_index("name")` / `object_group_index("name")`
to look one up). Tile values are tileset indices (0-based), -1 meaning "no
tile".
"""
import ctypes
from enum import IntFlag
from typing import NamedTuple

from . import _native as _n
from .camera import Camera


class TileFlags(IntFlag):
    """Bitmask returned by `TileMapRenderer.tile_flags`, matching the engine's
    core tile properties (set via `blocks` / `kills` custom properties in
    Tiled)."""

    NONE = 0x00
    BLOCKS_LEFT = 0x01
    BLOCKS_TOP = 0x02
    BLOCKS_RIGHT = 0x04
    BLOCKS_BOTTOM = 0x08
    BLOCKS_ALL = 0x0F
    KILLS = 0x10


class TileObject(NamedTuple):
    """One object from a Tiled object layer. `x`, `y` are the object's
    top-left in map pixels; `name`, `class_` and `props` come straight from
    Tiled (empty string / empty dict when unset)."""

    index: int
    id: int
    gid: int
    x: int
    y: int
    w: int
    h: int
    name: str
    class_: str


class TileMapRenderer:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.PixzigError("tilemap renderer already destroyed")

    # --- Rendering -------------------------------------------------------

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

    # --- Layers -------------------------------------------------------

    def layer_count(self) -> int:
        self._check_alive()
        return _n.pz_tilemap_layer_count(self._handle)

    def layer_index(self, name: str) -> int:
        """Raw index of the first layer named `name`, or -1 if there is none."""
        self._check_alive()
        return _n.pz_tilemap_layer_index(self._handle, name.encode("utf-8"))

    def layer_size(self, layer_index: int):
        """(width, height) of the layer in tiles."""
        self._check_alive()
        w, h = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_tilemap_layer_size(self._handle, int(layer_index), ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    def tile_size(self, layer_index: int):
        """(width, height) of one tile in the layer, in pixels."""
        self._check_alive()
        w, h = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_tilemap_tile_size(self._handle, int(layer_index), ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    # --- Tiles -------------------------------------------------------

    def get_tile(self, layer_index: int, tx: int, ty: int) -> int:
        """Tileset index at tile coords (tx, ty); -1 for empty or out of bounds."""
        self._check_alive()
        return _n.pz_tilemap_get_tile(self._handle, int(layer_index), int(tx), int(ty))

    def set_tile(self, layer_index: int, tx: int, ty: int, value: int) -> None:
        """Sets the tileset index at (tx, ty). Out-of-bounds coords are
        ignored. Call `refresh()` once after a batch of edits to make them
        visible."""
        self._check_alive()
        _n.pz_tilemap_set_tile(self._handle, int(layer_index), int(tx), int(ty), int(value))

    def refresh(self) -> None:
        """Marks rendered chunks dirty so `set_tile` edits show up. Chunks
        rebuild lazily as they come into view."""
        self._check_alive()
        _n.pz_tilemap_refresh(self._handle)

    # --- Collision -------------------------------------------------------

    def tile_flags(self, layer_index: int, tx: int, ty: int) -> TileFlags:
        """Collision / behaviour bitmask for the tile at (tx, ty)."""
        self._check_alive()
        return TileFlags(_n.pz_tilemap_tile_flags(self._handle, int(layer_index), int(tx), int(ty)))

    def is_blocked(self, layer_index: int, tx: int, ty: int) -> bool:
        """True when the tile at (tx, ty) has `blocks all` set."""
        self._check_alive()
        return bool(_n.pz_tilemap_tile_blocked(self._handle, int(layer_index), int(tx), int(ty)))

    def tile_property(self, layer_index: int, tx: int, ty: int, name: str) -> str:
        """A custom string property on the tileset tile at (tx, ty), or ""."""
        self._check_alive()
        raw = _n.pz_tilemap_tile_prop(
            self._handle, int(layer_index), int(tx), int(ty), name.encode("utf-8")
        )
        return raw.decode("utf-8") if raw else ""

    # --- Coordinate helpers ------------------------------------------------

    def world_to_tile(self, layer_index: int, wx: float, wy: float):
        """Tile coords (tx, ty) containing world-pixel (wx, wy)."""
        self._check_alive()
        tx, ty = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_tilemap_world_to_tile(
            self._handle, int(layer_index), float(wx), float(wy), ctypes.byref(tx), ctypes.byref(ty)
        )
        return (tx.value, ty.value)

    def tile_to_world(self, layer_index: int, tx: int, ty: int):
        """World-pixel position of the top-left corner of tile (tx, ty)."""
        self._check_alive()
        x, y = ctypes.c_float(), ctypes.c_float()
        _n.pz_tilemap_tile_to_world(
            self._handle, int(layer_index), int(tx), int(ty), ctypes.byref(x), ctypes.byref(y)
        )
        return (x.value, y.value)

    # --- Object layers ------------------------------------------------

    def object_group_count(self) -> int:
        self._check_alive()
        return _n.pz_tilemap_object_group_count(self._handle)

    def object_group_index(self, name: str) -> int:
        """Raw index of the first object group named `name`, or -1."""
        self._check_alive()
        return _n.pz_tilemap_object_group_index(self._handle, name.encode("utf-8"))

    def object_count(self, group_index: int) -> int:
        self._check_alive()
        return _n.pz_tilemap_object_count(self._handle, int(group_index))

    def object_index(self, group_index: int, name: str) -> int:
        """Index of the first object named `name` in the group, or -1."""
        self._check_alive()
        return _n.pz_tilemap_object_index(self._handle, int(group_index), name.encode("utf-8"))

    def object_by_name(self, group_index: int, name: str):
        """The first object named `name` as a `TileObject`, or None."""
        idx = self.object_index(group_index, name)
        return self.object(group_index, idx) if idx >= 0 else None

    def object(self, group_index: int, obj_index: int):
        """The object at `obj_index` in the group as a `TileObject`, or None
        if the index is out of range."""
        self._check_alive()
        gi, oi = int(group_index), int(obj_index)
        raw = _n._PzTileObject()
        if not _n.pz_tilemap_object_get(self._handle, gi, oi, ctypes.byref(raw)):
            return None
        name = _n.pz_tilemap_object_name(self._handle, gi, oi)
        cls = _n.pz_tilemap_object_class(self._handle, gi, oi)
        return TileObject(
            index=oi,
            id=raw.id,
            gid=raw.gid,
            x=raw.x,
            y=raw.y,
            w=raw.w,
            h=raw.h,
            name=name.decode("utf-8") if name else "",
            class_=cls.decode("utf-8") if cls else "",
        )

    def objects(self, group_index: int):
        """Iterates the `TileObject`s in an object group."""
        self._check_alive()
        for i in range(self.object_count(group_index)):
            obj = self.object(group_index, i)
            if obj is not None:
                yield obj

    def object_property(self, group_index: int, obj_index: int, name: str) -> str:
        """A custom string property on the object, or ""."""
        self._check_alive()
        raw = _n.pz_tilemap_object_prop(
            self._handle, int(group_index), int(obj_index), name.encode("utf-8")
        )
        return raw.decode("utf-8") if raw else ""

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_tilemap_renderer_destroy(self._handle)
            self._destroyed = True
