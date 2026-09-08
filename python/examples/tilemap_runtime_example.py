"""Tilemap runtime example: collision queries, object layers, and live tile
edits.

  * Arrow keys walk a block around the map; `is_blocked` on the main layer
    stops it entering solid tiles.
  * Object layers are read once at startup and their rectangles are drawn.
  * Left click paints tile 0 under the cursor, right click erases it, then
    `refresh()` makes the change show up.

Run from the pixzig repo root, since asset paths are relative to it:

    zig build python-ffi
    python python/examples/tilemap_runtime_example.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pixzig import Key, MouseButton, PixzigApp

SOLID_LAYER = "main_layer"


class TilemapRuntimeApp(PixzigApp):
    def __init__(self):
        super().__init__("Tilemap Runtime Example", width=800, height=480)

        self.text.load_font("roboto", "assets/Roboto-Medium.ttf", 18)
        self.text.set_font("roboto")

        self.load_texture("tiles", "assets/mario_grassish2.png")
        self.load_tilemap("level1a", "assets/level1a.tmx")
        self.map = self.create_tilemap_renderer("level1a", "tiles")

        self.solid = self.map.layer_index(SOLID_LAYER)
        self.tw, self.th = self.map.tile_size(self.solid)

        self.camera = self.create_camera()
        w, h = self.map.pixel_size(self.solid)
        self.camera.set_bounds(0, 0, w, h)

        self.pos = [8.0 * self.tw, 6.0 * self.th]
        self.camera.set_pos(*self.pos)

        # Read every object layer once; keep (rect, label) for drawing.
        self.obj_rects = []
        for gi in range(self.map.object_group_count()):
            for obj in self.map.objects(gi):
                self.obj_rects.append((obj.x, obj.y, obj.w, obj.h, obj.class_ or obj.name))

        self.painted = "(click to edit tiles)"

    def _solid_at(self, px: float, py: float) -> bool:
        tx, ty = self.map.world_to_tile(self.solid, px, py)
        return self.map.is_blocked(self.solid, tx, ty)

    def update(self, dt_ms: float) -> bool:
        if self.keyboard.pressed(Key.ESCAPE):
            return False

        speed = 0.15 * dt_ms
        dx = (self.keyboard.down(Key.RIGHT) - self.keyboard.down(Key.LEFT)) * speed
        dy = (self.keyboard.down(Key.DOWN) - self.keyboard.down(Key.UP)) * speed

        # Axis-separated collision against the solid layer.
        if not self._solid_at(self.pos[0] + dx, self.pos[1]):
            self.pos[0] += dx
        if not self._solid_at(self.pos[0], self.pos[1] + dy):
            self.pos[1] += dy
        self.camera.set_pos(*self.pos)

        # Live tile edits at the cursor.
        mx, my = self.mouse.raw_pos
        world = self.screen_to_world(self.camera, mx, my)
        if world is not None:
            tx, ty = self.map.world_to_tile(self.solid, *world)
            if self.mouse.pressed(MouseButton.LEFT):
                self.map.set_tile(self.solid, tx, ty, 0)
                self.map.refresh()
                self.painted = f"painted tile 0 at ({tx}, {ty})"
            elif self.mouse.pressed(MouseButton.RIGHT):
                self.map.set_tile(self.solid, tx, ty, -1)
                self.map.refresh()
                self.painted = f"erased tile at ({tx}, {ty})"
        return True

    def render(self) -> None:
        self.render_begin(self.camera)
        self.map.render_below(self.camera, 1.0)
        for x, y, w, h, _ in self.obj_rects:
            self.shapes.rect(x, y, w, h, (80, 200, 255), line_width=1)
        self.shapes.filled_rect(self.pos[0] - 12, self.pos[1] - 12, 24, 24, (255, 80, 80))
        self.map.render_above(self.camera, 1.0)
        self.render_end()

        self.render_begin()
        tx, ty = self.map.world_to_tile(self.solid, *self.pos)
        flags = self.map.tile_flags(self.solid, tx, ty)
        self.text.draw(f"tile ({tx}, {ty})  id={self.map.get_tile(self.solid, tx, ty)}  flags={flags!r}", 12, 12)
        self.text.draw(f"objects drawn: {len(self.obj_rects)}   {self.painted}", 12, 34)
        self.text.draw("Arrows move, L/R click edit tiles, Esc quits", 12, 452)
        self.render_end()


if __name__ == "__main__":
    TilemapRuntimeApp().run()
