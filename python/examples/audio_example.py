"""Audio example: sound effects with random pan and pitch, a streamed music
track with fades, bus volume and pause-all.

Holding Space spins up overlapping laser voices up to the engine's
per-sound cap; past it the oldest voice restarts.

Run it from any working directory:

    just py_install
    .venv/bin/python python/examples/audio_example.py
"""
import os
import random

from pixzig import App, Bus, Key

# Assets live in the repo's top-level assets/ directory, two levels up from
# this script; see hello_pixzig.py.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


class AudioApp(App):
    def __init__(self):
        super().__init__("Audio Example", width=640, height=360, asset_root=REPO_ROOT)

        self.text.load_font("roboto", "assets/Roboto-Medium.ttf", 20)
        self.text.set_font("roboto")

        self.audio.load("laser", "assets/laserShoot.wav")
        self.audio.load("boom", "assets/explosion.wav")
        self.audio.load_music("theme", "assets/music_loop.ogg")
        self.audio.play_music("theme", fade_ms=1000)

        self.last = "(nothing yet)"
        self.paused = False
        self.flash = 0.0

    def update(self, dt_ms: float) -> None:
        kb = self.keyboard
        if kb.pressed(Key.ESCAPE):
            self.quit()
            return

        if kb.pressed(Key.SPACE):
            self.audio.play("laser", pan=random.uniform(-0.6, 0.6), pitch=random.uniform(0.9, 1.1))
            self.last = "laser"
            self.flash = 200.0
        if kb.pressed(Key.B):
            self.audio.play("boom", volume=0.8)
            self.last = "boom"
            self.flash = 200.0
        if kb.pressed(Key.M):
            if self.audio.music_playing:
                self.audio.stop_music(fade_ms=1000)
            else:
                self.audio.play_music("theme", fade_ms=1000)
        if kb.pressed(Key.P):
            self.paused = not self.paused
            if self.paused:
                self.audio.pause_all()
            else:
                self.audio.resume_all()
        if kb.pressed(Key.UP):
            self.audio.set_bus_volume(Bus.MUSIC, min(1.0, self.audio.bus_volume(Bus.MUSIC) + 0.1))
        if kb.pressed(Key.DOWN):
            self.audio.set_bus_volume(Bus.MUSIC, max(0.0, self.audio.bus_volume(Bus.MUSIC) - 0.1))

        self.flash = max(0.0, self.flash - dt_ms)

    def render(self) -> None:
        self.render_begin()

        glow = int(60 + 160 * (self.flash / 200.0))
        self.shapes.filled_rect(40, 150, 560, 110, (glow, 40, 40))
        self.shapes.rect(40, 150, 560, 110, (255, 255, 255), line_width=2)

        self.text.draw("Space = laser   B = explosion   M = music on/off", 50, 30)
        self.text.draw("P = pause/resume all   Up/Down = music volume", 50, 60)
        self.text.draw(f"last played: {self.last}", 70, 175)
        music = "paused" if self.paused else ("playing" if self.audio.music_playing else "stopped")
        self.text.draw(f"music: {music}   volume: {self.audio.bus_volume(Bus.MUSIC):.1f}", 70, 215)
        self.text.draw("Esc to quit", 50, 320)

        self.render_end()


if __name__ == "__main__":
    AudioApp().run()
