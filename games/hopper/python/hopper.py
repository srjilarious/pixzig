"""Hopper, the Python version: a one-level platformer. Run, jump, stomp the
beetles, grab the coins and reach the flag.

It mirrors the Zig version in ../src section by section and shares its
assets: ../manifest.json lists them (the sprite sheet, the level and
tuning.json), so tweaking those changes both.

    # from the pixzig checkout, once:
    just py_install
    # then from anywhere:
    .venv/bin/python games/hopper/python/hopper.py

Or with pixzig from PyPI: `pip install pixzig`, then `python hopper.py`.
"""

import json
import math
import os
from dataclasses import dataclass, fields

from pixzig import App, Flip, GamepadButton, Key, ScalePolicy, State, StateStack, TextAlign

# The game's folder: manifest.json and assets/ live there, next to src/ and
# python/.
GAME_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


# ---------------------------------------------------------------------------
# config.zig: gameplay numbers, read from assets/tuning.json


@dataclass
class Tuning:
    """Distances in pixels (a tile is 16), speeds in pixels per second, times
    in milliseconds. See src/config.zig for what each one does."""

    run_speed: float = 95
    ground_accel: float = 900
    air_accel: float = 600
    ground_friction: float = 1100
    gravity: float = 1000
    max_fall_speed: float = 320
    jump_speed: float = 380
    jump_release_cut: float = 0.45
    coyote_ms: float = 90
    jump_buffer_ms: float = 110
    walker_speed: float = 28
    walkers_turn_at_ledges: bool = True
    stomp_bounce: float = 260
    squash_ms: float = 450
    lives: int = 3
    death_pause_ms: float = 900
    camera_deadzone_x: float = 12
    camera_smoothing: float = 9

    @classmethod
    def load(cls, manifest, asset_id):
        """A Tuning from the manifest's JSON asset `asset_id`; fields it leaves
        out keep their default, and unknown ones (like "_comment") are
        ignored."""
        data = json.loads(manifest.read_raw(asset_id))
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in data.items() if k in known})


# ---------------------------------------------------------------------------
# sheet.zig: the cells of assets/hopper.png (8 columns of 16x16)

CELL = 16
SHEET_COLUMNS = 8
GRASS, DIRT = 0, 1
# Sprites face right; they're flipped to face left.
FROG_IDLE, FROG_RUN1, FROG_RUN2, FROG_JUMP = 8, 9, 10, 11
BEETLE_WALK1, BEETLE_WALK2, BEETLE_SQUASHED = 12, 13, 14
COIN1, COIN_FRAMES = 15, 3

SKY = (120, 180, 240)
SHADOW = (0, 0, 0)

# Hitbox sizes. Sprites are 16x16 cells drawn centred over the hitbox, with
# their bottoms lined up.
PLAYER_W, PLAYER_H = 12, 13
WALKER_W, WALKER_H = 14, 11
COIN_SIZE = 10

# The tilemap asset ids, in play order (see manifest.json). Finishing the last
# one wins.
LEVELS = ["level1"]


# ---------------------------------------------------------------------------
# body.zig: a box that falls and stops against the level's solid tiles


class Level:
    """The loaded map: drawing it, and which tiles are solid."""

    def __init__(self, app, map_id):
        self.map = app.create_tilemap_renderer(map_id)
        # The layer the player stands on and bumps into; others are only drawn.
        self.main = self.map.layer_index("Main")
        cols, rows = self.map.layer_size(self.main)
        tile_w, tile_h = self.map.tile_size(self.main)
        self.width = cols * tile_w
        self.height = rows * tile_h

    def solid_at(self, x, y):
        """Whether the tile under world pixel (x, y) is solid. Outside the
        map is empty."""
        tx, ty = self.map.world_to_tile(self.main, x, y)
        return self.map.is_blocked(self.main, tx, ty)

    def spawns(self):
        """The "Spawns" object group's objects."""
        return self.map.objects(self.map.object_group_index("Spawns"))


class Body:
    """A box that falls, moves and stops against the level's solid tiles. The
    player and the walkers are both one of these."""

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
        self.x, self.y = x, y
        self.prev_x, self.prev_y = x, y

    def draw_pos(self, alpha):
        """Its top-left `alpha` of the way from last tick to this one, so
        movement stays smooth whatever the frame rate."""
        return (self.prev_x + (self.x - self.prev_x) * alpha, self.prev_y + (self.y - self.prev_y) * alpha)


# ---------------------------------------------------------------------------
# play.zig: the level, the player, walkers, coins and the HUD


class Player:
    def __init__(self, x, y):
        self.body = Body(x, y, PLAYER_W, PLAYER_H)
        self.facing_left = False
        self.coyote_ms = 0.0
        self.jump_buffer_ms = 0.0
        self.run_px = 0.0


class Walker:
    def __init__(self, x, y):
        self.body = Body(x, y, WALKER_W, WALKER_H)
        self.dir = -1
        self.squashed_ms = None  # time left on screen once squashed


class Coin:
    def __init__(self, x, y):
        self.x, self.y = x, y
        self.taken = False


class Play(State):
    def __init__(self, app):
        self.app = app
        self.level_index = 0
        self.level = Level(app, LEVELS[0])
        self.camera = app.create_camera()
        self.player = Player(16, 16)
        self.walkers = []
        self.coins = []
        self.goal = (0, 0, 0, 0)
        self.lives = 0
        self.coins_collected = 0
        self.elapsed_ms = 0.0
        self.dying_ms = 0.0

    @property
    def tun(self):
        return self.app.tuning

    def new_game(self):
        self.lives = self.tun.lives
        self.coins_collected = 0
        self.load_level(0)

    def load_level(self, index):
        if index != self.level_index:
            self.level = Level(self.app, LEVELS[index])
            self.level_index = index
        self.restart_level()

    def restart_level(self):
        """Puts everything back where the level's "Spawns" group says."""
        self.walkers.clear()
        self.coins.clear()
        self.player = Player(16, 16)
        self.dying_ms = 0.0
        for obj in self.level.spawns():
            # Spawns are tile-sized boxes; stand each body on the box's bottom
            # edge, centred across it.
            if obj.class_ == "player_start":
                self.player.body.teleport(obj.x + (obj.w - PLAYER_W) / 2, obj.y + obj.h - PLAYER_H)
            elif obj.class_ == "walker":
                self.walkers.append(Walker(obj.x + (obj.w - WALKER_W) / 2, obj.y + obj.h - WALKER_H))
            elif obj.class_ == "coin":
                self.coins.append(Coin(obj.x + (obj.w - COIN_SIZE) / 2, obj.y + (obj.h - COIN_SIZE) / 2))
            elif obj.class_ == "goal":
                self.goal = (obj.x, obj.y, obj.w, obj.h)
        self.camera.set_bounds(0, 0, self.level.width, self.level.height)
        self.camera.set_pos(*self.player.body.center())

    def update(self, dt_ms):
        actions = self.app.actions
        if actions.pressed("pause") or actions.pressed("back"):
            self.app.pause()
            return
        self.elapsed_ms += dt_ms
        dt = dt_ms / 1000.0

        if self.dying_ms > 0:
            self.dying_ms -= dt_ms
            if self.dying_ms <= 0:
                self.after_death()
            return

        self.update_player(dt, dt_ms)
        for w in self.walkers:
            self.update_walker(w, dt, dt_ms)
        # Squashed walkers that have finished showing are gone.
        self.walkers = [w for w in self.walkers if w.squashed_ms is None or w.squashed_ms > 0]

        self.check_walkers()
        self.check_coins()
        if self.player.body.overlaps(*self.goal):
            self.finish_level()
            return

        # Fell into a pit.
        if self.player.body.y > self.level.height:
            self.die()

        cx, cy = self.player.body.center()
        self.camera.follow(cx, cy, dt_ms, deadzone=(self.tun.camera_deadzone_x, 0), smoothing=self.tun.camera_smoothing)

    def update_player(self, dt, dt_ms):
        t = self.tun
        actions = self.app.actions
        p = self.player
        body = p.body

        # Run: speed up toward the held direction, or slow to a stop.
        direction = (1 if actions.down("right") else 0) - (1 if actions.down("left") else 0)
        if direction != 0:
            accel = t.ground_accel if body.on_ground else t.air_accel
            body.vx = approach(body.vx, direction * t.run_speed, accel * dt)
            p.facing_left = direction < 0
        elif body.on_ground:
            body.vx = approach(body.vx, 0, t.ground_friction * dt)

        # Jump, with a little forgiveness either side of being on the ground.
        p.coyote_ms = t.coyote_ms if body.on_ground else p.coyote_ms - dt_ms
        p.jump_buffer_ms = t.jump_buffer_ms if actions.pressed("jump") else p.jump_buffer_ms - dt_ms
        if p.jump_buffer_ms > 0 and p.coyote_ms > 0:
            body.vy = -t.jump_speed
            p.jump_buffer_ms = 0
            p.coyote_ms = 0
        # Letting go early cuts the jump short.
        if actions.released("jump") and body.vy < 0:
            body.vy *= t.jump_release_cut

        body.step(dt, self.level, t)

        # Keep inside the level's left and right edges.
        if body.x < 0:
            body.teleport(0, body.y)
        if body.right > self.level.width:
            body.teleport(self.level.width - PLAYER_W, body.y)

        p.run_px += abs(body.vx) * dt

    def update_walker(self, w, dt, dt_ms):
        """Walks back and forth, turning at walls (and, by default, at drops)."""
        if w.squashed_ms is not None:
            w.squashed_ms -= dt_ms
            return
        w.body.vx = w.dir * self.tun.walker_speed
        hit_wall, _ = w.body.step(dt, self.level, self.tun)
        if hit_wall:
            w.dir = -w.dir
        if self.tun.walkers_turn_at_ledges and w.body.on_ground:
            ahead_x = w.body.right + 1 if w.dir > 0 else w.body.x - 1
            if not self.level.solid_at(ahead_x, w.body.bottom + 1):
                w.dir = -w.dir

    def check_walkers(self):
        """Landing on a walker squashes it and bounces the player up; touching
        one any other way costs a life."""
        p = self.player.body
        for w in self.walkers:
            if w.squashed_ms is not None:
                continue
            if not p.overlaps(w.body.x, w.body.y, w.body.w, w.body.h):
                continue
            # Falling, and the player's feet were above its top a tick ago.
            was_above = p.prev_y + PLAYER_H <= w.body.y + 2
            if p.vy > 0 and was_above:
                w.squashed_ms = self.tun.squash_ms
                p.vy = -(self.tun.jump_speed if self.app.actions.down("jump") else self.tun.stomp_bounce)
            else:
                self.die()
                return

    def check_coins(self):
        for c in self.coins:
            if not c.taken and self.player.body.overlaps(c.x, c.y, COIN_SIZE, COIN_SIZE):
                c.taken = True
                self.coins_collected += 1

    def die(self):
        if self.dying_ms > 0:
            return
        self.dying_ms = self.tun.death_pause_ms

    def after_death(self):
        """The death pause is over: try again, or it's game over."""
        self.lives = max(0, self.lives - 1)
        if self.lives == 0:
            self.app.show_message("GAME OVER")
            return
        self.restart_level()

    def finish_level(self):
        if self.level_index + 1 < len(LEVELS):
            self.load_level(self.level_index + 1)
            return
        self.app.show_message("LEVEL CLEAR!")

    def render(self, alpha):
        app = self.app
        app.render_begin(self.camera)
        self.level.map.render(self.camera)

        coin_frame = int(self.elapsed_ms / 120) % COIN_FRAMES
        for c in self.coins:
            if not c.taken:
                app.draw_cell(COIN1 + coin_frame, c.x + COIN_SIZE / 2 - 8, c.y + COIN_SIZE / 2 - 8)

        for w in self.walkers:
            if w.squashed_ms is not None:
                cell = BEETLE_SQUASHED
            else:
                cell = BEETLE_WALK1 if self.elapsed_ms % 300 < 150 else BEETLE_WALK2
            draw_on_body(app, cell, w.body, alpha, Flip.NONE)

        # Blinks while dying.
        blink_off = self.dying_ms > 0 and self.dying_ms % 160 < 80
        if not blink_off:
            flip = Flip.HORZ if self.player.facing_left else Flip.NONE
            draw_on_body(app, self.player_cell(), self.player.body, alpha, flip)
        app.render_end()

        # The HUD, in screen space.
        app.render_begin()
        app.text.draw(f"Coins {self.coins_collected}   Lives {self.lives}", 6, 4, shadow=SHADOW)
        app.render_end()

    def player_cell(self):
        p = self.player
        if not p.body.on_ground:
            base = FROG_JUMP
        elif abs(p.body.vx) > 5:
            base = FROG_RUN1 if p.run_px % 16 < 8 else FROG_RUN2
        else:
            base = FROG_IDLE
        return base


def draw_on_body(app, cell, body, alpha, flip):
    """Draws a 16x16 sheet cell centred across `body`, bottoms lined up."""
    x, y = body.draw_pos(alpha)
    app.draw_cell(cell, x + body.w / 2 - CELL / 2, y + body.h - CELL, flip)


def approach(value, target, step):
    """`value` moved toward `target` by at most `step`."""
    if value < target:
        return min(value + step, target)
    return max(value - step, target)


# ---------------------------------------------------------------------------
# screens.zig: title, pause, and level clear / game over


class Title(State):
    def __init__(self, app):
        self.app = app
        self.elapsed_ms = 0.0

    def update(self, dt_ms):
        self.elapsed_ms += dt_ms
        actions = self.app.actions
        if actions.pressed("back"):
            self.app.quit()
            return
        if actions.pressed("confirm") or actions.pressed("jump"):
            self.app.start_game()

    def render(self, alpha):
        app = self.app
        w, h = app.window.logical_size
        app.render_begin()

        # Ground along the bottom, two tiles deep.
        ground_y = h - 2 * CELL
        for x in range(0, w, CELL):
            app.draw_cell(GRASS, x, ground_y)
            app.draw_cell(DIRT, x, ground_y + CELL)

        # A little hop every second.
        t = (self.elapsed_ms % 1000) / 1000
        hop = max(0.0, math.sin(t * math.pi * 2)) * 14
        app.draw_cell(FROG_JUMP if hop > 0.5 else FROG_IDLE, w / 2 - 8, ground_y - CELL - hop)

        app.text.draw("HOPPER", w / 2, h * 0.2, color=(255, 230, 90), scale=3, align=TextAlign.CENTER, shadow=SHADOW, shadow_offset=(2, 2))
        app.text.draw("Press Space or Enter", w / 2, h * 0.5, align=TextAlign.CENTER, shadow=SHADOW)
        app.text.draw("Arrows move, Space jumps, P pauses", w / 2, h * 0.5 + 14, align=TextAlign.CENTER, shadow=SHADOW)
        app.render_end()


class Paused(State):
    """Drawn over the frozen game."""

    def __init__(self, app):
        self.app = app

    def update(self, dt_ms):
        if self.app.actions.pressed("pause"):
            self.app.resume_game()
        elif self.app.actions.pressed("back"):
            self.app.to_title()

    def render(self, alpha):
        draw_banner(self.app, "PAUSED", "P to resume, Esc for the title")


class Message(State):
    """"LEVEL CLEAR!" or "GAME OVER" over the frozen game."""

    def __init__(self, app):
        self.app = app
        self.text = ""

    def update(self, dt_ms):
        a = self.app.actions
        if a.pressed("confirm") or a.pressed("jump") or a.pressed("back"):
            self.app.to_title()

    def render(self, alpha):
        draw_banner(self.app, self.text, f"{self.app.play.coins_collected} coins. Press Enter")


def draw_banner(app, title, hint):
    """Dims the screen and shows `title` with `hint` under it."""
    w, h = app.window.logical_size
    app.render_begin()
    app.shapes.filled_rect(0, 0, w, h, (0, 0, 0, 140))
    app.text.draw(title, w / 2, h * 0.35, scale=2, align=TextAlign.CENTER, shadow=SHADOW)
    app.text.draw(hint, w / 2, h * 0.55, align=TextAlign.CENTER, shadow=SHADOW)
    app.render_end()


# ---------------------------------------------------------------------------
# main.zig: the App: engine setup, controls, and switching screens


class Hopper(App):
    def __init__(self):
        # Everything is laid out on a 320x180 screen, scaled up by whole pixels
        # to fit the window.
        super().__init__(
            "Hopper",
            width=960,
            height=540,
            logical_size=(320, 180),
            scale_policy=ScalePolicy.INTEGER_FIT,
            asset_root=GAME_ROOT,
        )
        self.clear_color = SKY
        # Opening the manifest loads its "boot" group: the sprite sheet and
        # the level, registered under their ids.
        self.manifest = self.load_manifest("manifest.json")
        self.tuning = Tuning.load(self.manifest, "tuning")
        self.actions = self.create_action_map()
        bind_controls(self.actions)

        # One sprite over the sheet, pointed at a different cell for each
        # thing drawn (see draw_cell).
        self.cell_sprite = self.load_sprite("hopper")
        self.cell_sprite.set_size(CELL, CELL)

        self.title = Title(self)
        self.play = Play(self)
        self.paused = Paused(self)
        self.message = Message(self)
        self.states = StateStack(self.title)

    def draw_cell(self, cell, x, y, flip=Flip.NONE):
        """Draws a sheet cell with its top-left at (x, y), mirrored by `flip`.
        The renderer rounds it to whole pixels, so the pixel art doesn't
        shimmer between them."""
        s = self.cell_sprite
        s.set_src_rect((cell % SHEET_COLUMNS) * CELL, (cell // SHEET_COLUMNS) * CELL, CELL, CELL)
        s.set_flip(flip)
        s.set_pos(x, y)
        s.draw()

    def update(self, dt_ms):
        self.actions.update()
        self.states.update(dt_ms)

    def render(self, alpha):
        self.states.render(alpha)

    def start_game(self):
        self.play.new_game()
        self.states.set_state(self.play)

    def pause(self):
        """Freezes the game under the pause overlay."""
        self.states.push(self.paused, render_below=True)

    def resume_game(self):
        self.states.pop()

    def show_message(self, text):
        self.message.text = text
        self.states.push(self.message, render_below=True)

    def to_title(self):
        self.states.set_state(self.title)


def bind_controls(actions):
    """Keyboard and gamepad controls for every action."""
    for action, keys, buttons in [
        ("left", [Key.LEFT, Key.A], [GamepadButton.DPAD_LEFT]),
        ("right", [Key.RIGHT, Key.D], [GamepadButton.DPAD_RIGHT]),
        ("jump", [Key.SPACE, Key.UP, Key.W, Key.Z], [GamepadButton.A]),
        ("confirm", [Key.ENTER], [GamepadButton.START]),
        ("pause", [Key.P], [GamepadButton.START]),
        ("back", [Key.ESCAPE], [GamepadButton.BACK]),
    ]:
        for key in keys:
            actions.bind_key(action, key)
        for button in buttons:
            actions.bind_gamepad_button(action, button)


if __name__ == "__main__":
    Hopper().run()
