"""Tilemap loading + chunked rendering example. Loads level1a.tmx and drives
a camera around it with the arrow keys, world-space rendering interleaved
with the tile layers exactly as `examples/tile_load_ex.zig` does natively.

Run from the pixzig repo root, since asset paths are relative to it:

    zig build python-ffi
    python python/examples/tilemap_example.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pixzig import Key, PixzigApp


class TilemapApp(PixzigApp):
    def __init__(self):
        super().__init__("Tilemap Example", width=800, height=480)

        self.load_texture("tiles", "assets/mario_grassish2.png")
        self.load_tilemap("level1a", "assets/level1a.tmx")
        self.map_renderer = self.create_tilemap_renderer("level1a", "tiles")

        self.camera = self.create_camera()
        w, h = self.map_renderer.pixel_size(1)
        self.camera.set_bounds(0, 0, w, h)

        self.guy_pos = [64.0, 64.0]
        self.camera.set_pos(*self.guy_pos)

    def update(self, dt_ms: float) -> bool:
        if self.keyboard.pressed(Key.ESCAPE):
            return False

        if self.map_renderer.check_reload():
            w, h = self.map_renderer.pixel_size(1)
            self.camera.set_bounds(0, 0, w, h)

        speed = 0.2 * dt_ms
        if self.keyboard.down(Key.LEFT):
            self.guy_pos[0] -= speed
        if self.keyboard.down(Key.RIGHT):
            self.guy_pos[0] += speed
        if self.keyboard.down(Key.UP):
            self.guy_pos[1] -= speed
        if self.keyboard.down(Key.DOWN):
            self.guy_pos[1] += speed

        self.camera.set_pos(*self.guy_pos)
        return True

    def render(self) -> None:
        self.render_begin(self.camera)
        self.map_renderer.render_below(self.camera, 1.0)
        self.shapes.filled_rect(self.guy_pos[0], self.guy_pos[1], 32, 32, (255, 0, 0))
        self.map_renderer.render_above(self.camera, 1.0)
        self.render_end()


if __name__ == "__main__":
    TilemapApp().run()
