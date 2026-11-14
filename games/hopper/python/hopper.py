"""Hopper, the Python version: a one-level platformer. Run, jump, stomp the
beetles, grab the coins and reach the flag.

It mirrors the Zig version in ../src file by file (player.py is
player.zig, and so on) and shares its assets: ../manifest.json lists them
(the sprite sheet, the level and tuning.json), so tweaking those changes
both.

    # from the pixzig checkout, once:
    just py_install
    # then from anywhere:
    .venv/bin/python games/hopper/python/hopper.py

Or with pixzig from PyPI: `pip install pixzig`, then `python hopper.py`.

Files:
    hopper.py    the App: engine setup, drawing sprites, switching screens
    controls.py  the named actions and the keys bound to them
    play.py      the rules: stomping, coins, the goal, lives, the camera
    player.py    the frog: running and jumping
    walker.py    the beetles: walking back and forth
    coin.py      the coins
    level.py     the tile map, solid tiles and spawn points
    body.py      falling and bumping into tiles, shared by everything
    hud.py       the coins and lives counter
    screens.py   title, pause and level clear / game over
    config.py    gameplay numbers, loaded from assets/tuning.json
    sheet.py     where each sprite is in assets/hopper.png
"""

import os

from pixzig import App, Flip, ScalePolicy, StateStack

import controls
import sheet
from config import Tuning
from play import Play
from screens import Message, Paused, Title

# The game's folder: manifest.json and assets/ live there, next to src/ and
# python/.
GAME_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


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
        self.clear_color = sheet.SKY
        # Opening the manifest loads its "boot" group: the sprite sheet and
        # the level, registered under their ids.
        self.manifest = self.load_manifest("manifest.json")
        self.tuning = Tuning.load(self.manifest, "tuning")
        self.actions = self.create_action_map()
        controls.bind(self.actions)

        # One sprite over the sheet, pointed at a different cell for each
        # thing drawn (see draw_cell).
        self.cell_sprite = self.load_sprite("hopper")
        self.cell_sprite.set_size(sheet.CELL, sheet.CELL)

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
        s.set_src_rect(*sheet.rect(cell))
        s.set_flip(flip)
        s.set_pos(x, y)
        s.draw()

    def draw_on_body(self, cell, body, alpha, flip=Flip.NONE):
        """Draws a sheet cell over `body`, `alpha` of the way between its last
        two ticks: centred across it, with the bottoms lined up. Hitboxes are
        smaller than the 16x16 cells, so feet touch the ground this way."""
        x, y = body.draw_pos(alpha)
        self.draw_cell(cell, x + body.w / 2 - sheet.CELL / 2, y + body.h - sheet.CELL, flip)

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
        """Back to the game from the pause overlay."""
        self.states.pop()

    def show_message(self, text):
        """Freezes the game under `text` (see Message)."""
        self.message.text = text
        self.states.push(self.message, render_below=True)

    def to_title(self):
        self.states.set_state(self.title)


if __name__ == "__main__":
    Hopper().run()
