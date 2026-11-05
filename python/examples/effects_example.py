"""Render targets, a post-processing shader, blend modes, styled text,
sequences, a state stack and camera follow, together.

The scene is drawn at 320x180 into a render target, then scaled up to the
window through a scanline shader. Arrow keys move the glow, P pauses
(a state pushed over the game), Space plays a flash sequence, Esc quits.
"""
import math

from pixzig import (
    App,
    BlendMode,
    Ease,
    Key,
    State,
    StateStack,
    TargetFilter,
    TextAlign,
    color,
)
from pixzig.sequence import SequencePlayer, tween_attr, wait

SCANLINES = """#version 300 es
precision mediump float;
in vec2 Texcoord;
in vec4 Col;
flat in float Mode;
uniform sampler2D tex;
uniform float lines;
uniform float strength;
out vec4 fragColor;
void main() {
    vec4 c = texture(tex, Texcoord) * Col;
    float band = 0.5 + 0.5 * sin(Texcoord.y * lines * 3.14159);
    fragColor = vec4(c.rgb * (1.0 - strength * band), c.a);
}
"""

LOW_W, LOW_H = 320, 180


class Playing(State):
    def __init__(self, app):
        self.app = app
        self.x, self.y = 160.0, 90.0
        self.prev = (self.x, self.y)
        self.t = 0.0

    def update(self, dt_ms):
        kb = self.app.keyboard
        self.prev = (self.x, self.y)
        speed = 0.12 * dt_ms
        if kb.down(Key.LEFT):
            self.x -= speed
        if kb.down(Key.RIGHT):
            self.x += speed
        if kb.down(Key.UP):
            self.y -= speed
        if kb.down(Key.DOWN):
            self.y += speed
        self.t += dt_ms
        self.app.camera.follow(self.x, self.y, dt_ms, deadzone=(40, 20), smoothing=4)

    def render(self, alpha):
        app = self.app
        x = self.prev[0] + (self.x - self.prev[0]) * alpha
        y = self.prev[1] + (self.y - self.prev[1]) * alpha

        app.render_begin(app.camera)
        for i in range(12):
            gx = (i % 4) * 90 - 20
            gy = (i // 4) * 70 - 10
            app.shapes.filled_rect(gx, gy, 60, 40, color.hex("#2b3a55"))
        # Additive glow: overlapping rings brighten each other.
        app.set_blend(BlendMode.ADDITIVE)
        pulse = 0.5 + 0.5 * math.sin(self.t / 300)
        for r in (24, 16, 8):
            a = int(60 + 60 * pulse)
            app.shapes.filled_rect(x - r, y - r, r * 2, r * 2, (255, 140, 40, a))
        app.render_end()

        app.render_begin()
        app.text.draw("pixzig effects", LOW_W / 2, 8, align=TextAlign.CENTER, shadow=(0, 0, 0))
        app.render_end()


class Paused(State):
    def __init__(self, app):
        self.app = app

    def render(self, alpha):
        self.app.fade(color.BLACK, 0.6)
        self.app.render_begin()
        self.app.text.draw("PAUSED", LOW_W / 2, 80, scale=2, align=TextAlign.CENTER, color=color.YELLOW)
        self.app.render_end()


class EffectsApp(App):
    def __init__(self):
        super().__init__("pixzig effects", 960, 540, logical_size=(LOW_W, LOW_H))
        self.clear_color = (10, 10, 20)
        self.camera = self.create_camera()
        self.camera.set_pos(LOW_W / 2, LOW_H / 2)
        self.scene = self.create_render_target(LOW_W, LOW_H, TargetFilter.NEAREST)
        self.create_shader("scanlines", SCANLINES)

        self.playing = Playing(self)
        self.paused = Paused(self)
        self.states = StateStack(self.playing)
        self.seq = SequencePlayer()
        self.flash = 0.0

    def flash_sequence(self):
        yield tween_attr(self, "flash", 1.0, 80)
        yield wait(60)
        yield tween_attr(self, "flash", 0.0, 400, Ease.QUAD_OUT)

    def update(self, dt_ms):
        kb = self.keyboard
        if kb.pressed(Key.ESCAPE):
            self.quit()
            return
        if kb.pressed(Key.P):
            if self.states.current is self.paused:
                self.states.pop()
            else:
                self.states.push(self.paused)
        if kb.pressed(Key.SPACE) and not self.seq.is_running("flash"):
            self.seq.play(self.flash_sequence(), tag="flash")
        self.states.update(dt_ms)
        self.seq.update(dt_ms)

    def render(self, alpha):
        # The game at low resolution, into the target.
        self.set_target(self.scene)
        self.render_begin_screen()
        self.shapes.filled_rect(0, 0, LOW_W, LOW_H, self.clear_color)
        self.render_end()
        self.states.render(alpha)
        self.fade(color.WHITE, self.flash)
        self.set_target(None)

        # Scaled up to the window through the scanline shader.
        w, h = self.window.framebuffer_size
        self.render_begin_screen()
        self.set_shader("scanlines")
        self.set_uniform("lines", float(LOW_H))
        self.set_uniform("strength", 0.25)
        self.scene.draw(0, 0, w, h)
        self.render_end()


if __name__ == "__main__":
    EffectsApp().run()
