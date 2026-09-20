"""Sprite-sheet animation.

An `Actor` owns a `Sprite` (`actor.sprite`) and drives it through named
*states* (e.g. "walk_left", "idle"), each state playing a *frame sequence*. Frame sequences and states
live in one shared library owned by the app; build it either from a JSON
file (`App.load_anim_file`) or programmatically (`App.create_sequence` /
`add_frame` / `add_anim_state`), then attach states to individual actors.

    app.load_texture("hero", "assets/hero.png")
    for i in range(4):
        app.create_subtexture(f"hero_walk{i}", "hero", i * 16, 0, 16, 16)
    app.create_sequence("walk", loop=True)
    for i in range(4):
        app.add_frame("walk", f"hero_walk{i}", 120)
    app.add_anim_state("walk_right", "walk")
    app.add_anim_state("walk_left", "walk", flip=Flip.HORZ)

    self.hero = app.create_actor("hero_walk0")
    self.hero.add_state("walk_right")
    self.hero.add_state("walk_left")
    self.hero.set_state("walk_right")

    # in update(dt):
    self.hero.update(dt)
    self.hero.sprite.set_pos(x, y)

    # in render():
    self.hero.sprite.draw()
"""
from . import _native as _n
from .sprite import Sprite


class Actor:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False
        # The actor's own sprite; freed with the actor.
        self.sprite = Sprite(_n.pz_actor_sprite(handle), owner=self)

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.Error("actor already destroyed (or the app has shut down)")

    def add_state(self, name: str) -> None:
        """Copies a state registered on the app (by name) into this actor.
        The first state added becomes the current one."""
        self._check_alive()
        _n.check(_n.pz_actor_add_state(self._handle, name.encode("utf-8")) == 0)

    def set_state(self, name: str) -> None:
        """Switches to `name` and applies its first frame to the sprite now."""
        self._check_alive()
        _n.pz_actor_set_state(self._handle, name.encode("utf-8"))

    def update(self, dt_ms: float) -> None:
        """Advances the animation by `dt_ms`, updating the sprite's frame."""
        self._check_alive()
        _n.pz_actor_update(self._handle, float(dt_ms))

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_actor_destroy(self._handle)
            self._destroyed = True
