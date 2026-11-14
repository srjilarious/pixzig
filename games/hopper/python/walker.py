"""The beetles: they walk back and forth until stomped (walker.zig)."""

import sheet
from body import Body

# Hitbox size. The 16x16 sprite is drawn centred over it, bottoms lined up.
WIDTH, HEIGHT = 14, 11


class Walker:
    def __init__(self, x, y):
        self.body = Body(x, y, WIDTH, HEIGHT)
        # -1 walking left, 1 walking right.
        self.dir = -1
        # Time left on screen once squashed; None while alive.
        self.squashed_ms = None

    def update(self, tun, level, dt_ms):
        """One tick of `dt_ms`: walk, turning at walls (and, by default, at
        drops). A squashed walker only counts down until it's gone."""
        if self.squashed_ms is not None:
            self.squashed_ms -= dt_ms
            return
        self.body.vx = self.dir * tun.walker_speed
        hit_wall, _ = self.body.step(dt_ms / 1000.0, level, tun)
        if hit_wall:
            self.dir = -self.dir
        if tun.walkers_turn_at_ledges and self.body.on_ground:
            ahead_x = self.body.right + 1 if self.dir > 0 else self.body.x - 1
            if not level.solid_at(ahead_x, self.body.bottom + 1):
                self.dir = -self.dir

    def squash(self, tun):
        self.squashed_ms = tun.squash_ms

    def is_squashed(self):
        return self.squashed_ms is not None

    def is_gone(self):
        """Squashed, and finished showing it: time to remove it."""
        return self.squashed_ms is not None and self.squashed_ms <= 0

    def cell(self, elapsed_ms):
        """The sheet cell to draw, `elapsed_ms` into the level."""
        if self.is_squashed():
            return sheet.BEETLE_SQUASHED
        return sheet.BEETLE_WALK1 if elapsed_ms % 300 < 150 else sheet.BEETLE_WALK2
