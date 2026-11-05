"""A stack of game states, like `GameStateMgr` on the Zig side: a title
screen, the game, a pause menu over the game.

    class Playing(State):
        def update(self, dt_ms): ...
        def render(self, alpha): ...

    class Paused(State):
        def render(self, alpha):
            self.app.render_begin()
            self.app.text.draw("PAUSED", 160, 100, align=TextAlign.CENTER)
            self.app.render_end()

    self.states = StateStack(self.playing)
    self.states.push(self.paused)          # draws over the game, which freezes
    self.states.pop()                      # back to the game

    # In App.update / App.render:
    self.states.update(dt_ms)
    self.states.render(alpha)

States are any objects with `update(dt_ms)` and `render(alpha)`; `State`
gives empty defaults for those and for the optional hooks:

* `activate` / `deactivate` -- the state entered or left the stack.
* `pause` / `resume` -- a push covered it, or a pop uncovered it. It stays
  on the stack in between.
"""


class State:
    """Optional base class for states: every method does nothing."""

    def update(self, dt_ms: float) -> None:
        pass

    def render(self, alpha: float) -> None:
        pass

    def activate(self) -> None:
        pass

    def deactivate(self) -> None:
        pass

    def pause(self) -> None:
        pass

    def resume(self) -> None:
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
    """The states, bottom first; the top one takes input. Starts holding
    `initial` (its `activate` isn't called, like the Zig side)."""

    def __init__(self, initial):
        self._stack = [_Entry(initial, True, False)]

    @property
    def current(self):
        """The state on top of the stack."""
        return self._stack[-1].state

    @property
    def depth(self) -> int:
        """How many states are on the stack (1 when nothing is pushed)."""
        return len(self._stack)

    def is_on_stack(self, state) -> bool:
        return any(e.state is state for e in self._stack)

    def set_state(self, state) -> None:
        """Replaces the whole stack with `state`: deactivates every state on
        it, top first, then activates `state`."""
        while self._stack:
            _hook(self._stack.pop().state, "deactivate")
        self._stack.append(_Entry(state, True, False))
        _hook(state, "activate")

    def push(self, state, render_below: bool = True, update_below: bool = False) -> None:
        """Lays `state` over the current one: pauses the current state and
        activates `state`.

        * `render_below` -- draw the states below first, so this one renders
          over them (a pause menu over the game). False for a state that
          covers the whole screen.
        * `update_below` -- keep updating the states below (a popup over a
          live game). False freezes them while this state is on top.

        A state can only be on the stack once; pushing one that already is
        raises ValueError and changes nothing."""
        if self.is_on_stack(state):
            raise ValueError("that state is already on the stack")
        _hook(self.current, "pause")
        self._stack.append(_Entry(state, render_below, update_below))
        _hook(state, "activate")

    def pop(self) -> None:
        """Removes the top state: deactivates it and resumes the one below.
        The bottom state can't be popped (use `set_state` to replace it);
        trying raises ValueError."""
        if len(self._stack) <= 1:
            raise ValueError("can't pop the last state")
        _hook(self._stack.pop().state, "deactivate")
        _hook(self.current, "resume")

    def update(self, dt_ms: float) -> None:
        """Updates the top state, plus each state below it for as long as
        the state above was pushed with `update_below`. Lower states update
        first."""
        first = len(self._stack) - 1
        while first > 0 and self._stack[first].update_below:
            first -= 1
        for entry in list(self._stack[first:]):
            entry.state.update(dt_ms)

    def render(self, alpha: float = 1.0) -> None:
        """Renders the top state, plus each state below it for as long as
        the state above was pushed with `render_below`. Lower states render
        first, so the top one draws over them."""
        first = len(self._stack) - 1
        while first > 0 and self._stack[first].render_below:
            first -= 1
        for entry in list(self._stack[first:]):
            entry.state.render(alpha)

    def close(self) -> None:
        """Deactivates every state still on the stack, top first."""
        while self._stack:
            _hook(self._stack.pop().state, "deactivate")
