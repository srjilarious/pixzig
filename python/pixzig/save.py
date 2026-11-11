"""Saves and settings, like `pixzig.save` on the Zig side, with JSON in place
of ZON.

The game's own folder may be read-only once installed, so saves belong in
the per-user directory `pref_path` finds. Writes go through a temporary
file and a rename, so a crash mid-save leaves the previous save intact.

Example:
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
    """The per-user directory for the game's saves and settings.

    It's created if needed. Pick the names once and keep them, or players lose
    their saves.

    Args:
        org: Your studio or name.
        app: The game's name.

    Returns:
        The directory, ending in a path separator:
        `~/.local/share/<org>/<app>/` on Linux, `%APPDATA%\\<org>\\<app>\\` on
        Windows, `~/Library/Application Support/<org>/<app>/` on macOS.

    Raises:
        pixzig.Error: The directory couldn't be found or created.
    """
    buf = ctypes.create_string_buffer(4096)
    n = _n.pz_pref_path(org.encode("utf-8"), app.encode("utf-8"), buf, len(buf))
    _n.check(n >= 0)
    return os.fsdecode(buf.raw[:n])


def write_file_atomic(path: str, data) -> None:
    """Writes a file safely, creating parent directories.

    The data goes to `<path>.tmp` first and is then renamed over `path`, so a
    crash partway through leaves the old file instead of half a new one.

    Args:
        path: The file to write.
        data: A `str` (written as UTF-8) or `bytes`.
    """
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
    """Writes a value as JSON, safely (see `write_file_atomic`).

    Args:
        path: The file to write.
        value: Anything `json.dumps` accepts.
    """
    write_file_atomic(path, json.dumps(value, indent=2) + "\n")


def load_json(path: str, default=None):
    """Reads a JSON file.

    Args:
        path: The file to read.
        default: What to return when the file doesn't exist, so a first run
            gets the defaults.

    Returns:
        The parsed value, or `default`.

    Raises:
        json.JSONDecodeError: The file isn't valid JSON.
    """
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default
