"""A level: its tile map, which of its tiles are solid, and where things start
in it (level.zig)."""

# The tilemap asset ids, in play order (see manifest.json). Hopper has one;
# finishing the last one wins the game.
ORDER = ["level1"]


class Level:
    def __init__(self, app, map_id):
        """Loads the tilemap registered under `map_id` (by the manifest)."""
        self.map = app.create_tilemap_renderer(map_id)
        # The "Main" layer: the one bodies stand on and bump into. Other
        # layers are only drawn.
        self.main = self.map.layer_index("Main")
        cols, rows = self.map.layer_size(self.main)
        tile_w, tile_h = self.map.tile_size(self.main)
        # The map's size in pixels.
        self.width = cols * tile_w
        self.height = rows * tile_h

    def solid_at(self, x, y):
        """Whether the tile under world pixel (x, y) is solid. Outside the map
        is empty."""
        tx, ty = self.map.world_to_tile(self.main, x, y)
        return self.map.is_blocked(self.main, tx, ty)

    def spawns(self):
        """The objects in the "Spawns" object layer. Each one's class says
        what starts there (see Play.restart_level)."""
        return self.map.objects(self.map.object_group_index("Spawns"))

    def render(self, camera):
        """Draws every layer through `camera`."""
        self.map.render(camera)


def object_rect(obj):
    """The box a spawn object covers, in world pixels: (x, y, w, h)."""
    return (obj.x, obj.y, obj.w, obj.h)


def stand_on(obj, w, h):
    """Where the top-left of a `w` x `h` body goes to stand on the bottom edge
    of spawn box `obj`, centred across it. Spawns are tile-sized boxes, and
    most bodies are smaller than a tile."""
    return (obj.x + (obj.w - w) / 2, obj.y + obj.h - h)


def centre_in(obj, size):
    """Where the top-left of a `size` x `size` box goes to sit in the middle
    of spawn box `obj`."""
    return (obj.x + (obj.w - size) / 2, obj.y + (obj.h - size) / 2)
