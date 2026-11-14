"""A box that falls, moves and stops against the level's solid tiles
(body.zig). The player and the walkers are both one of these."""


class Body:
    def __init__(self, x, y, w, h):
        # Its hitbox, in world pixels.
        self.x, self.y, self.w, self.h = x, y, w, h
        # Where its top-left was before the last step, for drawing it between
        # ticks (see draw_pos).
        self.prev_x, self.prev_y = x, y
        # Pixels per second; +y is down.
        self.vx = self.vy = 0.0
        # Whether it ended the last step standing on a solid tile.
        self.on_ground = False

    @property
    def right(self):
        return self.x + self.w

    @property
    def bottom(self):
        return self.y + self.h

    def center(self):
        return (self.x + self.w / 2, self.y + self.h / 2)

    def overlaps(self, x, y, w, h):
        return self.x < x + w and x < self.right and self.y < y + h and y < self.bottom

    def step(self, dt, level, tun):
        """Pulls it down by gravity, then moves it by its velocity over `dt`
        seconds, one axis at a time so it slides along walls and floors.
        Hitting something zeroes the velocity along that axis. Returns
        (hit_wall, hit_floor)."""
        self.prev_x, self.prev_y = self.x, self.y
        self.vy = min(self.vy + tun.gravity * dt, tun.max_fall_speed)

        self.x, hit_wall = level.map.move_x(level.main, self.x, self.y, self.w, self.h, self.vx * dt)
        if hit_wall:
            self.vx = 0

        dy = self.vy * dt
        self.y, hit_y = level.map.move_y(level.main, self.x, self.y, self.w, self.h, dy)
        if hit_y:
            self.vy = 0
        # Stopped while moving down means it landed.
        self.on_ground = hit_y and dy > 0
        return hit_wall, self.on_ground

    def teleport(self, x, y):
        """Moves it straight to (x, y) (its top-left), with nothing to
        interpolate from."""
        self.x, self.y = x, y
        self.prev_x, self.prev_y = x, y

    def draw_pos(self, alpha):
        """Its top-left `alpha` of the way from last tick to this one, so
        movement stays smooth whatever the frame rate."""
        return (self.prev_x + (self.x - self.prev_x) * alpha, self.prev_y + (self.y - self.prev_y) * alpha)
