"""Asset path resolution for the Python bindings.

Every relative path handed to a loader -- textures, tilemaps, fonts, sounds,
animation files, the manifest -- is resolved against **the directory holding
the main script**, not the process's current working directory. That way a
game runs the same whichever directory it was launched from:

    python examples/hello_pixzig.py        # from the repo root
    cd examples && python hello_pixzig.py  # same assets either way

The Zig side resolves its own relative paths against the executable's
directory (`pixzig.paths`), which under Python is wherever the interpreter
happens to be installed. So the bindings resolve to an absolute path before
crossing the FFI; absolute paths pass through both layers untouched.

Pass `asset_root=` to `App` (or assign `app.asset_root`) to point somewhere
else -- a packaged install, a mod directory, a path read from a config file.
"""
import os
import sys


def main_script_dir() -> str:
    """The directory holding the `__main__` script, or the cwd when there
    isn't one (an interactive session, `python -c`, some frozen builds)."""
    main = sys.modules.get("__main__")
    script = getattr(main, "__file__", None)
    if script:
        return os.path.dirname(os.path.abspath(script))
    return os.getcwd()


class AssetPaths:
    """Resolves relative asset paths against `root`.

    One of these is created per `App`; the subsystems that load files
    (`Audio`, `Text`, and the loaders on `App` itself) share it, so changing
    `app.asset_root` affects every later load.
    """

    def __init__(self, root: str = None):
        self.root = root if root is not None else main_script_dir()

    @property
    def root(self) -> str:
        """The base directory, always absolute; assigning a relative path
        absolutizes it against the cwd at that moment."""
        return self._root

    @root.setter
    def root(self, value: str) -> None:
        self._root = os.path.abspath(value)

    def resolve(self, path: str) -> str:
        """Returns `path` as an absolute path, relative paths taken from
        `root`. Already-absolute paths are returned unchanged."""
        if os.path.isabs(path):
            return path
        return os.path.normpath(os.path.join(self.root, path))

    def encode(self, path: str) -> bytes:
        """`resolve`, UTF-8 encoded for the FFI."""
        return self.resolve(path).encode("utf-8")
