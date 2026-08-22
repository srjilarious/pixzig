"""Asset manifests. Load via `PixzigApp.load_manifest(path)`.

A manifest is a JSON file describing named assets (textures, atlases, fonts,
tilemaps) grouped into named groups, e.g.:

    {
      "root": "assets",
      "groups": { "boot": ["ui"], "level1": ["tiles", "level1_map"] },
      "assets": [
        { "id": "ui", "kind": "atlas", "path": "ui" },
        { "id": "tiles", "kind": "texture", "path": "mario_grassish2.png" },
        { "id": "level1_map", "kind": "tilemap", "path": "level1a.tmx" }
      ]
    }

A group named "boot" is loaded automatically as soon as the manifest is
opened. Loading a group registers its assets in the engine's resource
manager under their manifest id, so they're then usable directly by id with
`PixzigApp.load_sprite`, `PixzigApp.create_tilemap_renderer`, and
`Text.set_font` -- no separate step needed to "get" an asset out of the
manifest.
"""
from . import _native as _n


class AssetManifest:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.PixzigError("asset manifest already destroyed")

    def load_group(self, name: str) -> None:
        self._check_alive()
        _n.check(_n.pz_manifest_load_group(self._handle, name.encode("utf-8")) == 0)

    def unload_group(self, name: str) -> None:
        self._check_alive()
        _n.pz_manifest_unload_group(self._handle, name.encode("utf-8"))

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_manifest_destroy(self._handle)
            self._destroyed = True
