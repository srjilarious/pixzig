"""Sprite-sheet animation.

An `Actor` drives a `Sprite` through named *states* (e.g. "walk_left",
"idle"), each state playing a *frame sequence*. Frame sequences and states
live in one shared library owned by the app; build it either from a JSON
file (`PixzigApp.load_anim_file`) or programmatically
(`PixzigApp.create_sequence` / `add_frame` / `add_anim_state`), then attach
states to individual actors.

    app.load_texture("hero", "assets/hero.png")
    for i in range(4):
        app.create_subtexture(f"hero_walk{i}", "hero", i * 16, 0, 16, 16)
    app.create_sequence("walk", loop=True)
    for i in range(4):
        app.add_frame("walk", f"hero_walk{i}", 120)
    app.add_anim_state("walk_right", "walk")
    app.add_anim_state("walk_left", "walk", flip=Flip.HORZ)

    self.hero = app.load_sprite("hero_walk0")
    self.actor = app.create_actor()
    self.actor.add_state("walk_right")
    self.actor.add_state("walk_left")
    self.actor.set_state("walk_right", self.hero)

    # in update(dt):
    self.actor.update(dt, self.hero)
"""
from . import _native as _n


class Actor:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.PixzigError("actor already destroyed")

    def add_state(self, name: str) -> None:
        """Copies a state registered on the app (by name) into this actor.
        The first state added becomes the current one."""
        self._check_alive()
        _n.check(_n.pz_actor_add_state(self._handle, name.encode("utf-8")) == 0)

    def set_state(self, name: str, sprite) -> None:
        """Switches to `name` and applies its first frame to `sprite` now."""
        self._check_alive()
        _n.pz_actor_set_state(self._handle, name.encode("utf-8"), sprite._handle)

    def update(self, dt_ms: float, sprite) -> None:
        """Advances the animation by `dt_ms` and writes the current frame
        (texture sub-rect + flip) into `sprite`."""
        self._check_alive()
        _n.pz_actor_update(self._handle, float(dt_ms), sprite._handle)

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_actor_destroy(self._handle)
            self._destroyed = True
