"""Tilemap loading + chunked rendering example. Loads level1a.tmx and drives
a camera around it with the arrow keys, world-space rendering interleaved
with the tile layers exactly as `examples/tile_load_ex.zig` does natively.

Run it from any working directory:

    zig build python-ffi
    python python/examples/tilemap_example.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pixzig import App, Key

# Assets live in the repo's top-level assets/ directory, two levels up from
# this script; see hello_pixzig.py.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


class TilemapApp(App):
    def __init__(self):
        super().__init__("Tilemap Example", width=800, height=480, asset_root=REPO_ROOT)

        self.load_texture("tiles", "assets/mario_grassish2.png")
        self.load_tilemap("level1a", "assets/level1a.tmx")
        self.map_renderer = self.create_tilemap_renderer("level1a", "tiles")

        self.camera = self.create_camera()
        w, h = self.map_renderer.pixel_size(1)
        self.camera.set_bounds(0, 0, w, h)

        self.guy_pos = [64.0, 64.0]
        self.camera.set_pos(*self.guy_pos)

    def update(self, dt_ms: float) -> None:
        if self.keyboard.pressed(Key.ESCAPE):
            self.quit()
            return

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

    def render(self) -> None:
        self.render_begin(self.camera)
        self.map_renderer.render_below(self.camera, 1.0)
        self.shapes.filled_rect(self.guy_pos[0], self.guy_pos[1], 32, 32, (255, 0, 0))
        self.map_renderer.render_above(self.camera, 1.0)
        self.render_end()


if __name__ == "__main__":
    TilemapApp().run()
