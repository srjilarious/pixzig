# Saves and Settings

Asset paths resolve against the executable's directory (see [Assets](page:assets)), which may be read-only once a game is installed. Save games and settings belong in the per-user preference directory instead. `pixzig.save` finds it and reads and writes ZON files there.

## Where Saves Go

```zig
const dir = try pixzig.save.prefPath(alloc, "myname", "mygame");
defer alloc.free(dir);
```

`prefPath(alloc, org, app)` returns the directory, ending in a path separator, and creates it if it's missing. It comes from `SDL_GetPrefPath`:

| Platform | Directory |
|---|---|
| Linux | `~/.local/share/mygame/` |
| Windows | `%APPDATA%\myname\mygame\` |
| macOS | `~/Library/Application Support/mygame/` |

Pick the names once and don't change them, or players lose their saves.

## Saving and Loading a Struct

```zig
const Settings = struct {
    volume: f32 = 0.8,
    fullscreen: bool = false,
    name: []const u8 = "player",
};

const path = try std.fs.path.join(alloc, &.{ dir, "settings.zon" });
defer alloc.free(path);

try pixzig.save.saveZon(alloc, path, self.settings);

var arena: std.heap.ArenaAllocator = .init(alloc);
defer arena.deinit();
self.settings = pixzig.save.loadZon(Settings, arena.allocator(), path) catch |err| switch (err) {
    error.FileNotFound => .{}, // first run
    else => return err,
};
```

`saveZon` writes `<path>.tmp` and renames it over the real file, so a crash in the middle of a save leaves the previous one intact. It creates missing parent directories.

`loadZon` keeps a field's default when the file doesn't mention it and ignores fields it doesn't know, so you can add and remove settings without breaking older saves. Strings and slices in the result live in the arena you pass, so keep the arena as long as you use them. A malformed file logs where the error is and returns `error.ParseZon`.

For a save format of your own, `writeFileAtomic(alloc, path, bytes)` gives you the same tmp-and-rename write.
