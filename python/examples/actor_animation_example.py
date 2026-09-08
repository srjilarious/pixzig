"""Actor animation example: carve walk frames out of pac-tiles.png, build
frame sequences and named states, then let an Actor drive a Sprite through
them from the arrow keys. "walk_left" reuses the right-facing sequence with
a horizontal flip. Mirrors examples/actor_ex.zig, driven from Python.

Run from the pixzig repo root, since asset paths are relative to it:

    zig build python-ffi
    python python/examples/actor_animation_example.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pixzig import Flip, Key, PixzigApp

# name -> (x, y, w, h) inside pac-tiles.png
FRAMES = {
    "right_1": (96, 48, 16, 16),
    "right_2": (112, 48, 16, 16),
    "right_3": (96, 64, 16, 16),
    "down_1": (112, 64, 16, 16),
    "down_2": (96, 80, 16, 16),
    "down_3": (112, 80, 16, 16),
}

FRAME_MS = 120.0


class ActorAnimationApp(PixzigApp):
    def __init__(self):
        super().__init__("Actor Animation Example", width=640, height=480)

        self.text.load_font("roboto", "assets/Roboto-Medium.ttf", 20)
        self.text.set_font("roboto")

        self.load_texture("pac", "assets/pac-tiles.png")
        for name, (x, y, w, h) in FRAMES.items():
            self.create_subtexture("pac", name, x, y, w, h)

        # Two sequences; "walk_left" is "walk_right" played flipped.
        self.create_sequence("walk_right", loop=True)
        self.create_sequence("walk_down", loop=True)
        for i in (1, 2, 3):
            self.add_frame("walk_right", f"right_{i}", FRAME_MS)
            self.add_frame("walk_down", f"down_{i}", FRAME_MS)

        self.add_anim_state("right", "walk_right")
        self.add_anim_state("left", "walk_right", flip=Flip.HORZ)
        self.add_anim_state("down", "walk_down")
        self.add_anim_state("up", "walk_down", flip=Flip.VERT)

        self.sprite = self.load_sprite("right_1")
        self.sprite.set_scale(3)
        self.pos = [300.0, 220.0]
        self.sprite.set_pos(*map(int, self.pos))

        self.actor = self.create_actor()
        for state in ("right", "left", "down", "up"):
            self.actor.add_state(state)
        self.facing = "right"
        self.actor.set_state(self.facing, self.sprite)

    def update(self, dt_ms: float) -> bool:
        if self.keyboard.pressed(Key.ESCAPE):
            return False

        speed = 0.12 * dt_ms
        dx = dy = 0.0
        want = None
        if self.keyboard.down(Key.LEFT):
            dx, want = -speed, "left"
        elif self.keyboard.down(Key.RIGHT):
            dx, want = speed, "right"
        elif self.keyboard.down(Key.UP):
            dy, want = -speed, "up"
        elif self.keyboard.down(Key.DOWN):
            dy, want = speed, "down"

        if want is not None:
            if want != self.facing:
                self.facing = want
                self.actor.set_state(want, self.sprite)
            # Only advance the animation while actually moving.
            self.actor.update(dt_ms, self.sprite)

        self.pos[0] += dx
        self.pos[1] += dy
        self.sprite.set_pos(*map(int, self.pos))
        return True

    def render(self) -> None:
        self.render_begin()
        self.sprite.draw()
        self.text.draw("Arrow keys to walk, Esc to quit", 20, 20)
        self.text.draw(f"facing: {self.facing}", 20, 46)
        self.render_end()


if __name__ == "__main__":
    ActorAnimationApp().run()
