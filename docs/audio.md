# Audio

Pixzig plays sound effects through miniaudio. It's a small API: load a sound under a name, then play it by name.

## Turning It On

Audio is off by default. Enable it in the engine options:

```zig
const AppRunner = pixzig.AppRunner(App, .{
    .audioOpts = .{ .enabled = true },
});
```

With audio off, `eng.audio` is a stub and calling its methods is a compile error that tells you which option to set.

## Playing Sounds

```zig
// In init:
try eng.audio.loadSound("shoot", "assets/laserShoot.wav");
try eng.audio.loadSound("boom", "assets/explosion.wav");

// In update:
if (eng.actions.pressed(.fire)) {
    eng.audio.playSound("shoot") catch |err| std.log.warn("shoot: {}", .{err});
}
```

Paths resolve like every other asset (see [Assets](page:assets)). miniaudio decodes WAV, FLAC and MP3.

Loading a name twice returns `error.SoundAlreadyExists`, and playing a name that was never loaded returns `error.SoundNotLoaded`.

## Overlapping Sounds

Playing a sound that's already playing starts another copy, so rapid gunfire overlaps instead of cutting itself off. Each sound can have up to `maxConcurrentSounds` copies playing at once (16 by default). Past that, `playSound` logs a warning and skips it.

```zig
.audioOpts = .{ .enabled = true, .maxConcurrentSounds = 4 },
```

## Going Further

The audio engine is a thin layer over [zaudio](https://github.com/zig-gamedev/zaudio), which pixzig re-exports as `pixzig.zaudio`. For music streaming, volume or positional sound, `eng.audio.engine` is the underlying `*zaudio.Engine`.

`examples/audio_ex.zig` plays a sound on a key press.
