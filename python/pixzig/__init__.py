"""Pixzig for Python: write 2D games against the pixzig engine.

The package talks to a shared-library build of the engine through `ctypes`,
so it needs no compiler. Subclass `App`, override `update` and `render`, and
call `run()`; the app's members (`keyboard`, `text`, `audio` and so on) and
its `create_*` methods reach the rest of the engine.

Example:
        from pixzig import App, Key

        class MyGame(App):
            def __init__(self):
                super().__init__("My Game", width=800, height=480)
                self.load_texture("pac", "assets/pac-tiles.png")
                self.player = self.load_sprite("pac")

            def update(self, dt_ms):
                if self.keyboard.pressed(Key.ESCAPE):
                    self.quit()

            def render(self, alpha):
                self.render_begin()
                self.player.draw()
                self.render_end()

        MyGame().run()
"""
from ._native import Error
from .action import ActionMap
from .anim import Actor
from .app import App
from .audio import Audio, Bus
from .camera import Camera
from . import collision, color, easing, save, sequence
from .constants import (
    BlendMode,
    Ease,
    EventKind,
    GamepadAxis,
    GamepadButton,
    InputDevice,
    Key,
    MouseAxis,
    MouseButton,
    TargetFilter,
    TextAlign,
)
from .event import Event
from .input import Finger, Gamepad, Keyboard, Mouse, Touch
from .manifest import AssetManifest
from .paths import AssetPaths
from .render_target import RenderTarget
from .sequence import SequencePlayer
from .shapes import Shapes
from .sprite import Flip, Rotate, Sprite
from .states import State, StateStack
from .text import Text
from .tilemap import TileFlags, TileMapRenderer, TileObject
from .window import ScalePolicy, Window

__all__ = [
    # Entry point and errors
    "App",
    "Error",
    # Things a game creates through the app
    "ActionMap",
    "Actor",
    "AssetManifest",
    "Camera",
    "RenderTarget",
    "SequencePlayer",
    "Sprite",
    "State",
    "StateStack",
    "TileMapRenderer",
    # Subsystems reached as app.<name>
    "Audio",
    "Gamepad",
    "Keyboard",
    "Mouse",
    "Shapes",
    "Text",
    "Touch",
    "Window",
    # Enums and value types
    "BlendMode",
    "Bus",
    "Ease",
    "Event",
    "EventKind",
    "Finger",
    "Flip",
    "GamepadAxis",
    "GamepadButton",
    "InputDevice",
    "Key",
    "MouseAxis",
    "MouseButton",
    "Rotate",
    "ScalePolicy",
    "TargetFilter",
    "TextAlign",
    "TileFlags",
    "TileObject",
    # Asset path resolution
    "AssetPaths",
    # Modules of functions
    "collision",
    "color",
    "easing",
    "save",
    "sequence",
]
