"""Action mapping example. Binds "jump" to Space/gamepad-A and a "move_x"
axis to A/D, then reflects the live state as an on-screen rectangle and
text so you can confirm bindings actually respond to real input.

Run from the pixzig repo root:

    zig build python-ffi
    python python/examples/action_map_example.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pixzig import GamepadButton, Key, PixzigApp


class ActionMapApp(PixzigApp):
    def __init__(self):
        super().__init__("Action Map Example", width=800, height=480)

        self.text.load_font("roboto", "assets/Roboto-Medium.ttf", 24)
        self.text.set_font("roboto")

        self.actions = self.create_action_map()
        self.actions.bind_key("jump", Key.SPACE)
        self.actions.bind_gamepad_button("jump", GamepadButton.A)
        self.actions.bind_axis_buttons("move_x", Key.A, Key.D)

        self.box_x = 380.0

    def update(self, dt_ms: float) -> bool:
        if self.keyboard.pressed(Key.ESCAPE):
            return False

        self.actions.update()
        self.box_x += self.actions.axis("move_x") * 0.3 * dt_ms
        self.box_x = max(0.0, min(760.0, self.box_x))
        return True

    def render(self) -> None:
        self.render_begin()

        held = self.actions.down("jump")
        color = (80, 220, 80) if held else (60, 60, 90)
        self.shapes.filled_rect(self.box_x, 200, 40, 40, color)

        if self.actions.pressed("jump"):
            print("jump: pressed (rising edge)")
        if self.actions.released("jump"):
            print("jump: released (falling edge)")

        self.text.draw("Space or gamepad A = jump (box turns green while held)", 20, 20)
        self.text.draw("A/D or move_x binding = move the box", 20, 50)
        self.text.draw("Esc to quit", 20, 440)

        self.render_end()


if __name__ == "__main__":
    ActionMapApp().run()
