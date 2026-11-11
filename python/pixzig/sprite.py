"""Sprites: a texture region drawn at a position, with an origin, scale and
color options.

Create one with `App.load_sprite(texture_name)`. An actor's sprite is
`actor.sprite`.
"""
import ctypes
from enum import IntEnum

from . import _native as _n


class Rotate(IntEnum):
    """A quarter-turn rotation or flip applied when a sprite is drawn.

    The sprite's rect stays the same, so quarter turns are meant for square
    sprites. Matches the engine's `Rotate` enum.

    Attributes:
        NONE: Drawn as is.
        ROT90: A quarter turn clockwise.
        ROT180: A half turn.
        ROT270: Three quarter turns clockwise.
        FLIP_HORZ: Mirrored left to right.
        FLIP_VERT: Mirrored top to bottom.
    """

    NONE = 0
    ROT90 = 1
    ROT180 = 2
    ROT270 = 3
    FLIP_HORZ = 4
    FLIP_VERT = 5


class Flip(IntEnum):
    """A flip for an animation frame or state. Matches the engine's `Flip` enum.

    A frame's flip and its state's flip combine, and two flips on the same axis
    cancel out.

    Attributes:
        NONE: No flip.
        HORZ: Mirrored left to right.
        VERT: Mirrored top to bottom.
        BOTH: Both.
    """

    NONE = 0
    HORZ = 1
    VERT = 2
    BOTH = 3


class Sprite:
    """A texture region drawn at a position. Create one with `App.load_sprite()`.

    Positions are floats, so slow movement accumulates smoothly, but the sprite
    snaps to a whole pixel when drawn, so it never comes out blurry.
    """
    def __init__(self, handle, owner=None):
        self._handle = handle
        self._destroyed = False
        # The Actor this sprite belongs to, or None for a standalone sprite.
        # An actor's sprite lives and dies with the actor.
        self._owner = owner

    def _check_alive(self) -> None:
        if self._destroyed or (self._owner is not None and self._owner._destroyed):
            raise _n.Error("sprite already destroyed (or the app has shut down)")

    def set_pos(self, x: float, y: float) -> None:
        """Moves the sprite's origin to a point.

        The origin is the top-left corner unless `set_origin` moved it.

        Args:
            x: The x, in the pass's coordinates.
            y: The y.
        """
        self._check_alive()
        _n.pz_sprite_set_pos(self._handle, float(x), float(y))

    def set_origin(self, x: float, y: float) -> None:
        """Sets the pivot that `set_pos` places and scaling grows around.

        The sprite stays where it is on screen.

        Args:
            x: The pivot's x in the frame's own pixels; `(8, 16)` is the
                bottom-center of a 16x16 frame.
            y: The pivot's y.
        """
        self._check_alive()
        _n.pz_sprite_set_origin(self._handle, float(x), float(y))

    def set_size(self, w: float, h: float) -> None:
        """Resizes the sprite on screen, around its origin.

        Args:
            w: The width.
            h: The height.
        """
        self._check_alive()
        _n.pz_sprite_set_size(self._handle, float(w), float(h))

    def set_scale(self, sx: float, sy: float = None) -> None:
        """Scales the sprite relative to its frame's size, around its origin.

        Args:
            sx: The horizontal scale; 2 doubles it and 1 restores it.
            sy: The vertical scale. None uses `sx`, for a uniform scale.
        """
        self._check_alive()
        if sy is None:
            sy = sx
        _n.pz_sprite_set_scale(self._handle, float(sx), float(sy))

    def set_rotate(self, rotate: Rotate) -> None:
        """Sets a quarter-turn rotation or flip.

        Args:
            rotate: A `Rotate`.
        """
        self._check_alive()
        _n.pz_sprite_set_rotate(self._handle, int(rotate))

    def set_src_rect(self, x: int, y: int, w: int, h: int) -> None:
        """Draws only part of the sprite's frame.

        Args:
            x: The region's left edge, in the texture's pixels.
            y: The region's top edge.
            w: The region's width.
            h: The region's height.
        """
        self._check_alive()
        _n.pz_sprite_set_src_rect(self._handle, int(x), int(y), int(w), int(h))

    def set_tint(self, color) -> None:
        """Multiplies the sprite's colors by a color.

        Args:
            color: An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. White
                clears the tint; an alpha below 255 fades the sprite.
        """
        self._check_alive()
        if len(color) == 3:
            r, g, b = color
            a = 255
        else:
            r, g, b, a = color
        _n.pz_sprite_set_tint(self._handle, r / 255.0, g / 255.0, b / 255.0, a / 255.0)

    def clear_tint(self) -> None:
        """Removes the tint, drawing the sprite in its own colors."""
        self._check_alive()
        _n.pz_sprite_set_tint(self._handle, 1.0, 1.0, 1.0, 1.0)

    def set_fill(self, color) -> None:
        """Draws the sprite as a solid-color silhouette, keeping its shape.

        Use it for a hit flash, a shadow or a selection highlight. It takes
        precedence over the tint.

        Args:
            color: An `(r, g, b)` or `(r, g, b, a)` tuple of 0-255 values. The alpha
                blends between the sprite's own colors (0) and a solid fill (255).
                None draws the sprite normally again.
        """
        self._check_alive()
        if color is None:
            _n.pz_sprite_set_fill(self._handle, False, 0.0, 0.0, 0.0, 0.0)
            return
        if len(color) == 3:
            r, g, b = color
            a = 255
        else:
            r, g, b, a = color
        _n.pz_sprite_set_fill(self._handle, True, r / 255.0, g / 255.0, b / 255.0, a / 255.0)

    @property
    def rect(self):
        """The sprite's rect on screen, as `(x, y, w, h)`."""
        self._check_alive()
        x, y, w, h = ctypes.c_float(), ctypes.c_float(), ctypes.c_float(), ctypes.c_float()
        _n.pz_sprite_get_rect(self._handle, ctypes.byref(x), ctypes.byref(y), ctypes.byref(w), ctypes.byref(h))
        return (x.value, y.value, w.value, h.value)

    @property
    def pos(self):
        """The origin's position, as `(x, y)`: what `set_pos` set."""
        self._check_alive()
        x, y = ctypes.c_float(), ctypes.c_float()
        _n.pz_sprite_get_pos(self._handle, ctypes.byref(x), ctypes.byref(y))
        return (x.value, y.value)

    @property
    def size(self):
        """The sprite's size on screen, as `(w, h)`."""
        self._check_alive()
        w, h = ctypes.c_float(), ctypes.c_float()
        _n.pz_sprite_get_size(self._handle, ctypes.byref(w), ctypes.byref(h))
        return (w.value, h.value)

    @property
    def width(self) -> float:
        """The sprite's width on screen."""
        return self.rect[2]

    @property
    def height(self) -> float:
        """The sprite's height on screen."""
        return self.rect[3]

    def draw(self) -> None:
        """Draws the sprite. Call it inside a render pass."""
        self._check_alive()
        _n.pz_sprite_draw(self._handle)

    def destroy(self) -> None:
        """Frees the sprite now instead of when the app shuts down.

        An actor's sprite is freed with its actor, so this does nothing for one.
        Calling it twice does nothing. Using the sprite afterwards raises.
        """
        if self._owner is not None:
            return
        if not self._destroyed:
            _n.pz_sprite_destroy(self._handle)
            self._destroyed = True
