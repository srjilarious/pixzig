"""A stack of game states, like `GameStateMgr` on the Zig side.

A title screen, the game, and a pause menu over the game are each a state.
States are any objects with `update(dt_ms)` and `render(alpha)`; `State`
gives empty defaults for those and for the optional hooks:

* `activate` and `deactivate`: the state entered or left the stack.
* `pause` and `resume`: a push covered it, or a pop uncovered it. It stays
  on the stack in between.

Example:
        class Playing(State):
            def update(self, dt_ms): ...
            def render(self, alpha): ...

        class Paused(State):
            def render(self, alpha):
                self.app.render_begin()
                self.app.text.draw("PAUSED", 160, 100, align=TextAlign.CENTER)
                self.app.render_end()

        self.states = StateStack(self.playing)
        self.states.push(self.paused)   # draws over the game, which freezes
        self.states.pop()               # back to the game

        # In App.update and App.render:
        self.states.update(dt_ms)
        self.states.render(alpha)
"""


class State:
    """An optional base class for states, where every method does nothing.

    Override the ones a state needs.
    """

    def update(self, dt_ms: float) -> None:
        """Called each tick while the state updates.

        Args:
            dt_ms: The tick's length, in milliseconds.
        """
        pass

    def render(self, alpha: float) -> None:
        """Called each frame while the state renders.

        Args:
            alpha: The interpolation alpha passed to `App.render`.
        """
        pass

    def activate(self) -> None:
        """Called when the state enters the stack."""
        pass

    def deactivate(self) -> None:
        """Called when the state leaves the stack."""
        pass

    def pause(self) -> None:
        """Called when a `push` covers the state."""
        pass

    def resume(self) -> None:
        """Called when a `pop` uncovers the state again."""
        pass


class _Entry:
    __slots__ = ("state", "render_below", "update_below")

    def __init__(self, state, render_below: bool, update_below: bool):
        self.state = state
        self.render_below = render_below
        self.update_below = update_below


def _hook(state, name: str) -> None:
    fn = getattr(state, name, None)
    if fn is not None:
        fn()


class StateStack:
    """The states, bottom first; the top one takes input.

    Args:
        initial: The state to start with. Its `activate` isn't called, like
            the Zig side.
    """

    def __init__(self, initial):
        self._stack = [_Entry(initial, True, False)]

    @property
    def current(self):
        """The state on top of the stack."""
        return self._stack[-1].state

    @property
    def depth(self) -> int:
        """How many states are on the stack: 1 when nothing is pushed."""
        return len(self._stack)

    def is_on_stack(self, state) -> bool:
        """Whether a state is anywhere on the stack.

        Args:
            state: The state object.

        Returns:
            True when it's on the stack, covered or not.
        """
        return any(e.state is state for e in self._stack)

    def set_state(self, state) -> None:
        """Replaces the whole stack with one state.

        Deactivates every state on it, top first, then activates the new one.

        Args:
            state: The new state.
        """
        while self._stack:
            _hook(self._stack.pop().state, "deactivate")
        self._stack.append(_Entry(state, True, False))
        _hook(state, "activate")

    def push(self, state, render_below: bool = True, update_below: bool = False) -> None:
        """Lays a state over the current one, e.g. a pause menu over the game.

        Pauses the current state and activates the new one.

        Args:
            state: The state to push.
            render_below: Render the states below first, so this one draws over
                them. False for a state that covers the whole screen.
            update_below: Keep updating the states below, for a popup over a live
                game. False freezes them while this state is on top.

        Raises:
            ValueError: The state is already on the stack. Nothing changes.
        """
        if self.is_on_stack(state):
            raise ValueError("that state is already on the stack")
        _hook(self.current, "pause")
        self._stack.append(_Entry(state, render_below, update_below))
        _hook(state, "activate")

    def pop(self) -> None:
        """Removes the top state, deactivating it and resuming the one below.

        Raises:
            ValueError: Only the bottom state is left; replace it with `set_state`.
        """
        if len(self._stack) <= 1:
            raise ValueError("can't pop the last state")
        _hook(self._stack.pop().state, "deactivate")
        _hook(self.current, "resume")

    def update(self, dt_ms: float) -> None:
        """Updates the top state, and the states below it it lets update.

        Each state below updates for as long as the state above it was pushed with
        `update_below`. Lower states update first.

        Args:
            dt_ms: The tick's length, in milliseconds.
        """
        first = len(self._stack) - 1
        while first > 0 and self._stack[first].update_below:
            first -= 1
        for entry in list(self._stack[first:]):
            entry.state.update(dt_ms)

    def render(self, alpha: float = 1.0) -> None:
        """Renders the top state, and the states below it it lets render.

        Each state below renders for as long as the state above it was pushed with
        `render_below`. Lower states render first, so the top one draws over them.

        Args:
            alpha: The interpolation alpha from `App.render`.
        """
        first = len(self._stack) - 1
        while first > 0 and self._stack[first].render_below:
            first -= 1
        for entry in list(self._stack[first:]):
            entry.state.render(alpha)

    def close(self) -> None:
        """Deactivates every state still on the stack, top first."""
        while self._stack:
            _hook(self._stack.pop().state, "deactivate")
