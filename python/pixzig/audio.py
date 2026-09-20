"""Sound playback. Access via `PixzigApp.audio`.

Load a sound file once under a name, then play it by that name. Playing a
name that is already sounding spins up an extra concurrent voice, up to the
engine's per-sound cap.

    app.audio.load("jump", "assets/jump.wav")
    app.audio.play("jump")

Paths are resolved against the current working directory, the same as
`PixzigApp.load_texture`.
"""
import os

from . import _native as _n


class Audio:
    def __init__(self, eng):
        self._eng = eng

    def load(self, name: str, path: str) -> None:
        # The engine resolves a relative path against the executable's own
        # directory, which under Python is the interpreter's install dir.
        # Resolve against the cwd here instead, matching `load_texture`.
        abs_path = os.path.abspath(path)
        _n.check(_n.pz_audio_load(self._eng, name.encode("utf-8"), abs_path.encode("utf-8")) == 0)

    def play(self, name: str) -> None:
        _n.check(_n.pz_audio_play(self._eng, name.encode("utf-8")) == 0)
