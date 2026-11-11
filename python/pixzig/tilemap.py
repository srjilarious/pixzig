"""Tiled maps: drawing them and reading or editing their data.

Load a map with `App.load_tilemap(name, path)`, then create a renderer with
`App.create_tilemap_renderer(map_name)`; it finds the tileset image named
in the `.tmx` itself. Besides drawing, `TileMapRenderer` reads and writes
tiles, reports per-tile collision flags and properties, converts between
tile and world coordinates, and walks Tiled object layers.

`layer_index` and `group_index` arguments are indices into the map's layer
and object group lists; look one up by name with `layer_index("name")` or
`object_group_index("name")`. Tile values are 0-based tileset indices, with
-1 for no tile.

Example:
        self.load_tilemap("level1", "assets/level1.tmx")
        self.map = self.create_tilemap_renderer("level1")
        walls = self.map.layer_index("walls")
        w, h = self.map.pixel_size(walls)
        self.camera.set_bounds(0, 0, w, h)

        group = self.map.object_group_index("spawns")
        player = self.map.object_by_name(group, "player")
        self.hero.sprite.set_pos(player.x, player.y)
"""
import ctypes
from enum import IntFlag
from typing import NamedTuple

from . import _native as _n
from .camera import Camera


class TileFlags(IntFlag):
    """Collision and behavior flags on a tile, from `TileMapRenderer.tile_flags`.

    They come from the `blocks` and `kills` custom properties on tileset tiles
    in Tiled, and match the engine's core tile flags.

    Attributes:
        NONE: No flags.
        BLOCKS_LEFT: Solid from the left (`blocks = left`).
        BLOCKS_TOP: Solid from above (`blocks = top`); a one-way platform.
        BLOCKS_RIGHT: Solid from the right (`blocks = right`).
        BLOCKS_BOTTOM: Solid from below (`blocks = bottom`).
        BLOCKS_ALL: Solid from every side (`blocks = all`).
        KILLS: Deadly (`kills = true`).
    """

    NONE = 0x00
    BLOCKS_LEFT = 0x01
    BLOCKS_TOP = 0x02
    BLOCKS_RIGHT = 0x04
    BLOCKS_BOTTOM = 0x08
    BLOCKS_ALL = 0x0F
    KILLS = 0x10


class TileObject(NamedTuple):
    """One object from a Tiled object layer.

    Attributes:
        index: Its index in the group, for `object_property`.
        id: Its Tiled object id.
        gid: The tile it shows, for tile objects; 0 otherwise.
        x: The left edge, in map pixels.
        y: The top edge, in map pixels.
        w: The width, in pixels.
        h: The height, in pixels.
        name: Its name in Tiled, or "".
        class_: Its class in Tiled (or the older `type`), or "".
    """

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
    """Draws a Tiled map and gives access to its data.

    Create one with `App.create_tilemap_renderer()`. It only draws the parts of
    the map the camera can see. Give layers a `z` float property in Tiled to
    draw some behind your sprites and some in front with `render_below` and
    `render_above`.
    """
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.Error("tilemap renderer already destroyed (or the app has shut down)")

    # --- Rendering -------------------------------------------------------

    def pixel_size(self, layer_index: int):
        """A layer's size in pixels, e.g. for a camera's bounds.

        Args:
            layer_index: The layer.

        Returns:
            The `(width, height)`.
        """
        self._check_alive()
        w, h = ctypes.c_float(), ctypes.c_float()
        _n.pz_tilemap_pixel_size(self._handle, int(layer_index), ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    def render(self, camera: Camera) -> None:
        """Draws every layer in `z` order. Call it inside a world render pass.

        Args:
            camera: The `Camera` the pass draws through.
        """
        self._check_alive()
        _n.pz_tilemap_render(self._handle, camera._handle)

    def render_below(self, camera: Camera, z: float) -> None:
        """Draws the layers whose `z` property is below a threshold: the background.

        Args:
            camera: The `Camera` the pass draws through.
            z: The threshold.
        """
        self._check_alive()
        _n.pz_tilemap_render_below(self._handle, camera._handle, float(z))

    def render_above(self, camera: Camera, z: float) -> None:
        """Draws the layers whose `z` property is at or above a threshold: the
        foreground.

        Args:
            camera: The `Camera` the pass draws through.
            z: The threshold.
        """
        self._check_alive()
        _n.pz_tilemap_render_above(self._handle, camera._handle, float(z))

    def check_reload(self) -> bool:
        """Reloads the map if its file changed on disk. Call it once per frame.

        Only debug engine builds watch files.

        Returns:
            True when it reloaded, so the game can re-read `pixel_size` for camera
            bounds or anything else it took from the map.
        """
        self._check_alive()
        return bool(_n.pz_tilemap_check_reload(self._handle))

    # --- Layers -------------------------------------------------------

    def layer_count(self) -> int:
        """How many tile layers the map has."""
        self._check_alive()
        return _n.pz_tilemap_layer_count(self._handle)

    def layer_index(self, name: str) -> int:
        """Looks a tile layer up by name.

        Args:
            name: The layer's name in Tiled.

        Returns:
            The index of the first layer with that name, or -1.
        """
        self._check_alive()
        return _n.pz_tilemap_layer_index(self._handle, name.encode("utf-8"))

    def layer_size(self, layer_index: int):
        """A layer's size in tiles.

        Args:
            layer_index: The layer.

        Returns:
            The `(width, height)`.
        """
        self._check_alive()
        w, h = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_tilemap_layer_size(self._handle, int(layer_index), ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    def tile_size(self, layer_index: int):
        """The size of one tile in a layer.

        Args:
            layer_index: The layer.

        Returns:
            The `(width, height)` in pixels.
        """
        self._check_alive()
        w, h = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_tilemap_tile_size(self._handle, int(layer_index), ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    # --- Tiles -------------------------------------------------------

    def get_tile(self, layer_index: int, tx: int, ty: int) -> int:
        """Reads a tile.

        Args:
            layer_index: The layer.
            tx: The tile column.
            ty: The tile row.

        Returns:
            The tileset index, or -1 for an empty cell or one outside the layer.
        """
        self._check_alive()
        return _n.pz_tilemap_get_tile(self._handle, int(layer_index), int(tx), int(ty))

    def set_tile(self, layer_index: int, tx: int, ty: int, value: int) -> None:
        """Changes a tile. Cells outside the layer are ignored.

        Call `refresh()` once after a batch of edits to make them visible.

        Args:
            layer_index: The layer.
            tx: The tile column.
            ty: The tile row.
            value: The tileset index, or -1 to clear the cell.
        """
        self._check_alive()
        _n.pz_tilemap_set_tile(self._handle, int(layer_index), int(tx), int(ty), int(value))

    def refresh(self) -> None:
        """Makes `set_tile` edits visible.

        Drawn chunks are marked stale and rebuilt as they come into view.
        """
        self._check_alive()
        _n.pz_tilemap_refresh(self._handle)

    # --- Collision -------------------------------------------------------

    def tile_flags(self, layer_index: int, tx: int, ty: int) -> TileFlags:
        """A tile's collision and behavior flags.

        Args:
            layer_index: The layer.
            tx: The tile column.
            ty: The tile row.

        Returns:
            The `TileFlags`.
        """
        self._check_alive()
        return TileFlags(_n.pz_tilemap_tile_flags(self._handle, int(layer_index), int(tx), int(ty)))

    def is_blocked(self, layer_index: int, tx: int, ty: int) -> bool:
        """Whether a tile is solid from every side (`TileFlags.BLOCKS_ALL`).

        Args:
            layer_index: The layer.
            tx: The tile column.
            ty: The tile row.

        Returns:
            True for a wall.
        """
        self._check_alive()
        return bool(_n.pz_tilemap_tile_blocked(self._handle, int(layer_index), int(tx), int(ty)))

    def tile_property(self, layer_index: int, tx: int, ty: int, name: str) -> str:
        """Reads a custom property on a tile's tileset entry.

        Args:
            layer_index: The layer.
            tx: The tile column.
            ty: The tile row.
            name: The property's name.

        Returns:
            The value as a string, or "" when it isn't set.
        """
        self._check_alive()
        raw = _n.pz_tilemap_tile_prop(
            self._handle, int(layer_index), int(tx), int(ty), name.encode("utf-8")
        )
        return raw.decode("utf-8") if raw else ""

    # --- Coordinate helpers ------------------------------------------------

    def world_to_tile(self, layer_index: int, wx: float, wy: float):
        """The tile that contains a world point.

        Args:
            layer_index: The layer, for its tile size.
            wx: The world x, in pixels.
            wy: The world y, in pixels.

        Returns:
            The `(tx, ty)`.
        """
        self._check_alive()
        tx, ty = ctypes.c_int32(), ctypes.c_int32()
        _n.pz_tilemap_world_to_tile(
            self._handle, int(layer_index), float(wx), float(wy), ctypes.byref(tx), ctypes.byref(ty)
        )
        return (tx.value, ty.value)

    def tile_to_world(self, layer_index: int, tx: int, ty: int):
        """Where a tile's top-left corner is in the world.

        Args:
            layer_index: The layer, for its tile size.
            tx: The tile column.
            ty: The tile row.

        Returns:
            The `(x, y)` in world pixels.
        """
        self._check_alive()
        x, y = ctypes.c_float(), ctypes.c_float()
        _n.pz_tilemap_tile_to_world(
            self._handle, int(layer_index), int(tx), int(ty), ctypes.byref(x), ctypes.byref(y)
        )
        return (x.value, y.value)

    # --- Object layers ------------------------------------------------

    def object_group_count(self) -> int:
        """How many object layers the map has."""
        self._check_alive()
        return _n.pz_tilemap_object_group_count(self._handle)

    def object_group_index(self, name: str) -> int:
        """Looks an object layer up by name.

        Args:
            name: The layer's name in Tiled.

        Returns:
            The index of the first object group with that name, or -1.
        """
        self._check_alive()
        return _n.pz_tilemap_object_group_index(self._handle, name.encode("utf-8"))

    def object_count(self, group_index: int) -> int:
        """How many objects are in an object group.

        Args:
            group_index: The object group.

        Returns:
            The count.
        """
        self._check_alive()
        return _n.pz_tilemap_object_count(self._handle, int(group_index))

    def object_index(self, group_index: int, name: str) -> int:
        """Looks an object up by name.

        Args:
            group_index: The object group.
            name: The object's name in Tiled.

        Returns:
            The index of the first object with that name, or -1.
        """
        self._check_alive()
        return _n.pz_tilemap_object_index(self._handle, int(group_index), name.encode("utf-8"))

    def object_by_name(self, group_index: int, name: str):
        """Finds an object by name, e.g. a spawn point.

        Args:
            group_index: The object group.
            name: The object's name in Tiled.

        Returns:
            The first `TileObject` with that name, or None.
        """
        idx = self.object_index(group_index, name)
        return self.object(group_index, idx) if idx >= 0 else None

    def object(self, group_index: int, obj_index: int):
        """Reads one object.

        Args:
            group_index: The object group.
            obj_index: The object's index in the group.

        Returns:
            The `TileObject`, or None when the index is out of range.
        """
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
        """Iterates the objects in an object group.

        Args:
            group_index: The object group.

        Yields:
            Each `TileObject` in order.
        """
        self._check_alive()
        for i in range(self.object_count(group_index)):
            obj = self.object(group_index, i)
            if obj is not None:
                yield obj

    def object_property(self, group_index: int, obj_index: int, name: str) -> str:
        """Reads a custom property on an object.

        Args:
            group_index: The object group.
            obj_index: The object's index in the group (`TileObject.index`).
            name: The property's name.

        Returns:
            The value as a string, or "" when it isn't set.
        """
        self._check_alive()
        raw = _n.pz_tilemap_object_prop(
            self._handle, int(group_index), int(obj_index), name.encode("utf-8")
        )
        return raw.decode("utf-8") if raw else ""

    def destroy(self) -> None:
        """Frees the renderer now instead of when the app shuts down.

        The map itself stays loaded. Calling it twice does nothing.
        """
        if not self._destroyed:
            _n.pz_tilemap_renderer_destroy(self._handle)
            self._destroyed = True
