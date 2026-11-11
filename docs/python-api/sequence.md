# pixzig.sequence

Module `pixzig.sequence`. Generated from its docstrings by `tools/gen_py_docs.py`.

Sequences: scripted moments written as generators.

This is the Python take on the engine's sequencer. A sequence is a generator
that yields steps. Code between yields runs right away, in the tick the
sequence reaches it, so setting values, playing a sound or spawning
something costs no time. A yielded step takes as long as it needs, and time
it doesn't use carries into what comes next, so two 30 ms waits end after
60 ms, not after whole ticks.

A bare `yield` waits until the next tick. A generator can `yield` another
generator to run it as a sub-sequence, or `yield from` it.

**Example:**

```python
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
```

## `Step`

One step a sequence yields. Subclass it for steps of your own.

**Example:**

A step that flashes a sprite white until a timer runs out:

```python
class Flash(Step):
    def __init__(self, sprite, ms):
        self.sprite, self.ms, self.elapsed = sprite, ms, 0.0

    def update(self, dt_ms):
        self.elapsed += dt_ms
        if self.elapsed < self.ms:
            self.sprite.set_fill((255, 255, 255, 255))
            return None
        self.sprite.set_fill(None)
        return self.elapsed - self.ms
```

### `Step.update`

```python
update(dt_ms: float)
```

Advances the step. Override it.

| Argument | Type | Description |
|---|---|---|
| `dt_ms` | `float` | The time to advance, in milliseconds. The first call can get 0, when the step before ended exactly at the end of a tick. |

**Returns:** None while the step needs more time, or the part of `dt_ms` it didn't
use (0 or more) once it has finished.

## `SequencePlayer`

Runs any number of sequences at once and drops them when they finish.

Keep one for the game and call [`update`](page:python-api/sequence#h3-sequenceplayer-update) every tick. Code in a sequence may
play, cancel or clear sequences, including its own. One played that way
starts on the next [`update`](page:python-api/sequence#h3-sequenceplayer-update); a cancel takes effect at once.

### `SequencePlayer.play`

```python
play(gen, tag: str = None) -> None
```

Starts running a sequence.

| Argument | Type | Default | Description |
|---|---|---|---|
| `gen` |  |  | The generator, i.e. the sequence function already called: `play(self.intro())`, not `play(self.intro)`. |
| `tag` | `str` | `None` | A name for [`is_running`](page:python-api/sequence#h3-sequenceplayer-is-running) and [`cancel`](page:python-api/sequence#h3-sequenceplayer-cancel) to find it by. Several sequences can share one. |

**Raises:**

- `TypeError`: `gen` isn't a generator.

### `SequencePlayer.update`

```python
update(dt_ms: float) -> None
```

Advances every sequence and drops the ones that finished.

| Argument | Type | Description |
|---|---|---|
| `dt_ms` | `float` | The tick's length, in milliseconds. |

### `SequencePlayer.is_running`

```python
is_running(tag: str) -> bool
```

Whether an unfinished sequence with a tag is playing.

| Argument | Type | Description |
|---|---|---|
| `tag` | `str` | The tag passed to [`play`](page:python-api/sequence#h3-sequenceplayer-play). |

**Returns:** True while one is playing.

### `SequencePlayer.cancel`

```python
cancel(tag: str) -> int
```

Stops every sequence with a tag where it is.

Their generators are closed, so `finally` blocks in them run.

| Argument | Type | Description |
|---|---|---|
| `tag` | `str` | The tag passed to [`play`](page:python-api/sequence#h3-sequenceplayer-play). |

**Returns:** How many were stopped.

### `SequencePlayer.clear`

```python
clear() -> None
```

Stops every sequence, e.g. when the level changes.

### `SequencePlayer.count`

```python
count: int  # property
```

How many sequences are playing, e.g. to ignore input during a cutscene.

## `wait`

```python
wait(ms: float) -> Step
```

A step that waits.

| Argument | Type | Description |
|---|---|---|
| `ms` | `float` | How long, in milliseconds. |

**Returns:** The [`Step`](page:python-api/sequence#h2-step).

## `tween`

```python
tween(apply, start: float, to: float, ms: float, curve: int = 0) -> Step
```

A step that eases a value and hands it to a function every tick.

| Argument | Type | Default | Description |
|---|---|---|---|
| `apply` |  |  | Called with each tick's value. |
| `start` | `float` |  | The value at the start. |
| `to` | `float` |  | The value at the end. |
| `ms` | `float` |  | How long it takes, in milliseconds. |
| `curve` | `int` | `0` | An [`Ease`](page:python-api/constants#h2-ease); linear by default. |

**Returns:** The [`Step`](page:python-api/sequence#h2-step).

## `tween_attr`

```python
tween_attr(obj, name: str, to: float, ms: float, curve: int = 0) -> Step
```

A step that eases an attribute from wherever it is when the step starts.

Starting from the current value lets a tween pick up where an earlier or
cancelled one left off.

| Argument | Type | Default | Description |
|---|---|---|---|
| `obj` |  |  | The object holding the attribute. |
| `name` | `str` |  | The attribute's name. |
| `to` | `float` |  | The value at the end. |
| `ms` | `float` |  | How long it takes, in milliseconds. |
| `curve` | `int` | `0` | An [`Ease`](page:python-api/constants#h2-ease); linear by default. |

**Returns:** The [`Step`](page:python-api/sequence#h2-step).

## `move_to`

```python
move_to(sprite, x: float, y: float, ms: float, curve: int = 0) -> Step
```

A step that moves a sprite from where it is when the step starts.

| Argument | Type | Default | Description |
|---|---|---|---|
| `sprite` |  |  | A [`Sprite`](page:python-api/sprite#h2-sprite), or an actor's `actor.sprite`. |
| `x` | `float` |  | The target x for its origin. |
| `y` | `float` |  | The target y. |
| `ms` | `float` |  | How long it takes, in milliseconds. |
| `curve` | `int` | `0` | An [`Ease`](page:python-api/constants#h2-ease); linear by default. |

**Returns:** The [`Step`](page:python-api/sequence#h2-step).

## `parallel`

```python
parallel(*gens) -> Step
```

A step that runs several generators side by side.

It finishes when the last one does. One that finishes early isn't run again
while the others catch up.

| Argument | Description |
|---|---|
| `*gens` | The generators. |

**Returns:** The [`Step`](page:python-api/sequence#h2-step).
