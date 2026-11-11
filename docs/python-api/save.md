# pixzig.save

Module `pixzig.save`. Generated from its docstrings by `tools/gen_py_docs.py`.

Saves and settings, like [`pixzig.save`](page:python-api/save) on the Zig side, with JSON in place of ZON.

The game's own folder may be read-only once installed, so saves belong in the per-user directory `pref_path` finds. Writes go through a temporary file and a rename, so a crash mid-save leaves the previous save intact.

**Example:**

```python
from pixzig import save

path = os.path.join(save.pref_path("MyStudio", "MyGame"), "settings.json")
settings = save.load_json(path, default={"volume": 0.8})
...
save.save_json(path, settings)
```

## `pref_path`

```python
pref_path(org: str, app: str) -> str
```

The per-user directory for the game's saves and settings.

It's created if needed. Pick the names once and keep them, or players lose their saves.

| Argument | Type | Description |
|---|---|---|
| `org` | `str` | Your studio or name. |
| `app` | `str` | The game's name. |

**Returns:** The directory, ending in a path separator: `~/.local/share/<org>/<app>/` on Linux, `%APPDATA%\<org>\<app>\` on Windows, `~/Library/Application Support/<org>/<app>/` on macOS.

**Raises:**

- `pixzig.Error`: The directory couldn't be found or created.

## `write_file_atomic`

```python
write_file_atomic(path: str, data) -> None
```

Writes a file safely, creating parent directories.

The data goes to `<path>.tmp` first and is then renamed over `path`, so a crash partway through leaves the old file instead of half a new one.

| Argument | Type | Description |
|---|---|---|
| `path` | `str` | The file to write. |
| `data` |  | A `str` (written as UTF-8) or `bytes`. |

## `save_json`

```python
save_json(path: str, value) -> None
```

Writes a value as JSON, safely (see `write_file_atomic`).

| Argument | Type | Description |
|---|---|---|
| `path` | `str` | The file to write. |
| `value` |  | Anything `json.dumps` accepts. |

## `load_json`

```python
load_json(path: str, default=None)
```

Reads a JSON file.

| Argument | Type | Default | Description |
|---|---|---|---|
| `path` | `str` |  | The file to read. |
| `default` |  | `None` | What to return when the file doesn't exist, so a first run gets the defaults. |

**Returns:** The parsed value, or `default`.

**Raises:**

- `json.JSONDecodeError`: The file isn't valid JSON.
