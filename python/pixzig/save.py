"""Saves and settings, like `pixzig.save` on the Zig side, with JSON in
place of ZON.

    from pixzig import save

    path = os.path.join(save.pref_path("MyStudio", "MyGame"), "settings.json")
    settings = save.load_json(path, default={"volume": 0.8})
    ...
    save.save_json(path, settings)
"""
import ctypes
import json
import os

from . import _native as _n


def pref_path(org: str, app: str) -> str:
    """The per-user directory for the game's saves and settings, created if
    needed and ending in a path separator: `~/.local/share/<app>/` on
    Linux, `%APPDATA%\\<org>\\<app>\\` on Windows. `org` and `app` should
    stay the same for the life of the game, or old saves won't be found."""
    buf = ctypes.create_string_buffer(4096)
    n = _n.pz_pref_path(org.encode("utf-8"), app.encode("utf-8"), buf, len(buf))
    _n.check(n >= 0)
    return os.fsdecode(buf.raw[:n])


def write_file_atomic(path: str, data) -> None:
    """Writes `data` (str or bytes) to `path`, creating parent directories.
    It goes to `<path>.tmp` first and is then renamed over `path`, so a
    crash partway through leaves the old file instead of half a new one."""
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    tmp = path + ".tmp"
    mode = "wb" if isinstance(data, (bytes, bytearray)) else "w"
    with open(tmp, mode, **({} if mode == "wb" else {"encoding": "utf-8"})) as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def save_json(path: str, value) -> None:
    """Writes `value` to `path` as JSON, atomically (see `write_file_atomic`)."""
    write_file_atomic(path, json.dumps(value, indent=2) + "\n")


def load_json(path: str, default=None):
    """Reads JSON from `path`. A missing file returns `default`, so a first
    run gets the defaults. A file that isn't valid JSON raises."""
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default
