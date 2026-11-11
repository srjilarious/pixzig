"""Sprite-sheet animation.

An `Actor` owns a `Sprite` (`actor.sprite`) and plays named states on it,
like `"walk_left"` or `"idle"`, each state playing a frame sequence. The
sequences and states live in one library shared by the whole app. Build it
from a JSON file with `App.load_anim_file`, or in code with
`App.create_sequence`, `App.add_frame` and `App.add_anim_state`, then add
states to each actor.

Example:
        app.load_texture("hero", "assets/hero.png")
        for i in range(4):
            app.create_subtexture("hero", f"hero_walk{i}", i * 16, 0, 16, 16)
        app.create_sequence("walk", loop=True)
        for i in range(4):
            app.add_frame("walk", f"hero_walk{i}", 120)
        app.add_anim_state("walk_right", "walk")
        app.add_anim_state("walk_left", "walk", flip=Flip.HORZ)

        self.hero = app.create_actor("hero_walk0")
        self.hero.add_state("walk_right")
        self.hero.add_state("walk_left")

        # In update(dt_ms):
        self.hero.update(dt_ms)
        self.hero.sprite.set_pos(x, y)

        # In render(alpha):
        self.hero.sprite.draw()
"""
from . import _native as _n
from .sprite import Sprite


class Actor:
    """A sprite that plays animation states. Create one with `App.create_actor()`.

    Attributes:
        sprite: The `Sprite` it animates. Move, scale and draw the actor
            through it. It's freed with the actor.
    """
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False
        # The actor's own sprite; freed with the actor.
        self.sprite = Sprite(_n.pz_actor_sprite(handle), owner=self)

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.Error("actor already destroyed (or the app has shut down)")

    def add_state(self, name: str) -> None:
        """Adds a state from the app's animation library to this actor.

        The first state added becomes the current one.

        Args:
            name: A state registered with `App.add_anim_state` or
                `App.load_anim_file`.

        Raises:
            pixzig.Error: No state has that name.
        """
        self._check_alive()
        _n.check(_n.pz_actor_add_state(self._handle, name.encode("utf-8")) == 0)

    def set_state(self, name: str) -> None:
        """Switches to a state and shows its first frame right away.

        Switching to the state the actor is already in does nothing, so it's safe
        to call every tick.

        Args:
            name: A state added with `add_state`.

        Raises:
            pixzig.Error: The actor has no state with that name.
        """
        self._check_alive()
        _n.check(_n.pz_actor_set_state(self._handle, name.encode("utf-8")) == 0)

    @property
    def finished(self) -> bool:
        """Whether a play-once state with no `next_state` has reached its last frame.

        The actor holds that frame until the state changes, which clears this.
        """
        self._check_alive()
        return bool(_n.pz_actor_finished(self._handle))

    def update(self, dt_ms: float) -> None:
        """Advances the animation, updating the sprite's frame.

        A delta longer than the current frame steps through as many frames as it
        covers, so animations keep their pace however time arrives.

        Args:
            dt_ms: The time to advance, in milliseconds.
        """
        self._check_alive()
        _n.pz_actor_update(self._handle, float(dt_ms))

    def destroy(self) -> None:
        """Frees the actor and its sprite now instead of when the app shuts down.

        Calling it twice does nothing. Using the actor afterwards raises.
        """
        if not self._destroyed:
            _n.pz_actor_destroy(self._handle)
            self._destroyed = True
