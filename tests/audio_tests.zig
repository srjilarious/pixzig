const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");

const audio = pixzig.audio;
const AudioEngine = audio.AudioEngine;
const ResourceManager = pixzig.ResourceManager;

/// A resource manager plus a device-less audio engine attached to it.
/// Nothing is heard, and audio time only moves when `pump` pulls frames.
const Fixture = struct {
    res: ResourceManager,
    eng: AudioEngine,

    fn init(self: *Fixture, alloc: std.mem.Allocator, opts: audio.AudioOptions) !void {
        var o = opts;
        o.noDevice = true;
        self.res = ResourceManager.init(alloc);
        errdefer self.res.deinit();
        self.eng = try AudioEngine.init(alloc, o, &self.res);
    }

    fn deinit(self: *Fixture) void {
        self.eng.deinit();
        self.res.deinit();
    }

    /// Mixes `ms` milliseconds of audio, advancing the engine clock.
    fn pump(self: *Fixture, ms: u32) !void {
        var buf: [2 * 480]f32 = undefined;
        var left: u64 = @as(u64, ms) * self.eng.sampleRate() / 1000;
        while (left > 0) {
            const n = @min(left, 480);
            try self.eng.renderFrames(&buf, n);
            left -= n;
        }
    }
};

/// Writes a mono 16-bit 48 kHz WAV of `frames` frames of a quiet square
/// wave to `.zig-cache/pixzig_audio_tests/<name>` and returns its absolute
/// path (caller frees).
fn writeWav(io: std.Io, alloc: std.mem.Allocator, name: []const u8, frames: u32) ![]u8 {
    const cwd = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", alloc);
    defer alloc.free(cwd);
    const dir = try std.fs.path.join(alloc, &.{ cwd, ".zig-cache", "pixzig_audio_tests" });
    defer alloc.free(dir);
    try std.Io.Dir.cwd().createDirPath(io, dir);
    const path = try std.fs.path.join(alloc, &.{ dir, name });
    errdefer alloc.free(path);

    var data: std.ArrayList(u8) = .empty;
    defer data.deinit(alloc);
    const dataBytes = frames * 2;
    try data.appendSlice(alloc, "RIFF");
    try data.appendSlice(alloc, &std.mem.toBytes(std.mem.nativeToLittle(u32, 36 + dataBytes)));
    try data.appendSlice(alloc, "WAVEfmt ");
    const fmt = [_]u32{ 16, 0x0001_0001, 48000, 96000, 0x0010_0002 };
    for (fmt) |v| try data.appendSlice(alloc, &std.mem.toBytes(std.mem.nativeToLittle(u32, v)));
    try data.appendSlice(alloc, "data");
    try data.appendSlice(alloc, &std.mem.toBytes(std.mem.nativeToLittle(u32, dataBytes)));
    for (0..frames) |i| {
        const s: i16 = if ((i / 50) % 2 == 0) 1000 else -1000;
        try data.appendSlice(alloc, &std.mem.toBytes(std.mem.nativeToLittle(i16, s)));
    }

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data.items });
    return path;
}

// --- Sounds ---

pub fn playReturnsAPlayingVoiceTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    _ = try f.res.loadSound("laser", "assets/laserShoot.wav");
    const v = try f.eng.play("laser", .{ .volume = 0.5, .pan = -0.5, .pitch = 1.2 });
    try testz.expectTrue(f.eng.isValid(v));
    try testz.expectTrue(f.eng.isPlaying(v));

    f.eng.stop(v, .{});
    try testz.expectFalse(f.eng.isPlaying(v));
}

pub fn unknownNamesErrorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    try testz.expectError(f.eng.play("nope", .{}), error.NoSoundWithThatName);
    try testz.expectError(f.eng.playMusic("nope", .{}), error.NoMusicWithThatName);
    try testz.expectError(f.res.loadSound("missing", "assets/does_not_exist.wav"), error.DoesNotExist);
}

pub fn loadWithoutAudioIsAnErrorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var res = ResourceManager.init(alloc);
    defer res.deinit();
    try testz.expectError(res.loadSound("laser", "assets/laserShoot.wav"), error.AudioDisabled);
    try testz.expectError(res.loadMusic("theme", "assets/music_loop.ogg"), error.AudioDisabled);
}

pub fn fullPoolStealsOldestVoiceTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{ .maxConcurrentSounds = 2 });
    defer f.deinit();

    const h = try f.res.loadSound("laser", "assets/laserShoot.wav");
    const first = try f.eng.play("laser", .{});
    const second = try f.eng.play("laser", .{});
    try testz.expectEqual(h.val.voices.items.len, 2);

    // Both voices busy: the third play takes the first (oldest) voice.
    const third = try f.eng.play("laser", .{});
    try testz.expectEqual(h.val.voices.items.len, 2);
    try testz.expectEqual(third.index, first.index);
    try testz.expectFalse(f.eng.isValid(first));
    try testz.expectTrue(f.eng.isPlaying(second));
    try testz.expectTrue(f.eng.isPlaying(third));

    // Stopping a stale handle must not touch the voice that replaced it.
    f.eng.stop(first, .{});
    try testz.expectTrue(f.eng.isPlaying(third));
}

pub fn finishedVoiceIsReusedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    const h = try f.res.loadSound("laser", "assets/laserShoot.wav");
    const a = try f.eng.play("laser", .{});
    f.eng.stop(a, .{});
    const b = try f.eng.play("laser", .{});
    try testz.expectEqual(h.val.voices.items.len, 1);
    try testz.expectEqual(b.index, a.index);
    try testz.expectFalse(f.eng.isValid(a));
}

pub fn fadeOutStopsAfterTheFadeAndReplayIsAudibleTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    _ = try f.res.loadSound("laser", "assets/laserShoot.wav");
    const v = try f.eng.play("laser", .{ .loop = true });
    f.eng.stop(v, .{ .fadeOutMs = 50 });
    try testz.expectTrue(f.eng.isPlaying(v));
    try f.pump(80);
    try testz.expectFalse(f.eng.isPlaying(v));

    // The fade leaves a scheduled stop and a zero fader behind; a new play
    // on the same voice must clear both.
    const again = try f.eng.play("laser", .{ .loop = true });
    try testz.expectEqual(again.index, v.index);
    try f.pump(20);
    try testz.expectTrue(f.eng.isPlaying(again));
}

pub fn repeatedFadeOutDoesNotPostponeTheStopTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    _ = try f.res.loadSound("laser", "assets/laserShoot.wav");
    const v = try f.eng.play("laser", .{ .loop = true });

    // Polling "if playing, fade out" every tick must still let it end.
    for (0..10) |_| {
        if (f.eng.isPlaying(v)) f.eng.stop(v, .{ .fadeOutMs = 50 });
        try f.pump(10);
    }
    try testz.expectFalse(f.eng.isPlaying(v));
}

pub fn reloadReplacesVoicesAndReadsTheNewFileTest(io: std.Io, alloc: std.mem.Allocator) !void {
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    const path = try writeWav(io, alloc, "reload.wav", 4800);
    defer alloc.free(path);

    const h = try f.res.loadSound("blip", path);
    const v = try f.eng.play("blip", .{});
    try testz.expectEqual(try h.val.template.?.getLengthInPcmFrames(), 4800);

    // Same path, new contents. miniaudio caches decoded data by path while
    // any copy (voice) is alive, so this only sees the new length if the
    // reload tore every voice down first.
    const path2 = try writeWav(io, alloc, "reload.wav", 9600);
    defer alloc.free(path2);
    const h2 = try f.res.loadSound("blip", path);

    try testz.expectTrue(h2 == h);
    try testz.expectEqual(h.version, 1);
    try testz.expectEqual(try h.val.template.?.getLengthInPcmFrames(), 9600);
    try testz.expectEqual(h.val.voices.items.len, 0);
    try testz.expectFalse(f.eng.isValid(v));
    try testz.expectFalse(f.eng.isPlaying(v));

    const v2 = try f.eng.play("blip", .{});
    try testz.expectTrue(f.eng.isPlaying(v2));
}

pub fn failedReloadLeavesSoundEmptyTest(io: std.Io, alloc: std.mem.Allocator) !void {
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    const path = try writeWav(io, alloc, "broken.wav", 4800);
    defer alloc.free(path);
    const h = try f.res.loadSound("blip", path);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "not a wav file" });
    if (f.res.loadSound("blip", path)) |_| {
        return error.ExpectedLoadFailure;
    } else |_| {}

    try testz.expectTrue(h.val.template == null);
    try testz.expectError(f.eng.play("blip", .{}), error.SoundNotLoaded);
}

pub fn deinitFreesSoundsButKeepsHandlesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var res = ResourceManager.init(alloc);
    defer res.deinit();
    var eng = try AudioEngine.init(alloc, .{ .noDevice = true }, &res);

    const h = try res.loadSound("laser", "assets/laserShoot.wav");
    _ = try eng.play("laser", .{});
    eng.deinit();

    // The slot outlives the audio engine, empty.
    try testz.expectTrue(h.val.template == null);
    try testz.expectEqual(h.val.voices.items.len, 0);
    try testz.expectTrue(res.audio == null);
}

// --- Music ---

pub fn musicPlaysAndCrossfadesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    const otherPath = try writeWav(io, alloc, "other_track.wav", 48000);
    defer alloc.free(otherPath);

    const theme = try f.res.loadMusic("theme", "assets/music_loop.ogg");
    const other = try f.res.loadMusic("other", otherPath);

    try f.eng.playMusic("theme", .{});
    try testz.expectTrue(f.eng.musicPlaying());
    try testz.expectTrue(f.eng.currentMusic().? == theme);

    // Playing the current track again doesn't restart it.
    try f.pump(30);
    const cursor = try theme.val.snd.?.getCursorInPcmFrames();
    try f.eng.playMusic("theme", .{ .volume = 0.5 });
    try testz.expectTrue(try theme.val.snd.?.getCursorInPcmFrames() >= cursor);

    try f.eng.playMusic("other", .{ .fadeMs = 50 });
    try testz.expectTrue(f.eng.currentMusic().? == other);
    try testz.expectTrue(theme.val.snd.?.isPlaying()); // still fading out
    try f.pump(80);
    try testz.expectFalse(theme.val.snd.?.isPlaying());
    try testz.expectTrue(f.eng.musicPlaying());

    f.eng.stopMusic(.{ .fadeOutMs = 20 });
    try testz.expectTrue(f.eng.currentMusic() == null);
    try f.pump(40);
    try testz.expectFalse(other.val.snd.?.isPlaying());
}

pub fn oggMusicLoopsPastItsEndTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    // stb_vorbis runs in push mode, so the stream's length is unknown and
    // looping relies on seeking back at the end. The track is 8 s long.
    _ = try f.res.loadMusic("theme", "assets/music_loop.ogg");
    try f.eng.playMusic("theme", .{ .loop = true });
    try f.pump(9000);
    try testz.expectTrue(f.eng.musicPlaying());

    try f.eng.playMusic("theme", .{ .loop = false });
    try f.pump(8000);
    try testz.expectFalse(f.eng.musicPlaying());
}

pub fn oggDecodesWithoutPaddingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    // Exactly 8 s at the engine's 48 kHz: no encoder delay or padding
    // that would put a gap in the loop (MP3 through dr_mp3 adds ~100 ms).
    const h = try f.res.loadSound("theme", "assets/music_loop.ogg");
    try testz.expectEqual(try h.val.template.?.getLengthInPcmFrames(), 8 * 48000);
}

pub fn musicPauseResumeKeepsPositionTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    const theme = try f.res.loadMusic("theme", "assets/music_loop.ogg");
    try f.eng.playMusic("theme", .{});
    try f.pump(50);

    f.eng.pauseMusic();
    try testz.expectFalse(f.eng.musicPlaying());
    const cursor = try theme.val.snd.?.getCursorInPcmFrames();
    try f.pump(50);
    try testz.expectEqual(try theme.val.snd.?.getCursorInPcmFrames(), cursor);

    f.eng.resumeMusic();
    try testz.expectTrue(f.eng.musicPlaying());
}

pub fn musicReloadRestartsTheCurrentTrackTest(io: std.Io, alloc: std.mem.Allocator) !void {
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    const path = try writeWav(io, alloc, "track.wav", 48000);
    defer alloc.free(path);
    const track = try f.res.loadMusic("track", path);
    try f.eng.playMusic("track", .{});

    _ = try f.res.loadMusic("track", path);
    try testz.expectEqual(track.version, 1);
    try testz.expectFalse(track.val.snd.?.isPlaying());

    f.eng.update();
    try testz.expectTrue(f.eng.musicPlaying());
}

// --- Streams ---

const Counter = struct {
    frames: std.atomic.Value(u64) = .init(0),
    limit: u64,

    fn fill(ctx: ?*anyopaque, out: []f32, channels: u32) usize {
        const self: *Counter = @ptrCast(@alignCast(ctx.?));
        const done = self.frames.load(.monotonic);
        const want = out.len / channels;
        const n: usize = @intCast(@min(want, self.limit -| done));
        @memset(out[0 .. n * channels], 0.0);
        self.frames.store(done + n, .monotonic);
        return n;
    }
};

pub fn streamPullsFramesAndIsFreedWhenItEndsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    var counter = Counter{ .limit = 2400 };
    const v = try f.eng.playStream(Counter.fill, &counter, .{ .channels = 1 });
    try testz.expectTrue(f.eng.isPlaying(v));

    try f.pump(100);
    try testz.expectEqual(counter.frames.load(.monotonic), 2400);
    try testz.expectFalse(f.eng.isPlaying(v));

    try testz.expectTrue(f.eng.isValid(v));
    f.eng.update();
    try testz.expectFalse(f.eng.isValid(v));
    try testz.expectEqual(f.eng.streams.items.len, 0);
}

pub fn stoppedStreamIsFreedTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    var counter = Counter{ .limit = std.math.maxInt(u64) };
    const v = try f.eng.playStream(Counter.fill, &counter, .{ .bus = .music });
    try f.pump(10);
    try testz.expectTrue(counter.frames.load(.monotonic) > 0);

    f.eng.stop(v, .{});
    f.eng.update();
    try testz.expectFalse(f.eng.isValid(v));
}

// --- Buses and pausing ---

pub fn busVolumesRoundTripTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    try testz.expectEqual(f.eng.busVolume(.music), 1.0);
    f.eng.setBusVolume(.music, 0.25);
    f.eng.setBusVolume(.master, 0.5);
    try testz.expectEqual(f.eng.busVolume(.music), 0.25);
    try testz.expectEqual(f.eng.busVolume(.master), 0.5);
    try testz.expectEqual(f.eng.music.getVolume(), 0.25);
}

pub fn pauseAllPausesOnlyWhatWasPlayingTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    _ = try f.res.loadSound("laser", "assets/laserShoot.wav");
    _ = try f.res.loadSound("boom", "assets/explosion.wav");
    _ = try f.res.loadMusic("theme", "assets/music_loop.ogg");

    const laser = try f.eng.play("laser", .{ .loop = true });
    try f.eng.playMusic("theme", .{});
    var counter = Counter{ .limit = std.math.maxInt(u64) };
    const stream = try f.eng.playStream(Counter.fill, &counter, .{});

    f.eng.pauseAll();
    try testz.expectFalse(f.eng.isPlaying(laser));
    try testz.expectFalse(f.eng.isPlaying(stream));
    try testz.expectFalse(f.eng.musicPlaying());

    // A paused stream isn't mistaken for a finished one.
    f.eng.update();
    try testz.expectTrue(f.eng.isValid(stream));

    // Sounds started while paused play, and a new play of a sound with a
    // paused voice doesn't take that voice.
    const click = try f.eng.play("boom", .{});
    try testz.expectTrue(f.eng.isPlaying(click));
    const laser2 = try f.eng.play("laser", .{});
    try testz.expectFalse(laser2.index == laser.index);

    f.eng.resumeAll();
    try testz.expectTrue(f.eng.isPlaying(laser));
    try testz.expectTrue(f.eng.isPlaying(stream));
    try testz.expectTrue(f.eng.musicPlaying());
}

// --- Manifest and Lua ---

pub fn manifestLoadsSoundAndMusicKindsTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    const json =
        \\{
        \\  "groups": { "boot": ["laser", "theme"] },
        \\  "assets": [
        \\    { "id": "laser", "kind": "sound", "path": "assets/laserShoot.wav" },
        \\    { "id": "theme", "kind": "music", "path": "assets/music_loop.ogg" }
        \\  ]
        \\}
    ;
    var manifest = try pixzig.AssetManifest.loadFromJson(alloc, &f.res, json, ".");
    defer manifest.deinit();

    _ = try f.res.getSound("laser");
    _ = try f.res.getMusic("theme");
}

pub fn manifestSkipsAudioKindsWithAudioOffTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var res = ResourceManager.init(alloc);
    defer res.deinit();

    const json =
        \\{
        \\  "groups": { "boot": ["laser"] },
        \\  "assets": [ { "id": "laser", "kind": "sound", "path": "assets/laserShoot.wav" } ]
        \\}
    ;
    var manifest = try pixzig.AssetManifest.loadFromJson(alloc, &res, json, ".");
    defer manifest.deinit();
    try testz.expectError(res.getSound("laser"), error.NoSoundWithThatName);
}

pub fn luaBindingsDriveTheEngineTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    var f: Fixture = undefined;
    try f.init(alloc, .{});
    defer f.deinit();

    var script = try pixzig.ScriptEngine.init(alloc);
    defer script.deinit();
    try f.eng.bindToLua(&script);

    const laser = try f.res.loadSound("laser", "assets/laserShoot.wav");
    _ = try f.res.loadMusic("theme", "assets/music_loop.ogg");

    try script.run("audio_play('laser', 0.5, 0.2, 1.1)");
    try testz.expectEqual(laser.val.voices.items.len, 1);
    try testz.expectTrue(laser.val.voices.items[0].snd.isPlaying());

    try script.run("music_play('theme', 0, true)");
    try testz.expectTrue(f.eng.musicPlaying());
    try script.run("music_pause()");
    try testz.expectFalse(f.eng.musicPlaying());
    try script.run("music_resume()");
    try testz.expectTrue(f.eng.musicPlaying());

    try script.run("audio_set_volume('sfx', 0.3)");
    try testz.expectEqual(f.eng.busVolume(.sfx), 0.3);

    try script.run("audio_stop('laser')");
    try testz.expectFalse(laser.val.voices.items[0].snd.isPlaying());

    try script.run("music_stop()");
    try testz.expectFalse(f.eng.musicPlaying());

    // Unknown names warn instead of raising.
    try script.run("audio_play('nope'); music_play('nope'); audio_set_volume('nope', 1)");
}
