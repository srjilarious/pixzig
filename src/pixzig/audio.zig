//! Audio for pixzig, built on zaudio (miniaudio).
//!
//! Sounds and music are `ResourceManager` resources: `loadSound` /
//! `loadMusic` (or the `sound` / `music` manifest kinds) put them in named
//! slots that hot reload in place like textures do. `AudioEngine` plays
//! them: sound effects through pooled voices, one music track at a time
//! (streamed from disk, with crossfades), and game-generated PCM through
//! `playStream`. Everything mixes through three buses: `sfx` and `music`
//! feed `master`.
const std = @import("std");
const io = @import("./io.zig");
const zaudio = @import("zaudio");
const ziglua = @import("ziglua");
const resources = @import("./resources.zig");
const scripting = @import("./scripting.zig");

const ResourceManager = resources.ResourceManager;
const SoundHandle = resources.SoundHandle;
const MusicHandle = resources.MusicHandle;
const ScriptEngine = scripting.ScriptEngine;
const Lua = ziglua.Lua;

/// The default maximum number of voices one sound can play at once.
pub const DefaultMaxConcurrentSounds = 16;

/// Audio engine options for pixzig.
pub const AudioOptions = struct {
    /// Whether the engine creates an `AudioEngine` at all. When false,
    /// `Engine.audio` is a `DisabledAudioEngine` and using it is a compile
    /// error.
    enabled: bool = true,
    /// Voices one sound can play at once. Playing a sound with every voice
    /// busy restarts the one that has been playing longest.
    maxConcurrentSounds: u8 = DefaultMaxConcurrentSounds,
    /// Mix without an output device. Nothing is heard and time only moves
    /// when `AudioEngine.renderFrames` pulls frames, which is what tests
    /// and headless runs want. The engine also falls back to this, with a
    /// warning, when no audio device can be opened.
    noDevice: bool = false,
};

/// A mixing bus. `sfx` (sound effects and, by default, streams) and
/// `music` both feed `master`, the overall output volume.
pub const Bus = enum { master, sfx, music };

/// What `ResourceManager` needs to create sounds: the miniaudio engine and
/// the bus groups they attach to. `AudioEngine.init` hands it over with
/// `ResourceManager.attachAudio`.
pub const Backend = struct {
    engine: *zaudio.Engine,
    sfx: *zaudio.SoundGroup,
    music: *zaudio.SoundGroup,
};

/// Flags shared by everything pixzig creates: 2D games pan instead of
/// using miniaudio's 3D spatializer, so it's off.
const BaseFlags = zaudio.Sound.Flags{ .no_spatialization = true };

/// A loaded sound effect: a decoded template plus the voices playing it.
/// Lives in a `SoundHandle` slot owned by `ResourceManager`.
///
/// Voices are copies of the template, so they share its decoded samples.
/// miniaudio caches those samples by file path for as long as any copy is
/// alive, so a reload has to destroy every voice *and* the template before
/// loading the file again, or it would get the old samples back.
/// `ResourceManager` does that through `deinit`.
pub const Sound = struct {
    /// Never played itself; it holds the decoded data the voices share.
    /// Null when a hot reload freed the old sound but couldn't load the
    /// new file; playing it is then an error until the next good reload.
    template: ?*zaudio.Sound,
    voices: std.ArrayList(VoiceSlot) = .empty,
    alloc: std.mem.Allocator,

    /// A sound with nothing loaded.
    pub fn empty(alloc: std.mem.Allocator) Sound {
        return .{ .template = null, .alloc = alloc };
    }

    /// Decodes the file at `pathZ` (already resolved) into a new template.
    pub fn load(alloc: std.mem.Allocator, backend: Backend, pathZ: [:0]const u8) !Sound {
        var flags = BaseFlags;
        flags.decode = true;
        flags.no_default_attachment = true;
        const template = try backend.engine.createSoundFromFile(pathZ, .{ .flags = flags });
        return .{ .template = template, .alloc = alloc };
    }

    /// Destroys every voice, then the template.
    pub fn deinit(self: *Sound) void {
        for (self.voices.items) |v| v.snd.destroy();
        self.voices.deinit(self.alloc);
        if (self.template) |t| t.destroy();
        self.template = null;
    }
};

/// One playing copy of a `Sound`.
const VoiceSlot = struct {
    snd: *zaudio.Sound,
    /// Matches `Voice.gen` while that handle owns this slot. Every play
    /// gives the slot a new one, so a handle to a stolen or reloaded voice
    /// stops working instead of controlling someone else's sound.
    gen: u32,
    /// Play order, so the voice playing longest is the one stolen.
    startSeq: u64,
    /// Stopped by `pauseAll`, to be restarted by `resumeAll`.
    paused: bool = false,
    /// See `stopWithOpts`.
    fadingOut: bool = false,
};

/// A loaded music track, streamed from disk as it plays. Lives in a
/// `MusicHandle` slot owned by `ResourceManager`.
pub const Music = struct {
    /// Null when a hot reload couldn't load the new file.
    snd: ?*zaudio.Sound,
    /// See `stopWithOpts`.
    fadingOut: bool = false,

    pub fn empty() Music {
        return .{ .snd = null };
    }

    /// Opens the file at `pathZ` (already resolved) for streaming on the
    /// music bus.
    pub fn load(backend: Backend, pathZ: [:0]const u8) !Music {
        var flags = BaseFlags;
        flags.stream = true;
        const snd = try backend.engine.createSoundFromFile(pathZ, .{ .flags = flags, .sgroup = backend.music });
        return .{ .snd = snd };
    }

    pub fn deinit(self: *Music) void {
        if (self.snd) |s| s.destroy();
        self.snd = null;
    }
};

/// A handle to something `AudioEngine` is playing: one voice of a sound,
/// or a stream. Copy it freely. Once the voice is reused for another play,
/// its sound is reloaded, or the stream ends, the handle goes stale and
/// every call taking it does nothing (`isPlaying` reports false).
pub const Voice = struct {
    /// The sound this is a voice of, or null for a stream.
    sound: ?*SoundHandle,
    index: u32,
    gen: u32,
};

/// Options for `AudioEngine.play`.
pub const PlayOpts = struct {
    /// Linear gain; 1 is the file's own level.
    volume: f32 = 1.0,
    /// -1 is full left, 0 centered, 1 full right.
    pan: f32 = 0.0,
    /// Playback rate; 2 is an octave up and twice as fast.
    pitch: f32 = 1.0,
    loop: bool = false,
    fadeInMs: u32 = 0,
};

/// Options for stopping a voice or the music.
pub const StopOpts = struct {
    /// Fade out over this long, then stop. 0 stops at once.
    fadeOutMs: u32 = 0,
};

/// Options for `AudioEngine.playMusic`.
pub const MusicOpts = struct {
    loop: bool = true,
    volume: f32 = 1.0,
    /// Crossfade length: a track already playing fades out over this long
    /// while the new one fades in. 0 cuts straight over.
    fadeMs: u32 = 0,
};

/// Fills `out` with interleaved f32 samples (`out.len / channels` frames)
/// and returns how many frames it wrote. Returning fewer than asked ends
/// the stream once they have played.
///
/// Runs on miniaudio's audio thread, not the game thread: it must not
/// block, and anything it shares with game code (the `ctx` it was given)
/// needs atomics or a lock-free handoff.
pub const StreamFn = *const fn (ctx: ?*anyopaque, out: []f32, channels: u32) usize;

/// Options for `AudioEngine.playStream`.
pub const StreamOpts = struct {
    channels: u32 = 2,
    /// The rate the callback produces samples at; 0 means the engine's own
    /// rate (`AudioEngine.sampleRate`). miniaudio resamples anything else.
    sampleRate: u32 = 0,
    volume: f32 = 1.0,
    /// The bus it plays through. `master` bypasses both sub-buses.
    bus: Bus = .sfx,
};

/// A stream being played: a miniaudio data source whose reads call the
/// game's `StreamFn`. Heap allocated so miniaudio's pointer to `base`
/// stays put.
const StreamVoice = struct {
    /// Must stay the first thing miniaudio sees; the vtable callbacks get a
    /// pointer to it and recover the stream with `@fieldParentPtr`.
    base: zaudio.DataSourceBase,
    callback: StreamFn,
    ctx: ?*anyopaque,
    channels: u32,
    sampleRate: u32,
    snd: *zaudio.Sound = undefined,
    gen: u32,
    paused: bool = false,
    /// See `stopWithOpts`.
    fadingOut: bool = false,
    /// Set on the audio thread when the callback comes up short; later
    /// reads report the end without calling it again.
    ended: std.atomic.Value(bool) = .init(false),

    const vtable = zaudio.DataSource.VTable{
        .onRead = onRead,
        .onSeek = null,
        .onGetDataFormat = onGetDataFormat,
        .onGetCursor = null,
        .onGetLength = null,
        .onSetLooping = null,
        .flags = .{},
    };

    fn fromDataSource(ds: *zaudio.DataSource) *StreamVoice {
        const base: *zaudio.DataSourceBase = @ptrCast(@alignCast(ds));
        return @fieldParentPtr("base", base);
    }

    fn onRead(ds: *zaudio.DataSource, frames_out: ?*anyopaque, frame_count: u64, frames_read: *u64) callconv(.c) zaudio.Result {
        const self = fromDataSource(ds);
        frames_read.* = 0;
        if (self.ended.load(.acquire) or frames_out == null) return .at_end;

        const samples: [*]f32 = @ptrCast(@alignCast(frames_out.?));
        const out = samples[0 .. @as(usize, @intCast(frame_count)) * self.channels];
        const written = @min(self.callback(self.ctx, out, self.channels), frame_count);
        frames_read.* = written;
        if (written < frame_count) {
            self.ended.store(true, .release);
            if (written == 0) return .at_end;
        }
        return .success;
    }

    fn onGetDataFormat(
        ds: *zaudio.DataSource,
        format: ?*zaudio.Format,
        channels: ?*u32,
        sample_rate: ?*u32,
        channel_map: ?[*]zaudio.Channel,
        channel_map_cap: usize,
    ) callconv(.c) zaudio.Result {
        _ = channel_map;
        _ = channel_map_cap;
        const self = fromDataSource(ds);
        if (format) |f| f.* = .float32;
        if (channels) |c| c.* = self.channels;
        if (sample_rate) |r| r.* = self.sampleRate;
        return .success;
    }
};

/// The music track `AudioEngine` is playing.
const MusicState = struct {
    handle: *MusicHandle,
    /// The handle's `version` when this track started; a hot reload bumps
    /// it, and `update` restarts the new file.
    version: u32,
    opts: MusicOpts,
    /// Paused by `pauseMusic` or `pauseAll`.
    paused: bool = false,
};

/// Plays sounds, music and streams. Reached as `eng.audio`; `AppRunner`
/// calls `update` once per frame.
///
/// The engine's `ResourceManager` owns the sounds and music; this holds
/// the miniaudio engine, the buses, and what is currently playing. Sounds
/// are played by name (`play`, `playMusic`) or by the handle a load
/// returned (`playHandle`, `playMusicHandle`).
pub const AudioEngine = struct {
    engine: *zaudio.Engine,
    sfx: *zaudio.SoundGroup,
    music: *zaudio.SoundGroup,
    res: *ResourceManager,
    allocator: std.mem.Allocator,
    opts: AudioOptions,
    busVolumes: std.EnumArray(Bus, f32) = .initFill(1.0),
    /// Next `Voice.gen` to hand out. Never 0, so a zeroed handle is stale.
    nextGen: u32 = 1,
    playSeq: u64 = 0,
    current: ?MusicState = null,
    streams: std.ArrayList(*StreamVoice) = .empty,

    const Self = @This();

    /// Creates the miniaudio engine and its buses, and attaches them to
    /// `res` so it can load sounds. `res` must outlive the engine. If no
    /// output device opens, the engine logs a warning and carries on
    /// silently (as if `noDevice` were set) rather than failing.
    pub fn init(allocator: std.mem.Allocator, opts: AudioOptions, res: *ResourceManager) !AudioEngine {
        zaudio.init(allocator);
        errdefer zaudio.deinit();

        const engine = if (opts.noDevice)
            try createDeviceless()
        else
            createWithDevice() catch |err| blk: {
                std.log.warn("No audio device ({}); audio will be silent.", .{err});
                break :blk try createDeviceless();
            };
        errdefer engine.destroy();

        const sfx = try engine.createSoundGroup(.{}, null);
        errdefer sfx.destroy();
        const music = try engine.createSoundGroup(.{}, null);
        errdefer music.destroy();

        res.attachAudio(.{ .engine = engine, .sfx = sfx, .music = music });

        return .{
            .engine = engine,
            .sfx = sfx,
            .music = music,
            .res = res,
            .allocator = allocator,
            .opts = opts,
        };
    }

    /// The default engine on the default output device. Sounds load through
    /// `io.vfs`, so they come out of the APK on Android like other assets.
    fn createWithDevice() !*zaudio.Engine {
        var config = zaudio.Engine.Config.init();
        config.resource_manager_vfs = &io.vfs;
        return zaudio.Engine.create(config);
    }

    fn createDeviceless() !*zaudio.Engine {
        var config = zaudio.Engine.Config.init();
        config.resource_manager_vfs = &io.vfs;
        config.no_device = .true32;
        config.channels = 2;
        config.sample_rate = 48000;
        return zaudio.Engine.create(config);
    }

    /// Frees every sound and music track in the `ResourceManager` (their
    /// handles stay valid but play nothing), then the streams, buses and
    /// miniaudio engine.
    pub fn deinit(self: *Self) void {
        self.res.detachAudio();
        for (self.streams.items) |s| self.destroyStream(s);
        self.streams.deinit(self.allocator);
        self.sfx.destroy();
        self.music.destroy();
        self.engine.destroy();
        zaudio.deinit();
    }

    /// The engine's output sample rate, in Hz.
    pub fn sampleRate(self: *const Self) u32 {
        return self.engine.getSampleRate();
    }

    /// Per-frame housekeeping, called by `AppRunner`: restarts the music
    /// track if a hot reload replaced it, and frees streams that ended.
    pub fn update(self: *Self) void {
        if (self.current) |*cur| {
            if (cur.handle.version != cur.version) {
                cur.version = cur.handle.version;
                if (!cur.paused) self.startMusic(cur.handle, cur.opts, 0);
            }
        }

        var i: usize = 0;
        while (i < self.streams.items.len) {
            const s = self.streams.items[i];
            if (!s.paused and !s.snd.isPlaying()) {
                self.destroyStream(s);
                _ = self.streams.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Mixes `frameCount` frames into `out` (interleaved stereo f32, at
    /// least `frameCount * 2` long) and advances audio time by as much.
    /// Only for an engine made with `noDevice`, where nothing else pulls
    /// frames; tests use it to make streams and fades actually run.
    pub fn renderFrames(self: *Self, out: []f32, frameCount: u64) !void {
        std.debug.assert(out.len >= frameCount * 2);
        try self.engine.asNodeGraphMut().readPcmFrames(out.ptr, frameCount, null);
    }

    // -----------------------------------------------------------------------
    // Sound effects
    // -----------------------------------------------------------------------

    /// Plays the sound loaded as `name`. See `playHandle`.
    pub fn play(self: *Self, name: []const u8, opts: PlayOpts) !Voice {
        return self.playHandle(try self.res.getSound(name), opts);
    }

    /// Plays `sound` on a free voice, creating one if fewer than
    /// `maxConcurrentSounds` exist. With every voice busy, the one that has
    /// been playing longest is restarted for this play. Returns a handle
    /// for `stop`, `setVolume` and the rest.
    pub fn playHandle(self: *Self, sound: *SoundHandle, opts: PlayOpts) !Voice {
        const template = sound.val.template orelse return error.SoundNotLoaded;
        const voices = &sound.val.voices;

        const index = pick: {
            var oldest: usize = 0;
            for (voices.items, 0..) |v, i| {
                if (!v.paused and !v.snd.isPlaying()) break :pick i;
                if (v.startSeq < voices.items[oldest].startSeq) oldest = i;
            }
            if (voices.items.len < self.opts.maxConcurrentSounds) {
                const snd = try self.engine.createSoundCopy(template, BaseFlags, self.sfx);
                errdefer snd.destroy();
                try voices.append(sound.val.alloc, .{ .snd = snd, .gen = 0, .startSeq = 0 });
                break :pick voices.items.len - 1;
            }
            if (voices.items.len == 0) return error.NoVoices;
            break :pick oldest;
        };

        const slot = &voices.items[index];
        slot.gen = self.takeGen();
        slot.startSeq = self.playSeq;
        slot.paused = false;
        slot.fadingOut = false;
        self.playSeq += 1;

        restart(slot.snd, opts.volume, opts.fadeInMs);
        slot.snd.setPan(opts.pan);
        slot.snd.setPitch(opts.pitch);
        slot.snd.setLooping(opts.loop);
        slot.snd.start() catch |err| std.log.err("Error playing sound: {}", .{err});

        return .{ .sound = sound, .index = @intCast(index), .gen = slot.gen };
    }

    /// Stops a voice, at once or with a fade. A voice keeps playing
    /// (`isPlaying` is true) until its fade-out ends, and asking it to fade
    /// out again meanwhile is ignored. Stale handles are ignored.
    pub fn stop(self: *Self, voice: Voice, opts: StopOpts) void {
        const r = self.resolve(voice) orelse return;
        stopWithOpts(r.snd, r.fadingOut, opts);
    }

    /// Stops every voice of `name`.
    pub fn stopSound(self: *Self, name: []const u8, opts: StopOpts) !void {
        const sound = try self.res.getSound(name);
        for (sound.val.voices.items) |*v| {
            v.paused = false;
            stopWithOpts(v.snd, &v.fadingOut, opts);
        }
    }

    /// Whether `voice` still refers to something: a voice not yet reused,
    /// or a stream `update` hasn't freed. Paused and finished-but-unreused
    /// voices count; use `isPlaying` to ask whether it's audible.
    pub fn isValid(self: *Self, voice: Voice) bool {
        return self.resolve(voice) != null;
    }

    pub fn isPlaying(self: *Self, voice: Voice) bool {
        const r = self.resolve(voice) orelse return false;
        return r.snd.isPlaying();
    }

    pub fn setVolume(self: *Self, voice: Voice, volume: f32) void {
        if (self.resolve(voice)) |r| r.snd.setVolume(volume);
    }

    pub fn setPan(self: *Self, voice: Voice, pan: f32) void {
        if (self.resolve(voice)) |r| r.snd.setPan(pan);
    }

    pub fn setPitch(self: *Self, voice: Voice, pitch: f32) void {
        if (self.resolve(voice)) |r| r.snd.setPitch(pitch);
    }

    /// What a live `Voice` refers to.
    const Resolved = struct { snd: *zaudio.Sound, fadingOut: *bool };

    /// The miniaudio sound behind `voice`, or null when the handle is stale.
    fn resolve(self: *Self, voice: Voice) ?Resolved {
        if (voice.sound) |sound| {
            const voices = sound.val.voices.items;
            if (voice.index >= voices.len) return null;
            const slot = &voices[voice.index];
            if (slot.gen != voice.gen) return null;
            return .{ .snd = slot.snd, .fadingOut = &slot.fadingOut };
        }
        for (self.streams.items) |s| {
            if (s.gen == voice.gen) return .{ .snd = s.snd, .fadingOut = &s.fadingOut };
        }
        return null;
    }

    fn takeGen(self: *Self) u32 {
        const gen = self.nextGen;
        self.nextGen +%= 1;
        if (self.nextGen == 0) self.nextGen = 1;
        return gen;
    }

    // -----------------------------------------------------------------------
    // Music
    // -----------------------------------------------------------------------

    /// Plays the music loaded as `name`. See `playMusicHandle`.
    pub fn playMusic(self: *Self, name: []const u8, opts: MusicOpts) !void {
        try self.playMusicHandle(try self.res.getMusic(name), opts);
    }

    /// Makes `track` the current music, from the start. A different track
    /// already playing fades out over `opts.fadeMs` while this one fades
    /// in. If `track` is already the current, playing track, only its
    /// volume and looping change; it doesn't restart.
    pub fn playMusicHandle(self: *Self, track: *MusicHandle, opts: MusicOpts) !void {
        const snd = track.val.snd orelse return error.MusicNotLoaded;

        if (self.current) |*cur| {
            if (cur.handle == track and !cur.paused and snd.isPlaying()) {
                cur.opts = opts;
                snd.setVolume(opts.volume);
                snd.setLooping(opts.loop);
                return;
            }
            if (cur.handle != track) {
                const old = &cur.handle.val;
                if (old.snd) |oldSnd| stopWithOpts(oldSnd, &old.fadingOut, .{ .fadeOutMs = opts.fadeMs });
            }
        }

        self.current = .{ .handle = track, .version = track.version, .opts = opts };
        self.startMusic(track, opts, opts.fadeMs);
    }

    fn startMusic(self: *Self, track: *MusicHandle, opts: MusicOpts, fadeInMs: u32) void {
        _ = self;
        const snd = track.val.snd orelse return;
        track.val.fadingOut = false;
        restart(snd, opts.volume, fadeInMs);
        snd.setLooping(opts.loop);
        snd.start() catch |err| std.log.err("Error playing music: {}", .{err});
    }

    /// Stops the current music, at once or with a fade, and clears it.
    pub fn stopMusic(self: *Self, opts: StopOpts) void {
        const cur = self.current orelse return;
        const track = &cur.handle.val;
        if (track.snd) |snd| stopWithOpts(snd, &track.fadingOut, opts);
        self.current = null;
    }

    /// Pauses the current music where it is.
    pub fn pauseMusic(self: *Self) void {
        const cur = if (self.current) |*c| c else return;
        if (cur.paused) return;
        if (cur.handle.val.snd) |snd| snd.stop() catch {};
        cur.paused = true;
    }

    /// Resumes music paused by `pauseMusic` or `pauseAll`.
    pub fn resumeMusic(self: *Self) void {
        const cur = if (self.current) |*c| c else return;
        if (!cur.paused) return;
        cur.paused = false;
        if (cur.handle.version != cur.version) {
            // Reloaded while paused: the new file starts over.
            cur.version = cur.handle.version;
            self.startMusic(cur.handle, cur.opts, 0);
        } else if (cur.handle.val.snd) |snd| {
            snd.start() catch |err| std.log.err("Error resuming music: {}", .{err});
        }
    }

    /// The current music track, playing or paused, or null when none.
    pub fn currentMusic(self: *const Self) ?*MusicHandle {
        return if (self.current) |cur| cur.handle else null;
    }

    /// Whether the current music is audible (not paused, not finished).
    pub fn musicPlaying(self: *const Self) bool {
        const cur = self.current orelse return false;
        if (cur.paused) return false;
        const snd = cur.handle.val.snd orelse return false;
        return snd.isPlaying();
    }

    // -----------------------------------------------------------------------
    // Streams
    // -----------------------------------------------------------------------

    /// Starts playing PCM that `callback` generates, for a mod player, a
    /// synth, or any sound made at runtime. `ctx` is handed back to every
    /// call and must outlive the stream. See `StreamFn` for the threading
    /// rules. The stream ends when the callback comes up short, or on
    /// `stop`; `update` frees it after that.
    pub fn playStream(self: *Self, callback: StreamFn, ctx: ?*anyopaque, opts: StreamOpts) !Voice {
        if (opts.channels == 0) return error.InvalidChannelCount;

        const s = try self.allocator.create(StreamVoice);
        errdefer self.allocator.destroy(s);
        s.* = .{
            .base = undefined,
            .callback = callback,
            .ctx = ctx,
            .channels = opts.channels,
            .sampleRate = if (opts.sampleRate == 0) self.sampleRate() else opts.sampleRate,
            .gen = self.takeGen(),
        };

        var config = zaudio.DataSource.Config.init();
        config.vtable = &StreamVoice.vtable;
        const ds = try zaudio.DataSource.create(config, &s.base);
        errdefer ds.uninit();

        const group: ?*zaudio.SoundGroup = switch (opts.bus) {
            .master => null,
            .sfx => self.sfx,
            .music => self.music,
        };
        s.snd = try self.engine.createSoundFromDataSource(ds, BaseFlags, group);
        errdefer s.snd.destroy();

        try self.streams.append(self.allocator, s);
        s.snd.setVolume(opts.volume);
        s.snd.start() catch |err| std.log.err("Error starting stream: {}", .{err});
        return .{ .sound = null, .index = 0, .gen = s.gen };
    }

    fn destroyStream(self: *Self, s: *StreamVoice) void {
        s.snd.destroy();
        const ds: *zaudio.DataSource = @ptrCast(&s.base);
        ds.uninit();
        self.allocator.destroy(s);
    }

    // -----------------------------------------------------------------------
    // Buses and pausing
    // -----------------------------------------------------------------------

    /// Sets a bus's linear volume. `sfx` and `music` scale everything on
    /// them; `master` scales the whole mix.
    pub fn setBusVolume(self: *Self, bus: Bus, volume: f32) void {
        self.busVolumes.set(bus, volume);
        switch (bus) {
            .master => self.engine.setVolume(volume) catch |err| std.log.err("Error setting master volume: {}", .{err}),
            .sfx => self.sfx.setVolume(volume),
            .music => self.music.setVolume(volume),
        }
    }

    pub fn busVolume(self: *const Self, bus: Bus) f32 {
        return self.busVolumes.get(bus);
    }

    /// Pauses every sound voice, stream and the music that is playing right
    /// now, keeping their positions, for a pause menu or the app going to
    /// the background. Sounds played afterwards (menu clicks) still play.
    pub fn pauseAll(self: *Self) void {
        var it = self.res.sounds.valueIterator();
        while (it.next()) |sound| {
            for (sound.*.val.voices.items) |*v| {
                if (v.paused or !v.snd.isPlaying()) continue;
                v.snd.stop() catch {};
                v.paused = true;
            }
        }
        for (self.streams.items) |s| {
            if (s.paused or !s.snd.isPlaying()) continue;
            s.snd.stop() catch {};
            s.paused = true;
        }
        if (self.musicPlaying()) self.pauseMusic();
    }

    /// Resumes everything `pauseAll` paused (and music paused with
    /// `pauseMusic`).
    pub fn resumeAll(self: *Self) void {
        var it = self.res.sounds.valueIterator();
        while (it.next()) |sound| {
            for (sound.*.val.voices.items) |*v| {
                if (!v.paused) continue;
                v.paused = false;
                v.snd.start() catch |err| std.log.err("Error resuming sound: {}", .{err});
            }
        }
        for (self.streams.items) |s| {
            if (!s.paused) continue;
            s.paused = false;
            s.snd.start() catch |err| std.log.err("Error resuming stream: {}", .{err});
        }
        self.resumeMusic();
    }

    // -----------------------------------------------------------------------
    // Lua
    // -----------------------------------------------------------------------

    /// Registers the audio functions as Lua globals. The engine does this
    /// itself when both scripting and audio are on; call it for a
    /// `ScriptEngine` of your own. `self` must outlive the Lua state.
    ///
    ///   audio_play(name [, volume [, pan [, pitch]]])
    ///   audio_stop(name [, fade_ms])         -- every voice of a sound
    ///   audio_set_volume(bus, volume)        -- bus: "master"|"sfx"|"music"
    ///   audio_pause_all()  audio_resume_all()
    ///   music_play(name [, fade_ms [, loop]])
    ///   music_stop([fade_ms])  music_pause()  music_resume()
    ///
    /// Unknown names or buses log a warning; they don't raise Lua errors.
    pub fn bindToLua(self: *Self, script: *ScriptEngine) !void {
        try script.registerMethod(Self, self, "audio_play", luaAudioPlay);
        try script.registerMethod(Self, self, "audio_stop", luaAudioStop);
        try script.registerMethod(Self, self, "audio_set_volume", luaAudioSetVolume);
        try script.registerMethod(Self, self, "audio_pause_all", luaAudioPauseAll);
        try script.registerMethod(Self, self, "audio_resume_all", luaAudioResumeAll);
        try script.registerMethod(Self, self, "music_play", luaMusicPlay);
        try script.registerMethod(Self, self, "music_stop", luaMusicStop);
        try script.registerMethod(Self, self, "music_pause", luaMusicPause);
        try script.registerMethod(Self, self, "music_resume", luaMusicResume);
    }
};

/// Readies `snd` to start from the beginning: clears a stop a fade-out
/// scheduled (miniaudio keeps it, and the fader's 0 volume, across a
/// restart), rewinds, and sets the volume and optional fade-in.
fn restart(snd: *zaudio.Sound, volume: f32, fadeInMs: u32) void {
    snd.stop() catch {};
    snd.setStopTimeInPcmFrames(std.math.maxInt(u64));
    snd.seekToPcmFrame(0) catch {};
    snd.setVolume(volume);
    if (fadeInMs > 0) {
        snd.setFadeInMilliseconds(0.0, 1.0, fadeInMs);
    } else {
        snd.setFadeInPcmFrames(1.0, 1.0, 0);
    }
}

/// Stops `snd` at once, or schedules a fade-out stop. `fadingOut` is the
/// owner's flag for a fade already under way: miniaudio would push the
/// scheduled stop back on every repeat, so code that polls "if playing,
/// fade out" would never let the sound end. An immediate stop always works.
fn stopWithOpts(snd: *zaudio.Sound, fadingOut: *bool, opts: StopOpts) void {
    if (opts.fadeOutMs > 0 and snd.isPlaying()) {
        if (fadingOut.*) return;
        snd.stopWithFadeInMilliseconds(opts.fadeOutMs) catch {};
        fadingOut.* = true;
    } else {
        snd.stop() catch {};
        fadingOut.* = false;
    }
}

// --- Lua function implementations --------------------------------------------

fn luaOptNumber(lua: *Lua, idx: i32, default: f32) f32 {
    if (lua.getTop() < idx or lua.isNil(idx)) return default;
    return @floatCast(lua.toNumber(idx) catch return default);
}

fn luaOptMs(lua: *Lua, idx: i32) u32 {
    return @intFromFloat(@max(0.0, luaOptNumber(lua, idx, 0.0)));
}

fn luaAudioPlay(self: *AudioEngine, lua: *Lua) i32 {
    const name = lua.toString(1) catch return 0;
    _ = self.play(name, .{
        .volume = luaOptNumber(lua, 2, 1.0),
        .pan = luaOptNumber(lua, 3, 0.0),
        .pitch = luaOptNumber(lua, 4, 1.0),
    }) catch |err| std.log.warn("audio_play('{s}'): {}", .{ name, err });
    return 0;
}

fn luaAudioStop(self: *AudioEngine, lua: *Lua) i32 {
    const name = lua.toString(1) catch return 0;
    self.stopSound(name, .{ .fadeOutMs = luaOptMs(lua, 2) }) catch |err|
        std.log.warn("audio_stop('{s}'): {}", .{ name, err });
    return 0;
}

fn luaAudioSetVolume(self: *AudioEngine, lua: *Lua) i32 {
    const busName = lua.toString(1) catch return 0;
    const bus = std.meta.stringToEnum(Bus, busName) orelse {
        std.log.warn("audio_set_volume: unknown bus '{s}'", .{busName});
        return 0;
    };
    self.setBusVolume(bus, luaOptNumber(lua, 2, 1.0));
    return 0;
}

fn luaAudioPauseAll(self: *AudioEngine, _: *Lua) i32 {
    self.pauseAll();
    return 0;
}

fn luaAudioResumeAll(self: *AudioEngine, _: *Lua) i32 {
    self.resumeAll();
    return 0;
}

fn luaMusicPlay(self: *AudioEngine, lua: *Lua) i32 {
    const name = lua.toString(1) catch return 0;
    const loop = if (lua.getTop() < 3 or lua.isNil(3)) true else lua.toBoolean(3);
    self.playMusic(name, .{ .fadeMs = luaOptMs(lua, 2), .loop = loop }) catch |err|
        std.log.warn("music_play('{s}'): {}", .{ name, err });
    return 0;
}

fn luaMusicStop(self: *AudioEngine, lua: *Lua) i32 {
    self.stopMusic(.{ .fadeOutMs = luaOptMs(lua, 1) });
    return 0;
}

fn luaMusicPause(self: *AudioEngine, _: *Lua) i32 {
    self.pauseMusic();
    return 0;
}

fn luaMusicResume(self: *AudioEngine, _: *Lua) i32 {
    self.resumeMusic();
    return 0;
}

/// Stand-in for `AudioEngine` used as `Engine.audio` when
/// `AudioOptions.enabled` is false. Every method is a compile error naming
/// the flag, so using audio without enabling it fails at build time instead
/// of touching an uninitialized engine.
pub const DisabledAudioEngine = struct {
    fn disabled(comptime method: []const u8) noreturn {
        @compileError("audio." ++ method ++ " requires AudioOptions.enabled = true (EngineOptions.audioOpts.enabled)");
    }

    pub fn play(_: *DisabledAudioEngine, _: []const u8, _: PlayOpts) !Voice {
        disabled("play");
    }
    pub fn playHandle(_: *DisabledAudioEngine, _: *SoundHandle, _: PlayOpts) !Voice {
        disabled("playHandle");
    }
    pub fn stop(_: *DisabledAudioEngine, _: Voice, _: StopOpts) void {
        disabled("stop");
    }
    pub fn stopSound(_: *DisabledAudioEngine, _: []const u8, _: StopOpts) !void {
        disabled("stopSound");
    }
    pub fn isPlaying(_: *DisabledAudioEngine, _: Voice) bool {
        disabled("isPlaying");
    }
    pub fn setVolume(_: *DisabledAudioEngine, _: Voice, _: f32) void {
        disabled("setVolume");
    }
    pub fn setPan(_: *DisabledAudioEngine, _: Voice, _: f32) void {
        disabled("setPan");
    }
    pub fn setPitch(_: *DisabledAudioEngine, _: Voice, _: f32) void {
        disabled("setPitch");
    }
    pub fn playMusic(_: *DisabledAudioEngine, _: []const u8, _: MusicOpts) !void {
        disabled("playMusic");
    }
    pub fn playMusicHandle(_: *DisabledAudioEngine, _: *MusicHandle, _: MusicOpts) !void {
        disabled("playMusicHandle");
    }
    pub fn stopMusic(_: *DisabledAudioEngine, _: StopOpts) void {
        disabled("stopMusic");
    }
    pub fn pauseMusic(_: *DisabledAudioEngine) void {
        disabled("pauseMusic");
    }
    pub fn resumeMusic(_: *DisabledAudioEngine) void {
        disabled("resumeMusic");
    }
    pub fn musicPlaying(_: *DisabledAudioEngine) bool {
        disabled("musicPlaying");
    }
    pub fn playStream(_: *DisabledAudioEngine, _: StreamFn, _: ?*anyopaque, _: StreamOpts) !Voice {
        disabled("playStream");
    }
    pub fn setBusVolume(_: *DisabledAudioEngine, _: Bus, _: f32) void {
        disabled("setBusVolume");
    }
    pub fn pauseAll(_: *DisabledAudioEngine) void {
        disabled("pauseAll");
    }
    pub fn resumeAll(_: *DisabledAudioEngine) void {
        disabled("resumeAll");
    }
};
