"""Minimal pixzig-from-Python example: two moving sprites, some shapes, and
text. Run from the pixzig repo root, since asset paths are relative to it:

    zig build python-ffi
    python python/examples/hello_pixzig.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pixzig import Key, PixzigApp


class HelloApp(PixzigApp):
    def __init__(self):
        super().__init__("Hello Pixzig", width=800, height=480)

        self.load_texture("pac", "assets/pac-tiles.png")
        self.text.load_font("roboto", "assets/Roboto-Medium.ttf", 24)
        self.text.set_font("roboto")

        self.player = self.load_sprite("pac")
        self.player_pos = [340.0, 200.0]

        self.orbiter = self.load_sprite("pac")
        self.orbit_angle = 0.0

    def update(self, dt_ms: float) -> bool:
        if self.keyboard.down(Key.ESCAPE):
            return False

        speed = 0.2 * dt_ms
        if self.keyboard.down(Key.LEFT) or self.keyboard.down(Key.A):
            self.player_pos[0] -= speed
        if self.keyboard.down(Key.RIGHT) or self.keyboard.down(Key.D):
            self.player_pos[0] += speed
        if self.keyboard.down(Key.UP) or self.keyboard.down(Key.W):
            self.player_pos[1] -= speed
        if self.keyboard.down(Key.DOWN) or self.keyboard.down(Key.S):
            self.player_pos[1] += speed

        self.player.set_pos(int(self.player_pos[0]), int(self.player_pos[1]))

        self.orbit_angle += 0.002 * dt_ms
        orbit_x = self.player_pos[0] + 80.0 * math.cos(self.orbit_angle)
        orbit_y = self.player_pos[1] + 80.0 * math.sin(self.orbit_angle)
        self.orbiter.set_pos(int(orbit_x), int(orbit_y))

        return True

    def render(self) -> None:
        self.render_begin()
        self.shapes.filled_rect(20, 20, 260, 60, (40, 40, 80))
        self.shapes.rect(20, 20, 260, 60, (255, 255, 255), line_width=2)
        self.text.draw("Hello from Python!", 30, 35)

        self.player.draw()
        self.orbiter.draw()

        self.text.draw("Arrows/WASD to move, Esc to quit", 20, 440)
        self.render_end()


if __name__ == "__main__":
    HelloApp().run()
