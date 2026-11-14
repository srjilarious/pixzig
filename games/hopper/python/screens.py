"""The screens around play: the title, the pause overlay, and the "level
clear" / "game over" message (screens.zig)."""

import math

from pixzig import State, TextAlign

import sheet


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
        """The name over a strip of ground with the frog hopping on it."""
        app = self.app
        w, h = app.window.logical_size
        app.render_begin()

        # Ground along the bottom, two tiles deep.
        ground_y = h - 2 * sheet.CELL
        for x in range(0, w, sheet.CELL):
            app.draw_cell(sheet.GRASS, x, ground_y)
            app.draw_cell(sheet.DIRT, x, ground_y + sheet.CELL)

        # A little hop every second.
        t = (self.elapsed_ms % 1000) / 1000
        hop = max(0.0, math.sin(t * math.pi * 2)) * 14
        frame = sheet.FROG_JUMP if hop > 0.5 else sheet.FROG_IDLE
        app.draw_cell(frame, w / 2 - 8, ground_y - sheet.CELL - hop)

        app.text.draw("HOPPER", w / 2, h * 0.2, color=(255, 230, 90), scale=3, align=TextAlign.CENTER, shadow=sheet.SHADOW, shadow_offset=(2, 2))
        app.text.draw("Press Space or Enter", w / 2, h * 0.5, align=TextAlign.CENTER, shadow=sheet.SHADOW)
        app.text.draw("Arrows move, Space jumps, P pauses", w / 2, h * 0.5 + 14, align=TextAlign.CENTER, shadow=sheet.SHADOW)
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
    """"LEVEL CLEAR!" or "GAME OVER" over the frozen game, until the player
    presses on to the title."""

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
    app.text.draw(title, w / 2, h * 0.35, scale=2, align=TextAlign.CENTER, shadow=sheet.SHADOW)
    app.text.draw(hint, w / 2, h * 0.55, align=TextAlign.CENTER, shadow=sheet.SHADOW)
    app.render_end()
