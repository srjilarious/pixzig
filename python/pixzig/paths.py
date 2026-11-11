"""How the Python bindings resolve asset paths.

Every relative path handed to a loader (textures, tile maps, fonts, sounds,
animation files, the manifest) resolves against the directory holding the
main script, not the current working directory, so a game runs the same
from wherever it's launched:

    python examples/hello_pixzig.py        # from the repo root
    cd examples && python hello_pixzig.py  # same assets either way

The engine resolves its own relative paths against the executable's
directory, which under Python is wherever the interpreter is installed, so
the bindings turn paths absolute before handing them over. Absolute paths
pass through untouched.

Pass `asset_root=` to `App`, or assign `app.asset_root`, to point somewhere
else: a packaged install, a mod directory, a path from a config file.
"""
import os
import sys


def main_script_dir() -> str:
    """The directory holding the `__main__` script.

    Returns:
        The script's directory, or the current directory when there isn't a
        script (an interactive session, `python -c`, some frozen builds).
    """
    main = sys.modules.get("__main__")
    script = getattr(main, "__file__", None)
    if script:
        return os.path.dirname(os.path.abspath(script))
    return os.getcwd()


class AssetPaths:
    """Resolves relative asset paths against a root directory.

    Each `App` makes one, shared by everything that loads files (`Audio`,
    `Text` and the loaders on `App`), so changing `app.asset_root` affects
    every later load.

    Args:
        root: The base directory. None uses `main_script_dir()`.
    """

    def __init__(self, root: str = None):
        self.root = root if root is not None else main_script_dir()

    @property
    def root(self) -> str:
        """The base directory, always absolute.

        Assigning a relative path makes it absolute against the current directory
        at that moment.
        """
        return self._root

    @root.setter
    def root(self, value: str) -> None:
        self._root = os.path.abspath(value)

    def resolve(self, path: str) -> str:
        """Makes a path absolute.

        Args:
            path: A path relative to `root`, or an absolute one.

        Returns:
            The absolute path. Absolute paths come back unchanged.
        """
        if os.path.isabs(path):
            return path
        return os.path.normpath(os.path.join(self.root, path))

    def encode(self, path: str) -> bytes:
        """Resolves a path and encodes it as UTF-8 for the engine.

        Args:
            path: A path relative to `root`, or an absolute one.

        Returns:
            The absolute path as bytes.

        Raises:
            FileNotFoundError: The file doesn't exist. The message names the
                resolved path and, for a relative one, the asset root.
        """
        resolved = self.resolve(path)
        if not os.path.isfile(resolved):
            if os.path.isabs(path):
                message = f"asset not found: {resolved}"
            else:
                message = (
                    f"asset not found: '{path}' resolved to {resolved} "
                    f"(asset root is {self.root})"
                )
            raise FileNotFoundError(message)
        return resolved.encode("utf-8")
