"""The game's named controls, and the keys and gamepad buttons bound to them
(controls.zig). Game code asks about actions (`actions.pressed("jump")`),
never about keys, so rebinding is a change here only."""

from pixzig import GamepadButton, Key

BINDINGS = [
    ("left", [Key.LEFT, Key.A], [GamepadButton.DPAD_LEFT]),
    ("right", [Key.RIGHT, Key.D], [GamepadButton.DPAD_RIGHT]),
    ("jump", [Key.SPACE, Key.UP, Key.W, Key.Z], [GamepadButton.A]),
    ("confirm", [Key.ENTER], [GamepadButton.START]),
    ("pause", [Key.P], [GamepadButton.START]),
    ("back", [Key.ESCAPE], [GamepadButton.BACK]),
]


def bind(actions):
    """Binds keyboard and gamepad controls for every action."""
    for action, keys, buttons in BINDINGS:
        for key in keys:
            actions.bind_key(action, key)
        for button in buttons:
            actions.bind_gamepad_button(action, button)
