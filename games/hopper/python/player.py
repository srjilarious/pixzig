"""The frog: running, jumping, and which frame of it to draw (player.zig)."""

import sheet
from body import Body

# Hitbox size. The 16x16 sprite is drawn centred over it, bottoms lined up.
WIDTH, HEIGHT = 12, 13


class Player:
    def __init__(self, x, y):
        self.body = Body(x, y, WIDTH, HEIGHT)
        self.facing_left = False
        # Time left to jump after leaving the ground (see Tuning.coyote_ms).
        self.coyote_ms = 0.0
        # Time left on a jump pressed in the air (see Tuning.jump_buffer_ms).
        self.jump_buffer_ms = 0.0
        # Distance run, for picking the run frame.
        self.run_px = 0.0

    def update(self, actions, tun, level, dt_ms):
        """One tick of `dt_ms`: steer from the controls, then move."""
        dt = dt_ms / 1000.0
        body = self.body

        # Run: speed up toward the held direction, or slow to a stop.
        direction = (1 if actions.down("right") else 0) - (1 if actions.down("left") else 0)
        if direction != 0:
            accel = tun.ground_accel if body.on_ground else tun.air_accel
            body.vx = approach(body.vx, direction * tun.run_speed, accel * dt)
            self.facing_left = direction < 0
        elif body.on_ground:
            body.vx = approach(body.vx, 0, tun.ground_friction * dt)

        # Jump, with a little forgiveness either side of being on the ground
        # (coyote time and the jump buffer).
        self.coyote_ms = tun.coyote_ms if body.on_ground else self.coyote_ms - dt_ms
        self.jump_buffer_ms = tun.jump_buffer_ms if actions.pressed("jump") else self.jump_buffer_ms - dt_ms
        if self.jump_buffer_ms > 0 and self.coyote_ms > 0:
            body.vy = -tun.jump_speed
            self.jump_buffer_ms = 0
            self.coyote_ms = 0
        # Letting go early cuts the jump short.
        if actions.released("jump") and body.vy < 0:
            body.vy *= tun.jump_release_cut

        body.step(dt, level, tun)

        # Keep inside the level's left and right edges.
        if body.x < 0:
            body.teleport(0, body.y)
        if body.right > level.width:
            body.teleport(level.width - WIDTH, body.y)

        self.run_px += abs(body.vx) * dt

    def landed_on(self, other):
        """Whether it came down onto body `other` from above this tick:
        falling, with its feet above `other`'s top a tick ago. That's a
        stomp; touching something any other way is a hit."""
        was_above = self.body.prev_y + HEIGHT <= other.y + 2
        return self.body.vy > 0 and was_above

    def bounce(self, jump_held, tun):
        """Bounces up off something it stomped: a full jump with jump held, a
        smaller hop without."""
        self.body.vy = -(tun.jump_speed if jump_held else tun.stomp_bounce)

    def cell(self):
        """The sheet cell for its current pose."""
        if not self.body.on_ground:
            return sheet.FROG_JUMP
        if abs(self.body.vx) > 5:
            return sheet.FROG_RUN1 if self.run_px % 16 < 8 else sheet.FROG_RUN2
        return sheet.FROG_IDLE


def approach(value, target, step):
    """`value` moved toward `target` by at most `step`."""
    if value < target:
        return min(value + step, target)
    return max(value - step, target)
