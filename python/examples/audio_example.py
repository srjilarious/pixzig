"""Audio example: load two sound files once, then trigger them from the
keyboard. Holding a key spins up overlapping voices up to the engine's
per-sound cap, so you can hear several lasers at once.

Run from the pixzig repo root, since asset paths are relative to it:

    zig build python-ffi
    python python/examples/audio_example.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pixzig import Key, PixzigApp


class AudioApp(PixzigApp):
    def __init__(self):
        super().__init__("Audio Example", width=640, height=360)

        self.text.load_font("roboto", "assets/Roboto-Medium.ttf", 24)
        self.text.set_font("roboto")

        self.audio.load("laser", "assets/laserShoot.wav")
        self.audio.load("boom", "assets/explosion.wav")

        self.last = "(nothing yet)"
        self.flash = 0.0

    def update(self, dt_ms: float) -> bool:
        if self.keyboard.pressed(Key.ESCAPE):
            return False

        if self.keyboard.pressed(Key.SPACE):
            self.audio.play("laser")
            self.last = "laser"
            self.flash = 200.0
        if self.keyboard.pressed(Key.B):
            self.audio.play("boom")
            self.last = "boom"
            self.flash = 200.0

        self.flash = max(0.0, self.flash - dt_ms)
        return True

    def render(self) -> None:
        self.render_begin()

        glow = int(60 + 160 * (self.flash / 200.0))
        self.shapes.filled_rect(40, 120, 560, 120, (glow, 40, 40))
        self.shapes.rect(40, 120, 560, 120, (255, 255, 255), line_width=2)

        self.text.draw("Space = laser     B = explosion", 70, 150)
        self.text.draw(f"last played: {self.last}", 70, 190)
        self.text.draw("Esc to quit", 70, 320)

        self.render_end()


if __name__ == "__main__":
    AudioApp().run()
