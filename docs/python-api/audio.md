# Audio

Module `pixzig.audio`. Generated from its docstrings by `tools/gen_py_docs.py`.

Sound effects, music and generated audio, reached as `App.audio`.

Load a sound or music track once under a name, then play it by that name. Playing a sound whose voices are all busy restarts the one that has played longest, so `play` always returns a voice. A voice handle goes stale once its voice is reused or a stream ends; calls with a stale one do nothing.

Relative paths resolve against the app's asset root, the main script's directory unless `App(..., asset_root=...)` says otherwise. See [`pixzig.paths`](page:python-api/paths).

**Example:**

```python
app.audio.load("jump", "assets/jump.wav")
voice = app.audio.play("jump", volume=0.8, pan=-0.3)
app.audio.stop(voice, fade_ms=200)

app.audio.load_music("theme", "assets/theme.ogg")
app.audio.play_music("theme", fade_ms=1000)
app.audio.set_bus_volume(Bus.MUSIC, 0.5)
```

## `Bus`

A mixing bus. `SFX` and `MUSIC` both feed `MASTER`.

Mirrors `audio.Bus` in src/pixzig/audio.zig.

| Name | Value | Description |
|---|---|---|
| `MASTER` | `0` | Everything. |
| `SFX` | `1` | Sounds and, by default, streams. |
| `MUSIC` | `2` | The music track. |

## `Audio`

Plays sounds, music and generated audio. Reached as `App.audio`.

Pixzig reads WAV, FLAC, MP3 and Ogg Vorbis. Use Ogg or FLAC for looping music: MP3 leaves a short gap each time it wraps.

### `Audio.load`

```python
load(name: str, path: str) -> None
```

Loads a sound effect, decoded into memory so it starts instantly.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The name to play it by. |
| `path` | `str` | The audio file, relative to the asset root. |

**Raises:**

- `FileNotFoundError`: The file doesn't exist; the message names the resolved path and the asset root.
- `pixzig.Error`: The file couldn't be read or decoded.

### `Audio.play`

```python
play(
    name: str,
    volume: float = 1.0,
    pan: float = 0.0,
    pitch: float = 1.0,
    loop: bool = False,
) -> _n.PzVoice
```

Plays a loaded sound.

Playing a sound that's already playing starts another voice, so rapid fire overlaps instead of cutting itself off.

| Argument | Type | Default | Description |
|---|---|---|---|
| `name` | `str` |  | The sound's name from [`load`](page:python-api/audio#h3-audio-load). |
| `volume` | `float` | `1.0` | Linear gain. |
| `pan` | `float` | `0.0` | From -1 (full left) to 1 (full right). |
| `pitch` | `float` | `1.0` | Playback rate; 2.0 is an octave up and twice as fast. |
| `loop` | `bool` | `False` | Repeat until stopped. |

**Returns:** The voice handle, for [`stop`](page:python-api/audio#h3-audio-stop), [`set_volume`](page:python-api/audio#h3-audio-set-volume) and the rest.

**Raises:**

- `pixzig.Error`: No sound has that name.

### `Audio.stop`

```python
stop(voice: _n.PzVoice, fade_ms: int = 0) -> None
```

Stops one voice or stream.

A voice fading out still counts as playing until the fade ends, and asking it to fade again meanwhile is ignored.

| Argument | Type | Default | Description |
|---|---|---|---|
| `voice` | `_n.PzVoice` |  | The voice from [`play`](page:python-api/audio#h3-audio-play) or [`play_stream`](page:python-api/audio#h3-audio-play-stream). |
| `fade_ms` | `int` | `0` | Fade out over this many milliseconds; 0 stops at once. |

### `Audio.stop_sound`

```python
stop_sound(name: str, fade_ms: int = 0) -> None
```

Stops every voice of a loaded sound.

| Argument | Type | Default | Description |
|---|---|---|---|
| `name` | `str` |  | The sound's name. |
| `fade_ms` | `int` | `0` | Fade out over this many milliseconds. |

**Raises:**

- `pixzig.Error`: No sound has that name.

### `Audio.is_playing`

```python
is_playing(voice: _n.PzVoice) -> bool
```

Whether a voice is still playing.

| Argument | Type | Description |
|---|---|---|
| `voice` | `_n.PzVoice` | A voice from [`play`](page:python-api/audio#h3-audio-play) or [`play_stream`](page:python-api/audio#h3-audio-play-stream). |

**Returns:** False once it has ended, been stopped, or gone stale.

### `Audio.set_volume`

```python
set_volume(voice: _n.PzVoice, volume: float) -> None
```

Changes a playing voice's volume.

| Argument | Type | Description |
|---|---|---|
| `voice` | `_n.PzVoice` | The voice. |
| `volume` | `float` | Linear gain. |

### `Audio.set_pan`

```python
set_pan(voice: _n.PzVoice, pan: float) -> None
```

Changes a playing voice's pan.

| Argument | Type | Description |
|---|---|---|
| `voice` | `_n.PzVoice` | The voice. |
| `pan` | `float` | From -1 (full left) to 1 (full right). |

### `Audio.set_pitch`

```python
set_pitch(voice: _n.PzVoice, pitch: float) -> None
```

Changes a playing voice's pitch, e.g. an engine hum that follows speed.

| Argument | Type | Description |
|---|---|---|
| `voice` | `_n.PzVoice` | The voice. |
| `pitch` | `float` | Playback rate; 2.0 is an octave up. |

### `Audio.load_music`

```python
load_music(name: str, path: str) -> None
```

Opens a music track, streamed from disk as it plays.

| Argument | Type | Description |
|---|---|---|
| `name` | `str` | The name to play it by. |
| `path` | `str` | The audio file, relative to the asset root. |

**Raises:**

- `FileNotFoundError`: The file doesn't exist; the message names the resolved path and the asset root.
- `pixzig.Error`: The file couldn't be opened.

### `Audio.play_music`

```python
play_music(name: str, loop: bool = True, volume: float = 1.0, fade_ms: int = 0) -> None
```

Makes a track the current music. One track plays at a time.

Asking for the track that's already playing doesn't restart it, so it's safe to call every time a level loads.

| Argument | Type | Default | Description |
|---|---|---|---|
| `name` | `str` |  | The track's name from [`load_music`](page:python-api/audio#h3-audio-load-music). |
| `loop` | `bool` | `True` | Repeat when it ends. |
| `volume` | `float` | `1.0` | Linear gain. |
| `fade_ms` | `int` | `0` | Fade in over this many milliseconds, crossfading out a different track that's playing. |

**Raises:**

- `pixzig.Error`: No track has that name.

### `Audio.stop_music`

```python
stop_music(fade_ms: int = 0) -> None
```

Stops the current music track.

| Argument | Type | Default | Description |
|---|---|---|---|
| `fade_ms` | `int` | `0` | Fade out over this many milliseconds. |

### `Audio.pause_music`

```python
pause_music() -> None
```

Pauses the current music track, keeping its position.

### `Audio.resume_music`

```python
resume_music() -> None
```

Resumes music paused with [`pause_music`](page:python-api/audio#h3-audio-pause-music).

### `Audio.music_playing`

```python
music_playing: bool  # property
```

Whether a music track is audible right now.

### `Audio.set_bus_volume`

```python
set_bus_volume(bus: int, volume: float) -> None
```

Sets a bus's volume, which is what a settings menu wants.

| Argument | Type | Description |
|---|---|---|
| `bus` | `int` | A [`Bus`](page:python-api/audio#h2-bus). |
| `volume` | `float` | Linear gain; 1.0 leaves it unchanged. |

**Raises:**

- `pixzig.Error`: Unknown bus.

### `Audio.bus_volume`

```python
bus_volume(bus: int) -> float
```

Reads a bus's volume.

| Argument | Type | Description |
|---|---|---|
| `bus` | `int` | A [`Bus`](page:python-api/audio#h2-bus). |

**Returns:** The linear gain set with [`set_bus_volume`](page:python-api/audio#h3-audio-set-bus-volume).

### `Audio.pause_all`

```python
pause_all() -> None
```

Pauses every voice, stream and the music playing right now.

Sounds played afterwards still play, so a pause menu's own clicks work.

### `Audio.resume_all`

```python
resume_all() -> None
```

Resumes everything [`pause_all`](page:python-api/audio#h3-audio-pause-all) paused.

### `Audio.sample_rate`

```python
sample_rate: int  # property
```

The engine's output sample rate, in Hz.

### `Audio.play_stream`

```python
play_stream(
    fill,
    channels: int = 2,
    sample_rate: int = 0,
    volume: float = 1.0,
    bus: int = Bus.SFX,
) -> _n.PzVoice
```

Plays audio that a Python function generates.

`fill` runs on the audio thread and holds the GIL while it does, so keep it short: Python is slow enough here that complex synthesis will crackle.

| Argument | Type | Default | Description |
|---|---|---|---|
| `fill` |  |  | Called as `fill(out, frames, channels)`. `out` is a ctypes float array of `frames * channels` interleaved samples to write. Return how many frames it wrote; fewer than `frames` ends the stream once they've played. |
| `channels` | `int` | `2` | 1 for mono, 2 for stereo. |
| `sample_rate` | `int` | `0` | The rate `fill` generates at; 0 uses [`sample_rate`](page:python-api/audio#h3-audio-sample-rate), and anything else is resampled. |
| `volume` | `float` | `1.0` | Linear gain. |
| `bus` | `int` | `Bus.SFX` | The [`Bus`](page:python-api/audio#h2-bus) it plays through. |

**Returns:** The stream's voice, for [`stop`](page:python-api/audio#h3-audio-stop).

**Raises:**

- `pixzig.Error`: The stream couldn't start.
