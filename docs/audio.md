# Audio

Pixzig plays sound effects, music and game-generated audio through miniaudio. Sounds and music are assets like textures: you load them into the resource manager under a name, and `eng.audio` plays them. Everything mixes through three buses: `sfx` and `music`, which both feed `master`.

## Turning It Off

Audio is on by default, as `eng.audio`. A game that doesn't want it can turn it off:

```zig
const AppRunner = pixzig.AppRunner(App, .{
    .audioOpts = .{ .enabled = false },
});
```

With audio off, `eng.audio` is a stub and calling its methods is a compile error that tells you which option to set. If a machine has no audio device, the engine logs a warning and carries on silently instead of failing to start.

## Loading Sounds and Music

```zig
// In init:
_ = try eng.resources.loadSound("shoot", "assets/laserShoot.wav");
_ = try eng.resources.loadSound("boom", "assets/explosion.wav");
_ = try eng.resources.loadMusic("theme", "assets/theme.wav");
```

A **sound** is decoded into memory when it loads, so it starts instantly. Use it for effects. A **music** track is streamed from disk as it plays, so a long track costs little memory.

Pixzig reads WAV, FLAC, MP3 and Ogg Vorbis. For music that loops, use Ogg or FLAC: both loop seamlessly. MP3 doesn't, because the decoder keeps the encoder's padding (about 100 ms), and you'll hear it as a gap each time the track wraps.

Both return a handle (`*SoundHandle`, `*MusicHandle`) and can be looked up later with `getSound(name)` and `getMusic(name)`. Paths resolve like every other asset (see [Assets](page:assets)), and a manifest can declare them with the `sound` and `music` kinds.

## Playing Sounds

```zig
if (eng.actions.pressed(.fire)) {
    _ = eng.audio.play("shoot", .{}) catch |err| std.log.warn("shoot: {}", .{err});
}
```

`play` takes options for one play:

| Option | Default | What it does |
|---|---|---|
| `volume` | `1.0` | Linear gain. |
| `pan` | `0.0` | -1 is full left, 1 full right. |
| `pitch` | `1.0` | Playback rate: 2.0 is an octave up and twice as fast. |
| `loop` | `false` | Repeat until stopped. |
| `fadeInMs` | `0` | Fade in from silence. |

A little random pan and pitch keeps rapid fire from sounding like one sample on repeat:

```zig
_ = try eng.audio.play("shoot", .{
    .pan = eng.rng.floatRange(-0.5, 0.5),
    .pitch = eng.rng.floatRange(0.9, 1.1),
});
```

`playHandle(handle, opts)` does the same with a handle instead of a name.

## Voices

Each play gets a voice, and `play` returns a `pixzig.Voice` handle to it. Hold on to it to control a sound that's still playing, like an engine hum:

```zig
self.hum = try eng.audio.play("engine", .{ .loop = true, .volume = 0.4 });

// Later:
eng.audio.setPitch(self.hum, 1.0 + speed / 200.0);
eng.audio.setVolume(self.hum, 0.6);
eng.audio.stop(self.hum, .{ .fadeOutMs = 300 });
```

There's also `setPan` and `isPlaying`, and `stopSound(name, opts)` stops every voice of one sound. A voice that's fading out still counts as playing until the fade ends, and asking it to fade out again in the meantime is ignored, so "if it's playing, fade it out" is safe to run every tick.

Playing a sound that's already playing starts another voice, so rapid gunfire overlaps instead of cutting itself off. Each sound can have up to `maxConcurrentSounds` voices at once (16 by default). Past that, the voice that has been playing longest restarts for the new play, so `play` always succeeds:

```zig
.audioOpts = .{ .maxConcurrentSounds = 4 },
```

A `Voice` goes stale once its voice is reused for another play, its sound is reloaded, or (for a stream) it ends. Calls with a stale handle do nothing, so it's safe to keep one around after the sound has finished. `isValid(voice)` tells you whether it still refers to anything.

## Music

One music track plays at a time:

```zig
try eng.audio.playMusic("theme", .{});                    // loops by default
try eng.audio.playMusic("boss", .{ .fadeMs = 1500 });     // crossfade from theme
eng.audio.stopMusic(.{ .fadeOutMs = 2000 });
```

`playMusic` takes `loop` (default `true`), `volume`, and `fadeMs`. With `fadeMs` set, a track that's already playing fades out over that time while the new one fades in. Asking for the track that's already playing doesn't restart it, so it's safe to call `playMusic` every time a level loads.

`pauseMusic` and `resumeMusic` keep the track's position. `musicPlaying()` tells you whether it's audible, and `currentMusic()` returns the current track's handle, or null when there isn't one.

## Buses and Pausing

`setBusVolume` sets a bus's volume, which is what a settings menu wants:

```zig
eng.audio.setBusVolume(.music, settings.musicVolume);
eng.audio.setBusVolume(.sfx, settings.effectsVolume);
eng.audio.setBusVolume(.master, settings.masterVolume);
```

`busVolume(bus)` reads it back.

`pauseAll` pauses every voice, stream and the music that's playing right then, keeping their positions. Sounds played after it still play, so a pause menu's own clicks work. `resumeAll` resumes what it paused.

The engine calls both itself when the app goes to the background and comes back (the `will_enter_background` and `did_enter_foreground` events). `resumeAll` doesn't know who paused what, so coming back also resumes audio a pause menu had paused. A game that keeps its pause menu up across that should call `pauseAll` again from `onEvent` on `.did_enter_foreground`, which runs after the engine's resume. See [The Game Loop](page:app-runner).

## Generated Audio

`playStream` plays audio your code generates: a tracker module player, a synth, procedural effects. You give it a callback that fills a buffer of interleaved `f32` samples and returns how many frames it wrote:

```zig
const Tone = struct {
    phase: f32 = 0,
    step: f32,

    fn fill(ctx: ?*anyopaque, out: []f32, channels: u32) usize {
        const self: *Tone = @ptrCast(@alignCast(ctx.?));
        const frames = out.len / channels;
        for (0..frames) |i| {
            const s = @sin(self.phase * std.math.tau) * 0.1;
            self.phase = @mod(self.phase + self.step, 1.0);
            for (0..channels) |c| out[i * channels + c] = s;
        }
        return frames;
    }
};

self.tone = .{ .step = 440.0 / @as(f32, @floatFromInt(eng.audio.sampleRate())) };
self.voice = try eng.audio.playStream(Tone.fill, &self.tone, .{ .channels = 1 });
```

`StreamOpts` sets `channels` (2), `sampleRate` (0 means the engine's own rate; anything else is resampled), `volume`, and the `bus` it plays through (`sfx`). Returning fewer frames than asked ends the stream once they've played; `stop` with the returned voice ends it early. Either way the engine frees it on the next frame.

The callback runs on miniaudio's audio thread, not the game thread. It must not block, and anything it shares with game code needs atomics or another lock-free handoff. The context pointer has to outlive the stream.

## Hot Reload

In a debug build, sound and music files are watched like other assets. When one changes, it reloads in place: a sound's playing voices stop and the next `play` uses the new file. Music that was the current track restarts with the new file. If the new file doesn't load, the old music keeps playing, but a sound has nothing to play until the file is fixed, because its old samples have to be freed before the new file loads.

## From Lua

When both scripting and audio are on, the engine registers these Lua functions:

| Function | What it does |
|---|---|
| `audio_play(name [, volume [, pan [, pitch]]])` | Plays a sound. |
| `audio_stop(name [, fade_ms])` | Stops every voice of a sound. |
| `audio_set_volume(bus, volume)` | `bus` is `"master"`, `"sfx"` or `"music"`. |
| `audio_pause_all()`, `audio_resume_all()` | Pause and resume everything. |
| `music_play(name [, fade_ms [, loop]])` | Plays music. |
| `music_stop([fade_ms])`, `music_pause()`, `music_resume()` | Control the current track. |

An unknown name logs a warning instead of raising a Lua error. For a `ScriptEngine` of your own, call `eng.audio.bindToLua(&scripts)`.

## Testing Without a Device

`.audioOpts = .{ .noDevice = true }` mixes without opening an audio device. Nothing is heard, and audio time only moves when you call `eng.audio.renderFrames(buf, frames)`, so fades and streams run on your schedule. Pixzig's own audio tests work this way.

`examples/audio_ex.zig` plays sounds with random pan and pitch, crossfades music, changes the music volume, pauses everything, and runs a small synth stream.
