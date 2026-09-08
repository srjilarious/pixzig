"""Sound playback. Access via `PixzigApp.audio`.

Load a sound file once under a name, then play it by that name. Playing a
name that is already sounding spins up an extra concurrent voice, up to the
engine's per-sound cap.

    app.audio.load("jump", "assets/jump.wav")
    app.audio.play("jump")

Paths are resolved against the current working directory, the same as
`PixzigApp.load_texture`.
"""
from . import _native as _n


class Audio:
    def __init__(self, eng):
        self._eng = eng

    def load(self, name: str, path: str) -> None:
        _n.check(_n.pz_audio_load(self._eng, name.encode("utf-8"), path.encode("utf-8")) == 0)

    def play(self, name: str) -> None:
        _n.check(_n.pz_audio_play(self._eng, name.encode("utf-8")) == 0)
