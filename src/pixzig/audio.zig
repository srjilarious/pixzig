const std = @import("std");
const zaudio = @import("zaudio");

pub const DefaultMaxConcurrentSounds = 16;

pub const AudioOptions = struct {
    // Default to not initializing audio.
    enabled: bool = false,
    maxConcurrentSounds: u8 = DefaultMaxConcurrentSounds,
};

pub const Sound = struct {
    snds: std.ArrayList(*zaudio.Sound),
    name: []const u8,
};

pub const AudioEngine = struct {
    sounds: std.StringHashMap(Sound),
    engine: *zaudio.Engine,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !AudioEngine {
        zaudio.init(allocator);
        return AudioEngine{
            .sounds = std.StringHashMap(Sound).init(allocator),
            .engine = try zaudio.Engine.create(null),
            .allocator = allocator,
        };
    }

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
