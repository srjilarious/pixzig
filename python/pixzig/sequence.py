"""Sequences: scripted moments written as generators, the Python take on
the engine's sequencer.

A sequence is a generator that yields steps. Code between yields runs right
away, in the tick the sequence reaches it, so setting values, playing a
sound or spawning something costs no time. A yielded step takes as long as
it takes, and time it doesn't need carries into what comes next, so two
30 ms waits end after 60 ms, not after whole ticks.

    from pixzig import Ease
    from pixzig.sequence import SequencePlayer, move_to, parallel, tween_attr, wait

    def open_door(self):
        self.audio.play("creak")
        yield tween_attr(self, "door_open", 1.0, 400, Ease.QUAD_OUT)
        yield wait(1000)
        yield parallel(move_to(self.hero, 80, 16, 300), self.fade_music())
        self.door_done = True

    # In __init__:
    self.seq = SequencePlayer()
    # When the switch is hit:
    self.seq.play(self.open_door(), tag="door")
    # In update:
    self.seq.update(dt_ms)

A bare `yield` waits until the next tick. A generator can `yield` another
generator (a sub-sequence) or `yield from` it.
"""
from .easing import ease as _ease


class Step:
    """One step a sequence yields. Subclass it for your own: `update`
    advances by `dt_ms` and returns None while the step needs more time, or
    the part of `dt_ms` it didn't use (0 or more) once it's finished. The
    first `update` can get a `dt_ms` of 0, when the step before it ended
    exactly at the end of a tick."""

    def update(self, dt_ms: float):
        raise NotImplementedError


class _Wait(Step):
    def __init__(self, ms: float):
        self.ms = float(ms)
        self.elapsed = 0.0

    def update(self, dt_ms):
        self.elapsed += dt_ms
        return _finished_after(self.elapsed, self.ms)


def _finished_after(elapsed: float, duration: float):
    """What a step that has run `elapsed` of `duration` returns."""
    if elapsed >= duration:
        return elapsed - max(duration, 0.0)
    return None


def _progress(elapsed: float, duration: float) -> float:
    if duration <= 0:
        return 1.0
    return min(elapsed / duration, 1.0)


class _Tween(Step):
    def __init__(self, apply, start, to, ms, curve):
        self.apply = apply
        # A callable reads the start value on the first tick (`tween_attr`).
        self.start = start
        self.to = float(to)
        self.ms = float(ms)
        self.curve = curve
        self.elapsed = 0.0

    def update(self, dt_ms):
        if callable(self.start):
            self.start = float(self.start())
        self.elapsed += dt_ms
        t = _ease(self.curve, _progress(self.elapsed, self.ms))
        self.apply(self.start + (self.to - self.start) * t)
        return _finished_after(self.elapsed, self.ms)


class _MoveTo(Step):
    def __init__(self, sprite, x, y, ms, curve):
        self.sprite = sprite
        self.target = (float(x), float(y))
        self.ms = float(ms)
        self.curve = curve
        self.elapsed = 0.0
        self.start = None

    def update(self, dt_ms):
        if self.start is None:
            self.start = self.sprite.pos
        self.elapsed += dt_ms
        t = _ease(self.curve, _progress(self.elapsed, self.ms))
        sx, sy = self.start
        tx, ty = self.target
        self.sprite.set_pos(sx + (tx - sx) * t, sy + (ty - sy) * t)
        return _finished_after(self.elapsed, self.ms)


class _Track:
    """Runs one generator: advances through its steps, carrying leftover
    time from each into the next."""

    def __init__(self, gen):
        self.gen = gen
        self.step = None
        # Set by `SequencePlayer.cancel`, possibly from the generator's own
        # code while it runs.
        self.cancelled = False

    def advance(self, dt_ms: float):
        """None while the track needs more time; the unused part of `dt_ms`
        once its generator has finished."""
        remaining = dt_ms
        while True:
            if self.cancelled:
                return remaining
            if self.step is None:
                try:
                    yielded = next(self.gen)
                except StopIteration:
                    return remaining
                if self.cancelled:
                    return remaining
                if yielded is None:
                    # A bare `yield`: wait for the next tick.
                    return None
                self.step = _as_step(yielded)
            left = self.step.update(remaining)
            if left is None:
                return None
            self.step = None
            remaining = left


class _Parallel(Step):
    def __init__(self, gens):
        self.tracks = [_Track(g) for g in gens]
        self.done = [False] * len(self.tracks)

    def update(self, dt_ms):
        # The step ends with its slowest track, so what's left over is the
        # smallest leftover among the tracks finishing this tick.
        leftover = dt_ms
        for i, track in enumerate(self.tracks):
            if self.done[i]:
                continue
            left = track.advance(dt_ms)
            if left is not None:
                self.done[i] = True
                leftover = min(leftover, left)
        if all(self.done):
            return leftover
        return None


def _as_step(value) -> Step:
    if isinstance(value, Step):
        return value
    if hasattr(value, "__next__"):
        return _SubSequence(value)
    raise TypeError(f"a sequence yielded {value!r}, which isn't a step or a generator")


class _SubSequence(Step):
    def __init__(self, gen):
        self.track = _Track(gen)

    def update(self, dt_ms):
        return self.track.advance(dt_ms)


def wait(ms: float) -> Step:
    """Waits `ms` milliseconds."""
    return _Wait(ms)


def tween(apply, start: float, to: float, ms: float, curve: int = 0) -> Step:
    """Calls `apply(value)` every tick with a value easing from `start` to
    `to` over `ms` along `curve` (an `Ease`, linear by default)."""
    return _Tween(apply, float(start), to, ms, curve)


def tween_attr(obj, name: str, to: float, ms: float, curve: int = 0) -> Step:
    """Eases `obj.<name>` from whatever it holds when the step starts to
    `to`, so it picks up where an earlier or cancelled tween left off."""
    return _Tween(lambda v: setattr(obj, name, v), lambda: getattr(obj, name), to, ms, curve)


def move_to(sprite, x: float, y: float, ms: float, curve: int = 0) -> Step:
    """Moves a `Sprite` (or `actor.sprite`) from where it is when the step
    starts to (x, y) over `ms`, along `curve`."""
    return _MoveTo(sprite, x, y, ms, curve)


def parallel(*gens) -> Step:
    """Runs several generators side by side, finishing when the last one
    does."""
    return _Parallel(gens)


class _Playing:
    __slots__ = ("track", "tag", "done")

    def __init__(self, gen, tag):
        self.track = _Track(gen)
        self.tag = tag
        self.done = False


class SequencePlayer:
    """Runs any number of sequences at once and drops them when they
    finish. Keep one for the game and call `update` every tick.

    Code in a sequence may play, cancel or clear sequences, including its
    own. One played that way starts on the next `update`; a cancel takes
    effect at once."""

    def __init__(self):
        self._playing = []
        self._incoming = []
        self._updating = False

    def play(self, gen, tag: str = None) -> None:
        """Starts running the generator `gen`. A `tag` lets `is_running`
        and `cancel` find it later."""
        if not hasattr(gen, "__next__"):
            raise TypeError("play() takes a generator: call the sequence function, e.g. play(self.intro())")
        entry = _Playing(gen, tag)
        if self._updating:
            self._incoming.append(entry)
        else:
            self._playing.append(entry)

    def update(self, dt_ms: float) -> None:
        """Advances every sequence by `dt_ms` and drops the ones that
        finished."""
        self._updating = True
        try:
            for entry in self._playing:
                if entry.done:
                    continue
                if entry.track.advance(dt_ms) is not None:
                    entry.done = True
        finally:
            self._updating = False
            self._playing = [e for e in self._playing if not e.done]
            self._playing.extend(e for e in self._incoming if not e.done)
            self._incoming = []

    def is_running(self, tag: str) -> bool:
        """Whether an unfinished sequence tagged `tag` is playing."""
        return any(not e.done and e.tag == tag for e in self._playing + self._incoming)

    def cancel(self, tag: str) -> int:
        """Stops every sequence tagged `tag` where it is, and returns how
        many were stopped. Their generators are closed, so `finally` blocks
        in them run."""
        count = 0
        for entry in self._playing + self._incoming:
            if not entry.done and entry.tag == tag:
                self._stop(entry)
                count += 1
        self._drop_stopped()
        return count

    def clear(self) -> None:
        """Stops every sequence."""
        for entry in self._playing + self._incoming:
            if not entry.done:
                self._stop(entry)
        self._drop_stopped()

    @property
    def count(self) -> int:
        """How many sequences are playing, e.g. to ignore input during a
        cutscene."""
        return sum(1 for e in self._playing + self._incoming if not e.done)

    def _stop(self, entry: _Playing) -> None:
        entry.done = True
        entry.track.cancelled = True
        # Closing a generator that's running (one cancelling itself) raises;
        # it finishes on its own when it next yields.
        try:
            entry.track.gen.close()
        except ValueError:
            pass

    def _drop_stopped(self) -> None:
        if self._updating:
            return
        self._playing = [e for e in self._playing if not e.done]
        self._incoming = [e for e in self._incoming if not e.done]
