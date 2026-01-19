const std = @import("std");

pub const FpsCounter = struct {
    mElapsed: f64,
    mFrames: u32,
    mTotalFrames: u64,
    mFps: u32,

    pub fn init() FpsCounter {
        return .{ .mFps = 0, .mElapsed = 0, .mFrames = 0, .mTotalFrames = 0 };
    }

    pub fn update(self: *FpsCounter, elapsed: f64) bool {
        self.mElapsed += elapsed;
        if (self.mElapsed > 1000.0) {
            self.mFps = self.mFrames;
            self.mFrames = 0;
            self.mElapsed -= 1000.0;
            return true;
        }

        return false;
    }

    pub fn renderTick(self: *FpsCounter) void {
        self.mFrames += 1;
    }

    pub fn fps(self: *FpsCounter) u32 {
        return self.mFps;
    }

    pub fn totalFrames(self: *FpsCounter) u32 {
        return self.mTotalFrames;
    }
};

pub const Delay = struct {
    curr: usize = 0,
    max: usize,

    pub fn update(self: *Delay, num: usize) bool {
        self.curr += num;
        if (self.curr > self.max) {
            self.curr = 0;
            return true;
        }

        return false;
    }
};

pub const DelayF = struct {
    curr: f64 = 0,
    max: f64,

    pub fn update(self: *DelayF, num: f64) bool {
        self.curr += num;
        if (self.curr > self.max) {
            self.curr = 0;
            return true;
        }

        return false;
    }
};

pub fn cStrToSlice(c_str: [*:0]const u8) []const u8 {
    const length = std.mem.len(c_str);
    return c_str[0..length];
}

// Removes the starting path and end extension from the given path
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

// Adds the extension to the path, caller is responsible for freeing.
pub fn addExtension(alloc: std.mem.Allocator, path: []const u8, ext: []const u8) ![]const u8 {
    return try std.mem.concat(alloc, u8, &[_][]const u8{ path, ext });
}
