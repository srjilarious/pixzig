"""Minimal pixzig-from-Python example: two moving sprites, some shapes, and
text. Relative asset paths resolve against the main script's directory, so
this runs from any working directory:

    zig build python-ffi
    python python/examples/hello_pixzig.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pixzig import App, Key

# The examples share the repo's top-level assets/ directory, two levels up
# from this script. Pointing `asset_root` there lets every load below use a
# short path, and keeps them working whatever directory you launch from.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


class HelloApp(App):
    def __init__(self):
        super().__init__("Hello Pixzig", width=800, height=480, asset_root=REPO_ROOT)
        self.clear_color = (18, 18, 28)

        self.load_texture("pac", "assets/pac-tiles.png")
        self.text.load_font("roboto", "assets/Roboto-Medium.ttf", 24)
        self.text.set_font("roboto")

        self.player = self.load_sprite("pac")
        self.player_pos = [340.0, 200.0]

        self.orbiter = self.load_sprite("pac")
        self.orbit_angle = 0.0

    def update(self, dt_ms: float) -> None:
        if self.keyboard.down(Key.ESCAPE):
            self.quit()
            return

        speed = 0.2 * dt_ms
        if self.keyboard.down(Key.LEFT) or self.keyboard.down(Key.A):
            self.player_pos[0] -= speed
        if self.keyboard.down(Key.RIGHT) or self.keyboard.down(Key.D):
            self.player_pos[0] += speed
        if self.keyboard.down(Key.UP) or self.keyboard.down(Key.W):
            self.player_pos[1] -= speed
        if self.keyboard.down(Key.DOWN) or self.keyboard.down(Key.S):
            self.player_pos[1] += speed

        self.player.set_pos(self.player_pos[0], self.player_pos[1])

        self.orbit_angle += 0.002 * dt_ms
        orbit_x = self.player_pos[0] + 80.0 * math.cos(self.orbit_angle)
        orbit_y = self.player_pos[1] + 80.0 * math.sin(self.orbit_angle)
        self.orbiter.set_pos(orbit_x, orbit_y)

    def render(self) -> None:
        self.render_begin()

        # Size the banner to the text rather than guessing at 260x60.
        greeting = "Hello from Python!"
        text_w, _ = self.text.measure(greeting)
        line_h = self.text.line_height() or 24
        self.shapes.filled_rect(20, 20, text_w + 20, line_h + 20, (40, 40, 80))
        self.shapes.rect(20, 20, text_w + 20, line_h + 20, (255, 255, 255), line_width=2)
        self.text.draw_colored(greeting, 30, 30, (255, 220, 120))

        self.player.draw()
        self.orbiter.draw()

        self.text.draw("Arrows/WASD to move, Esc to quit", 20, 440)
        self.render_end()


if __name__ == "__main__":
    HelloApp().run()
