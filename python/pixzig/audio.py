"""Sound effects, music and generated audio. Access via `App.audio`.

Load a sound or a music track once under a name, then play it by that name:

    app.audio.load("jump", "assets/jump.wav")
    voice = app.audio.play("jump", volume=0.8, pan=-0.3)
    app.audio.stop(voice, fade_ms=200)

    app.audio.load_music("theme", "assets/theme.wav")
    app.audio.play_music("theme", fade_ms=1000)
    app.audio.set_bus_volume(Bus.MUSIC, 0.5)

Playing a sound whose voices are all busy restarts the one that has played
longest, so `play` always returns a voice. A voice handle goes stale once
its voice is reused (or a stream ends); calls taking a stale one do nothing.

A relative path is resolved against the app's asset root -- the directory of
the main script unless `App(..., asset_root=...)` says otherwise. See
`pixzig.paths`.
"""
import ctypes

from . import _native as _n


class Bus:
    """A mixing bus. `SFX` and `MUSIC` both feed `MASTER`. Mirrors
    `audio.Bus` in src/pixzig/audio.zig (declaration order)."""

    MASTER = 0
    SFX = 1
    MUSIC = 2


class Audio:
    def __init__(self, eng, paths):
        self._eng = eng
        self._paths = paths
        # ctypes callbacks for live streams, keyed by voice gen, so they
        # aren't garbage collected while the audio thread calls them.
        self._streams = {}

    # --- Sound effects -------------------------------------------------------

    def load(self, name: str, path: str) -> None:
        """Loads a sound effect (decoded into memory) under `name`."""
        _n.check(_n.pz_audio_load(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def play(self, name: str, volume: float = 1.0, pan: float = 0.0, pitch: float = 1.0,
             loop: bool = False) -> _n.PzVoice:
        """Plays a loaded sound and returns its voice handle. `pan` runs from
        -1 (left) to 1 (right); `pitch` 2.0 is an octave up."""
        voice = _n.PzVoice()
        _n.check(_n.pz_audio_play(self._eng, name.encode("utf-8"), volume, pan, pitch, loop,
                                  ctypes.byref(voice)) == 0)
        return voice

    def stop(self, voice: _n.PzVoice, fade_ms: int = 0) -> None:
        """Stops one voice (or stream), fading out over `fade_ms`."""
        _n.pz_audio_stop(self._eng, voice, fade_ms)

    def stop_sound(self, name: str, fade_ms: int = 0) -> None:
        """Stops every voice of a loaded sound."""
        _n.check(_n.pz_audio_stop_sound(self._eng, name.encode("utf-8"), fade_ms) == 0)

    def is_playing(self, voice: _n.PzVoice) -> bool:
        return _n.pz_audio_is_playing(self._eng, voice)

    def set_volume(self, voice: _n.PzVoice, volume: float) -> None:
        _n.pz_audio_set_voice_volume(self._eng, voice, volume)

    def set_pan(self, voice: _n.PzVoice, pan: float) -> None:
        _n.pz_audio_set_voice_pan(self._eng, voice, pan)

    def set_pitch(self, voice: _n.PzVoice, pitch: float) -> None:
        _n.pz_audio_set_voice_pitch(self._eng, voice, pitch)

    # --- Music ---------------------------------------------------------------

    def load_music(self, name: str, path: str) -> None:
        """Opens a music track for streaming under `name`."""
        _n.check(_n.pz_music_load(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def play_music(self, name: str, loop: bool = True, volume: float = 1.0, fade_ms: int = 0) -> None:
        """Makes a track the current music. A different track already
        playing crossfades out over `fade_ms`; the same track keeps playing."""
        _n.check(_n.pz_music_play(self._eng, name.encode("utf-8"), loop, volume, fade_ms) == 0)

    def stop_music(self, fade_ms: int = 0) -> None:
        _n.pz_music_stop(self._eng, fade_ms)

    def pause_music(self) -> None:
        _n.pz_music_pause(self._eng)

    def resume_music(self) -> None:
        _n.pz_music_resume(self._eng)

    @property
    def music_playing(self) -> bool:
        return _n.pz_music_playing(self._eng)

    # --- Buses and pausing ---------------------------------------------------

    def set_bus_volume(self, bus: int, volume: float) -> None:
        """Sets a `Bus` volume (linear, 1.0 = unchanged)."""
        _n.check(_n.pz_audio_set_bus_volume(self._eng, bus, volume) == 0)

    def bus_volume(self, bus: int) -> float:
        return _n.pz_audio_bus_volume(self._eng, bus)

    def pause_all(self) -> None:
        """Pauses everything playing now. Sounds played afterwards still play."""
        _n.pz_audio_pause_all(self._eng)

    def resume_all(self) -> None:
        _n.pz_audio_resume_all(self._eng)

    # --- Streams -------------------------------------------------------------

    @property
    def sample_rate(self) -> int:
        """The engine's output sample rate in Hz."""
        return _n.pz_audio_sample_rate(self._eng)

    def play_stream(self, fill, channels: int = 2, sample_rate: int = 0, volume: float = 1.0,
                    bus: int = Bus.SFX) -> _n.PzVoice:
        """Plays audio that `fill(out, frames, channels) -> int` generates.
        `out` is a ctypes float array of `frames * channels` interleaved
        samples to write; return the frames written (fewer ends the stream).

        `fill` runs on the audio thread and holds the GIL while it does, so
        keep it short; Python is slow enough here that complex synthesis
        will crackle."""
        def trampoline(_ctx, out, frames, chans):
            return fill(out, frames, chans)

        callback = _n.PzStreamFn(trampoline)
        voice = _n.PzVoice()
        _n.check(_n.pz_audio_play_stream(self._eng, callback, None, channels, sample_rate, volume, bus,
                                         ctypes.byref(voice)) == 0)
        # Drop callbacks whose streams have ended, then keep this one alive.
        self._streams = {g: (v, cb) for g, (v, cb) in self._streams.items()
                         if _n.pz_audio_voice_valid(self._eng, v)}
        self._streams[voice.gen] = (voice, callback)
        return voice
