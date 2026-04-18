//! Audio engine for pixzig, built on top of zaudio. This module manages
//! loading and playing sounds.
const std = @import("std");
const zaudio = @import("zaudio");

/// The default maximum number of concurrent instances of a sound that can be
/// played.
pub const DefaultMaxConcurrentSounds = 16;

/// Audio engine options for pixzig
pub const AudioOptions = struct {
    // Default to not initializing audio.
    enabled: bool = false,
    maxConcurrentSounds: u8 = DefaultMaxConcurrentSounds,
};

/// A named soundm, with a number of concurrently playable instances.
pub const Sound = struct {
    snds: std.ArrayList(*zaudio.Sound),
    name: []const u8,
};

/// Manages audio resources and playback.
pub const AudioEngine = struct {
    sounds: std.StringHashMap(Sound),
    engine: *zaudio.Engine,
    allocator: std.mem.Allocator,

    /// Initializes the audio engine. Must be called before using any other
    /// audio functions.
    pub fn init(allocator: std.mem.Allocator) !AudioEngine {
        zaudio.init(allocator);
        return AudioEngine{
            .sounds = std.StringHashMap(Sound).init(allocator),
            .engine = try zaudio.Engine.create(null),
            .allocator = allocator,
        };
    }

    /// Cleans up audio resources. Should be called when the application is
    /// shutting down.
    pub fn deinit(self: *AudioEngine) void {
        var sndIt = self.sounds.iterator();
        while (sndIt.next()) |kv| {
            const snd = kv.value_ptr;

            std.log.debug("Cleaning up sound '{s}', with {} samples.", .{ snd.name, snd.snds.items.len });

            for (snd.snds.items) |s| {
                s.destroy();
            }
            snd.snds.deinit(self.allocator);
            self.allocator.free(snd.name);
        }

        self.engine.destroy();
        zaudio.deinit();
    }

    /// Loads a sound from a file and associates it with the given name. The
    /// sound can then be played using playSound.
    pub fn loadSound(self: *AudioEngine, name: []const u8, path: []const u8) !void {
        const pathZ = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(pathZ);
        const sound = try self.engine.createSoundFromFile(pathZ, .{});

        if (self.sounds.get(name) != null) {
            return error.SoundAlreadyExists;
        }

        var sndList: std.ArrayList(*zaudio.Sound) = .{};
        try sndList.append(self.allocator, sound);
        try self.sounds.put(name, Sound{
            .snds = sndList,
            .name = try self.allocator.dupe(u8, name),
        });
    }

    /// Plays the sound associated with the given name. If the sound is already
    /// playing and the maximum number of concurrent instances has not been
    /// reached, a new instance of the sound will be created and played. If the
    /// maximum number of concurrent instances has been reached, the function will
    /// do nothing.
    pub fn playSound(self: *AudioEngine, name: []const u8) !void {
        var snd = self.sounds.getPtr(name) orelse return error.SoundNotLoaded;
        var sndList = &snd.snds;

        // Find a sound that isn't currently playing.
        for (sndList.items) |s| {
            if (!s.isPlaying()) {
                s.start() catch |err| {
                    std.debug.print("Error playing sound: {}\n", .{err});
                };
                return;
            }
        }

        // If we got here, all sounds are currently playing. If we have room to create a new one, do it..
        if (sndList.items.len < DefaultMaxConcurrentSounds) {
            const newSnd = try self.engine.createSoundCopy(snd.snds.items[0], .{}, null);
            try sndList.append(self.allocator, newSnd);
            newSnd.start() catch |err| {
                std.debug.print("Error playing sound: {}\n", .{err});
            };
        } else {
            std.debug.print("Max concurrent sounds reached for '{s}'. Cannot play sound.\n", .{name});
        }
    }
};
