"""Asset manifests: a game's assets listed in one JSON file, in groups.

Open one with `App.load_manifest(path)`. Loading a group registers its
assets in the engine under their manifest ids, so they're usable straight
away by id with `App.load_sprite`, `App.create_tilemap_renderer` and
`Text.set_font`. A group named `boot` loads as soon as the manifest opens.

The kinds are `texture`, `atlas`, `font` (with a `font_size`), `tilemap`,
`sound`, `music` and `raw` (a file the game reads itself).

Example:
    A manifest file:

        {
          "root": "assets",
          "groups": { "boot": ["ui"], "level1": ["tiles", "level1_map"] },
          "assets": [
            { "id": "ui", "kind": "atlas", "path": "ui" },
            { "id": "tiles", "kind": "texture", "path": "mario_grassish2.png" },
            { "id": "level1_map", "kind": "tilemap", "path": "level1a.tmx" }
          ]
        }
"""
from . import _native as _n


class AssetManifest:
    """An opened asset manifest. Create one with `App.load_manifest()`."""
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.Error("asset manifest already destroyed (or the app has shut down)")

    def load_group(self, name: str) -> None:
        """Loads every asset in a group.

        Loading a group that's already loaded does nothing.

        Args:
            name: The group's name.

        Raises:
            pixzig.Error: No group has that name, or one of its assets failed to load.
        """
        self._check_alive()
        _n.check(_n.pz_manifest_load_group(self._handle, name.encode("utf-8")) == 0)

    def unload_group(self, name: str) -> None:
        """Marks a group unloaded, so the next `load_group` reads its files again.

        Nothing is freed: assets stay loaded until the app shuts down, so sprites
        and renderers using them keep working, and reloading refreshes them in place.

        Args:
            name: The group's name.
        """
        self._check_alive()
        _n.pz_manifest_unload_group(self._handle, name.encode("utf-8"))

    def destroy(self) -> None:
        """Closes the manifest now instead of when the app shuts down.

        The assets it loaded stay loaded. Calling it twice does nothing.
        """
        if not self._destroyed:
            _n.pz_manifest_destroy(self._handle)
            self._destroyed = True
