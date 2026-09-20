"""Sound playback. Access via `App.audio`.

Load a sound file once under a name, then play it by that name. Playing a
name that is already sounding spins up an extra concurrent voice, up to the
engine's per-sound cap.

    app.audio.load("jump", "assets/jump.wav")
    app.audio.play("jump")

A relative path is resolved against the app's asset root -- the directory of
the main script unless `App(..., asset_root=...)` says otherwise. See
`pixzig.paths`.
"""
from . import _native as _n


class Audio:
    def __init__(self, eng, paths):
        self._eng = eng
        self._paths = paths

    def load(self, name: str, path: str) -> None:
        _n.check(_n.pz_audio_load(self._eng, name.encode("utf-8"), self._paths.encode(path)) == 0)

    def play(self, name: str) -> None:
        _n.check(_n.pz_audio_play(self._eng, name.encode("utf-8")) == 0)
