"""Sound effects, music and generated audio, reached as `App.audio`.

Load a sound or music track once under a name, then play it by that name.
Playing a sound whose voices are all busy restarts the one that has played
longest, so `play` always returns a voice. A voice handle goes stale once
its voice is reused or a stream ends; calls with a stale one do nothing.

Relative paths resolve against the app's asset root, the main script's
directory unless `App(..., asset_root=...)` says otherwise. See
`pixzig.paths`.

Example:
        app.audio.load("jump", "assets/jump.wav")
        voice = app.audio.play("jump", volume=0.8, pan=-0.3)
        app.audio.stop(voice, fade_ms=200)

        app.audio.load_music("theme", "assets/theme.ogg")
        app.audio.play_music("theme", fade_ms=1000)
        app.audio.set_bus_volume(Bus.MUSIC, 0.5)
"""
import ctypes

from . import _native as _n


class Bus:
    """A mixing bus. `SFX` and `MUSIC` both feed `MASTER`.

    Mirrors `audio.Bus` in src/pixzig/audio.zig.

    Attributes:
        MASTER: Everything.
        SFX: Sounds and, by default, streams.
        MUSIC: The music track.
    """

    MASTER = 0
    SFX = 1
    MUSIC = 2


class Audio:
    """Plays sounds, music and generated audio. Reached as `App.audio`.

    Pixzig reads WAV, FLAC, MP3 and Ogg Vorbis. Use Ogg or FLAC for looping
    music: MP3 leaves a short gap each time it wraps.
    """
    def __init__(self, eng, paths):
        self._eng = eng
        self._paths = paths
        # ctypes callbacks for live streams, keyed by voice gen, so they
        # aren't garbage collected while the audio thread calls them.
        self._streams = {}

    # --- Sound effects -------------------------------------------------------

    def load(self, name: str, path: str) -> None:
        """Loads a sound effect, decoded into memory so it starts instantly.

        Args:
            name: The name to play it by.
            path: The audio file, relative to the asset root.

        Raises:
            FileNotFoundError: The file doesn't exist; the message names the
                resolved path and the asset root.
            pixzig.Error: The file couldn't be read or decoded.
        """
        _n.check(_n.pz_audio_load(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def play(self, name: str, volume: float = 1.0, pan: float = 0.0, pitch: float = 1.0,
             loop: bool = False) -> _n.PzVoice:
        """Plays a loaded sound.

        Playing a sound that's already playing starts another voice, so rapid fire
        overlaps instead of cutting itself off.

        Args:
            name: The sound's name from `load`.
            volume: Linear gain.
            pan: From -1 (full left) to 1 (full right).
            pitch: Playback rate; 2.0 is an octave up and twice as fast.
            loop: Repeat until stopped.

        Returns:
            The voice handle, for `stop`, `set_volume` and the rest.

        Raises:
            pixzig.Error: No sound has that name.
        """
        voice = _n.PzVoice()
        _n.check(_n.pz_audio_play(self._eng, name.encode("utf-8"), volume, pan, pitch, loop,
                                  ctypes.byref(voice)) == 0)
        return voice

    def stop(self, voice: _n.PzVoice, fade_ms: int = 0) -> None:
        """Stops one voice or stream.

        A voice fading out still counts as playing until the fade ends, and asking
        it to fade again meanwhile is ignored.

        Args:
            voice: The voice from `play` or `play_stream`.
            fade_ms: Fade out over this many milliseconds; 0 stops at once.
        """
        _n.pz_audio_stop(self._eng, voice, fade_ms)

    def stop_sound(self, name: str, fade_ms: int = 0) -> None:
        """Stops every voice of a loaded sound.

        Args:
            name: The sound's name.
            fade_ms: Fade out over this many milliseconds.

        Raises:
            pixzig.Error: No sound has that name.
        """
        _n.check(_n.pz_audio_stop_sound(self._eng, name.encode("utf-8"), fade_ms) == 0)

    def is_playing(self, voice: _n.PzVoice) -> bool:
        """Whether a voice is still playing.

        Args:
            voice: A voice from `play` or `play_stream`.

        Returns:
            False once it has ended, been stopped, or gone stale.
        """
        return _n.pz_audio_is_playing(self._eng, voice)

    def set_volume(self, voice: _n.PzVoice, volume: float) -> None:
        """Changes a playing voice's volume.

        Args:
            voice: The voice.
            volume: Linear gain.
        """
        _n.pz_audio_set_voice_volume(self._eng, voice, volume)

    def set_pan(self, voice: _n.PzVoice, pan: float) -> None:
        """Changes a playing voice's pan.

        Args:
            voice: The voice.
            pan: From -1 (full left) to 1 (full right).
        """
        _n.pz_audio_set_voice_pan(self._eng, voice, pan)

    def set_pitch(self, voice: _n.PzVoice, pitch: float) -> None:
        """Changes a playing voice's pitch, e.g. an engine hum that follows speed.

        Args:
            voice: The voice.
            pitch: Playback rate; 2.0 is an octave up.
        """
        _n.pz_audio_set_voice_pitch(self._eng, voice, pitch)

    # --- Music ---------------------------------------------------------------

    def load_music(self, name: str, path: str) -> None:
        """Opens a music track, streamed from disk as it plays.

        Args:
            name: The name to play it by.
            path: The audio file, relative to the asset root.

        Raises:
            FileNotFoundError: The file doesn't exist; the message names the
                resolved path and the asset root.
            pixzig.Error: The file couldn't be opened.
        """
        _n.check(_n.pz_music_load(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def play_music(self, name: str, loop: bool = True, volume: float = 1.0, fade_ms: int = 0) -> None:
        """Makes a track the current music. One track plays at a time.

        Asking for the track that's already playing doesn't restart it, so it's
        safe to call every time a level loads.

        Args:
            name: The track's name from `load_music`.
            loop: Repeat when it ends.
            volume: Linear gain.
            fade_ms: Fade in over this many milliseconds, crossfading out a
                different track that's playing.

        Raises:
            pixzig.Error: No track has that name.
        """
        _n.check(_n.pz_music_play(self._eng, name.encode("utf-8"), loop, volume, fade_ms) == 0)

    def stop_music(self, fade_ms: int = 0) -> None:
        """Stops the current music track.

        Args:
            fade_ms: Fade out over this many milliseconds.
        """
        _n.pz_music_stop(self._eng, fade_ms)

    def pause_music(self) -> None:
        """Pauses the current music track, keeping its position."""
        _n.pz_music_pause(self._eng)

    def resume_music(self) -> None:
        """Resumes music paused with `pause_music`."""
        _n.pz_music_resume(self._eng)

    @property
    def music_playing(self) -> bool:
        """Whether a music track is audible right now."""
        return _n.pz_music_playing(self._eng)

    # --- Buses and pausing ---------------------------------------------------

    def set_bus_volume(self, bus: int, volume: float) -> None:
        """Sets a bus's volume, which is what a settings menu wants.

        Args:
            bus: A `Bus`.
            volume: Linear gain; 1.0 leaves it unchanged.

        Raises:
            pixzig.Error: Unknown bus.
        """
        _n.check(_n.pz_audio_set_bus_volume(self._eng, bus, volume) == 0)

    def bus_volume(self, bus: int) -> float:
        """Reads a bus's volume.

        Args:
            bus: A `Bus`.

        Returns:
            The linear gain set with `set_bus_volume`.
        """
        return _n.pz_audio_bus_volume(self._eng, bus)

    def pause_all(self) -> None:
        """Pauses every voice, stream and the music playing right now.

        Sounds played afterwards still play, so a pause menu's own clicks work.
        """
        _n.pz_audio_pause_all(self._eng)

    def resume_all(self) -> None:
        """Resumes everything `pause_all` paused."""
        _n.pz_audio_resume_all(self._eng)

    # --- Streams -------------------------------------------------------------

    @property
    def sample_rate(self) -> int:
        """The engine's output sample rate, in Hz."""
        return _n.pz_audio_sample_rate(self._eng)

    def play_stream(self, fill, channels: int = 2, sample_rate: int = 0, volume: float = 1.0,
                    bus: int = Bus.SFX) -> _n.PzVoice:
        """Plays audio that a Python function generates.

        `fill` runs on the audio thread and holds the GIL while it does, so keep it
        short: Python is slow enough here that complex synthesis will crackle.

        Args:
            fill: Called as `fill(out, frames, channels)`. `out` is a ctypes float
                array of `frames * channels` interleaved samples to write. Return
                how many frames it wrote; fewer than `frames` ends the stream once
                they've played.
            channels: 1 for mono, 2 for stereo.
            sample_rate: The rate `fill` generates at; 0 uses `sample_rate`, and
                anything else is resampled.
            volume: Linear gain.
            bus: The `Bus` it plays through.

        Returns:
            The stream's voice, for `stop`.

        Raises:
            pixzig.Error: The stream couldn't start.
        """
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
