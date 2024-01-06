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
        if (self.mElapsed > 1.0) {
            self.mFps = self.mFrames;
            self.mFrames = 0;
            self.mElapsed -= 1.0;
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
