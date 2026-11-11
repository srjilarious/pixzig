# pixzig.paths

Module `pixzig.paths`. Generated from its docstrings by `tools/gen_py_docs.py`.

How the Python bindings resolve asset paths.

Every relative path handed to a loader (textures, tile maps, fonts, sounds,
animation files, the manifest) resolves against the directory holding the
main script, not the current working directory, so a game runs the same
from wherever it's launched:

```sh
python examples/hello_pixzig.py        # from the repo root
cd examples && python hello_pixzig.py  # same assets either way
```

The engine resolves its own relative paths against the executable's
directory, which under Python is wherever the interpreter is installed, so
the bindings turn paths absolute before handing them over. Absolute paths
pass through untouched.

Pass `asset_root=` to [`App`](page:python-api/app#h2-app), or assign [`app.asset_root`](page:python-api/app#h3-app-asset-root), to point somewhere
else: a packaged install, a mod directory, a path from a config file.

## `AssetPaths`

```python
AssetPaths(root: str = None)
```

Resolves relative asset paths against a root directory.

Each [`App`](page:python-api/app#h2-app) makes one, shared by everything that loads files ([`Audio`](page:python-api/audio#h2-audio),
[`Text`](page:python-api/text#h2-text) and the loaders on [`App`](page:python-api/app#h2-app)), so changing [`app.asset_root`](page:python-api/app#h3-app-asset-root) affects
every later load.

| Argument | Type | Default | Description |
|---|---|---|---|
| `root` | `str` | `None` | The base directory. None uses `main_script_dir()`. |

### `AssetPaths.root`

```python
root: str  # property
```

The base directory, always absolute.

Assigning a relative path makes it absolute against the current directory
at that moment.

### `AssetPaths.resolve`

```python
resolve(path: str) -> str
```

Makes a path absolute.

| Argument | Type | Description |
|---|---|---|
| `path` | `str` | A path relative to [`root`](page:python-api/paths#h3-assetpaths-root), or an absolute one. |

**Returns:** The absolute path. Absolute paths come back unchanged.

### `AssetPaths.encode`

```python
encode(path: str) -> bytes
```

Resolves a path and encodes it as UTF-8 for the engine.

| Argument | Type | Description |
|---|---|---|
| `path` | `str` | A path relative to [`root`](page:python-api/paths#h3-assetpaths-root), or an absolute one. |

**Returns:** The absolute path as bytes.

**Raises:**

- `FileNotFoundError`: The file doesn't exist. The message names the resolved path and, for a relative one, the asset root.

## `main_script_dir`

```python
main_script_dir() -> str
```

The directory holding the `__main__` script.

**Returns:** The script's directory, or the current directory when there isn't a
script (an interactive session, `python -c`, some frozen builds).
