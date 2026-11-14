"""Playing a level: the rules that tie the player, walkers, coins and goal
together (stomp or get hurt, collect, finish), lives, and the camera
(play.zig). How each thing moves lives in its own file."""

from pixzig import Flip, State

import coin as coin_mod
import hud
import level as levels
import player as player_mod
import sheet
import walker as walker_mod
from coin import Coin
from level import Level
from player import Player
from walker import Walker


class Play(State):
    def __init__(self, app):
        self.app = app
        self.level_index = 0
        self.level = Level(app, levels.ORDER[0])
        self.camera = app.create_camera()
        self.player = Player(16, 16)
        self.walkers = []
        self.coins = []
        # Touching this finishes the level: (x, y, w, h).
        self.goal = (0, 0, 0, 0)
        self.lives = 0
        self.coins_collected = 0
        # Counts up while playing, for animations.
        self.elapsed_ms = 0.0
        # Counts down after the player dies; the level restarts at zero.
        self.dying_ms = 0.0

    @property
    def tun(self):
        return self.app.tuning

    def new_game(self):
        """Starts from the first level with full lives and no coins."""
        self.lives = self.tun.lives
        self.coins_collected = 0
        self.load_level(0)

    def load_level(self, index):
        if index != self.level_index:
            self.level = Level(self.app, levels.ORDER[index])
            self.level_index = index
        self.restart_level()

    def restart_level(self):
        """Puts everything back where the level's "Spawns" layer says: the
        player at "player_start", a walker at each "walker", a coin at each
        "coin", and the finish at "goal"."""
        self.walkers.clear()
        self.coins.clear()
        self.player = Player(16, 16)
        self.dying_ms = 0.0
        for obj in self.level.spawns():
            if obj.class_ == "player_start":
                self.player.body.teleport(*levels.stand_on(obj, player_mod.WIDTH, player_mod.HEIGHT))
            elif obj.class_ == "walker":
                self.walkers.append(Walker(*levels.stand_on(obj, walker_mod.WIDTH, walker_mod.HEIGHT)))
            elif obj.class_ == "coin":
                self.coins.append(Coin(*levels.centre_in(obj, coin_mod.SIZE)))
            elif obj.class_ == "goal":
                self.goal = levels.object_rect(obj)
        self.camera.set_bounds(0, 0, self.level.width, self.level.height)
        self.camera.set_pos(*self.player.body.center())

    def update(self, dt_ms):
        actions = self.app.actions
        if actions.pressed("pause") or actions.pressed("back"):
            self.app.pause()
            return
        self.elapsed_ms += dt_ms

        if self.dying_ms > 0:
            self.dying_ms -= dt_ms
            if self.dying_ms <= 0:
                self.after_death()
            return

        self.player.update(actions, self.tun, self.level, dt_ms)
        for w in self.walkers:
            w.update(self.tun, self.level, dt_ms)
        # Squashed walkers that have finished showing are gone.
        self.walkers = [w for w in self.walkers if not w.is_gone()]

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

    def check_walkers(self):
        """Landing on a walker squashes it and bounces the player up; touching
        one any other way costs a life."""
        p = self.player
        for w in self.walkers:
            if w.is_squashed():
                continue
            if not p.body.overlaps(w.body.x, w.body.y, w.body.w, w.body.h):
                continue
            if p.landed_on(w.body):
                w.squash(self.tun)
                p.bounce(self.app.actions.down("jump"), self.tun)
            else:
                self.die()
                return

    def check_coins(self):
        for c in self.coins:
            if not c.taken and self.player.body.overlaps(c.x, c.y, coin_mod.SIZE, coin_mod.SIZE):
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
        if self.level_index + 1 < len(levels.ORDER):
            self.load_level(self.level_index + 1)
            return
        self.app.show_message("LEVEL CLEAR!")

    def render(self, alpha):
        app = self.app
        # The world, through the camera.
        app.render_begin(self.camera)
        self.level.render(self.camera)
        coin_cell = coin_mod.cell(self.elapsed_ms)
        for c in self.coins:
            if not c.taken:
                cx, cy = c.center()
                app.draw_cell(coin_cell, cx - sheet.CELL / 2, cy - sheet.CELL / 2)
        for w in self.walkers:
            app.draw_on_body(w.cell(self.elapsed_ms), w.body, alpha)
        # Blinks while dying.
        blink_off = self.dying_ms > 0 and self.dying_ms % 160 < 80
        if not blink_off:
            flip = Flip.HORZ if self.player.facing_left else Flip.NONE
            app.draw_on_body(self.player.cell(), self.player.body, alpha, flip)
        app.render_end()

        hud.draw(app, self.coins_collected, self.lives)
