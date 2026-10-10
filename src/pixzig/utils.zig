//! Utility/helper functions and structures that don't fit into other categories.
const std = @import("std");

/// A structure for tracking frames per second (FPS) in a game. It keeps track
/// of the elapsed time, the number of frames rendered, and calculates the
/// FPS based on the elapsed time.
pub const FpsCounter = struct {
    /// Milliseconds accumulated toward the current one-second window.
    elapsedMs: f64,
    /// Frames rendered so far in the current window.
    windowFrames: u32,
    /// Frames rendered since init.
    framesTotal: u64,
    /// Frames counted in the last completed window.
    lastFps: u32,

    /// Initializes the FPS counter with everything at zero.
    pub fn init() FpsCounter {
        return .{ .elapsedMs = 0, .windowFrames = 0, .framesTotal = 0, .lastFps = 0 };
    }

    /// Updates the FPS counter with the elapsed time since the last update.
    /// It adds the elapsed time to the total elapsed time. Once a full
    /// second (1000 ms) has accumulated, it snapshots the frames rendered
    /// in that window as the FPS, resets the frame count, and subtracts
    /// 1000 ms so any overshoot carries into the next window. Returns true
    /// when the FPS was updated, and false otherwise.
    pub fn update(self: *FpsCounter, elapsed: f64) bool {
        self.elapsedMs += elapsed;
        if (self.elapsedMs > 1000.0) {
            self.lastFps = self.windowFrames;
            self.windowFrames = 0;
            self.elapsedMs -= 1000.0;
            return true;
        }

        return false;
    }

    /// Increments the frame counts by 1. This should be called every
    /// time a frame is rendered, regardless of whether the FPS was updated
    /// or not.
    pub fn renderTick(self: *FpsCounter) void {
        self.windowFrames += 1;
        self.framesTotal += 1;
    }

    /// Returns the current FPS value, which is the number of frames rendered
    /// in the last second. This value is updated every time the update
    /// function is called and the elapsed time exceeds 1000 milliseconds.
    pub fn fps(self: *FpsCounter) u32 {
        return self.lastFps;
    }

    /// Returns the number of frames rendered since init.
    pub fn totalFrames(self: *FpsCounter) u64 {
        return self.framesTotal;
    }
};

/// A repeating timer: fires once every `period` units of whatever you feed
/// `update`, e.g. `Timer(f64)` with milliseconds or `Timer(u32)` with
/// ticks.
///
/// ```zig
/// spawn: Timer(f64) = .{ .period = 500 },
/// ...
/// if (self.spawn.update(deltaMs)) self.spawnEnemy();
/// ```
pub fn Timer(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Time accumulated since the timer last fired.
        elapsed: T = 0,
        /// How much time passes between firings.
        period: T,

        /// Adds `dt` and returns true when that reaches `period`. The
        /// overshoot carries into the next period, so a timer fed uneven
        /// steps still fires at a steady average rate. Fires at most once
        /// per call.
        pub fn update(self: *Self, dt: T) bool {
            self.elapsed += dt;
            if (self.elapsed < self.period) return false;
            self.elapsed -= self.period;
            return true;
        }

        /// Starts the current period over.
        pub fn reset(self: *Self) void {
            self.elapsed = 0;
        }

        /// How far through the current period the timer is, in [0, 1].
        /// Handy as the `t` for an `easing.Ease` curve.
        pub fn progress(self: *const Self) f32 {
            if (self.period <= 0) return 1;
            const ratio = asF32(self.elapsed) / asF32(self.period);
            return @min(ratio, 1.0);
        }

        fn asF32(v: T) f32 {
            return switch (@typeInfo(T)) {
                .float, .comptime_float => @floatCast(v),
                else => @floatFromInt(v),
            };
        }
    };
}

/// Converts a null-terminated C string to a Zig slice. The caller is
/// responsible for ensuring that the C string is valid and null-terminated.
pub fn cStrToSlice(c_str: [*:0]const u8) []const u8 {
    const length = std.mem.len(c_str);
    return c_str[0..length];
}

/// Removes the starting path and end extension from the given path
pub fn baseNameFromPath(path: []const u8) []const u8 {
    const rootName = blk: {
        const lastIndex = std.mem.lastIndexOf(u8, path, "/");
        if (lastIndex != null) {
            break :blk path[lastIndex.? + 1 ..];
        } else {
            break :blk path;
        }
    };

    const name = blk: {
        const lastIndex = std.mem.lastIndexOf(u8, rootName, ".");
        if (lastIndex != null) {
            break :blk rootName[0..lastIndex.?];
        } else {
            break :blk rootName;
        }
    };

    return name;
}

/// Adds the extension to the path, caller is responsible for freeing.
pub fn addExtension(alloc: std.mem.Allocator, path: []const u8, ext: []const u8) ![]const u8 {
    return try std.mem.concat(alloc, u8, &[_][]const u8{ path, ext });
}
