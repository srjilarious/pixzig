const std = @import("std");

pub const TileIndexMap = struct {
    const KV = struct {
        tileIdx: usize,
        bufferIdx: usize,
    };
    arr: std.ArrayList(KV),
    alloc: std.mem.Allocator,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .alloc = alloc,
            .arr = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arr.deinit(self.alloc);
    }

    pub fn getBuffIndex(self: *const Self, tileIdx: usize) ?usize {
        for (self.arr.items) |kv| {
            if (kv.tileIdx == tileIdx) {
                return kv.bufferIdx;
            }
        }
        return null;
    }

    pub fn getTileIndex(self: *const Self, bufferIdx: usize) ?usize {
        for (self.arr.items) |kv| {
            if (kv.bufferIdx == bufferIdx) {
                return kv.tileIdx;
            }
        }
        return null;
    }

    pub fn getIdxFromTileIndex(self: *const Self, tileIdx: usize) ?usize {
        for (self.arr.items, 0..) |kv, idx| {
            if (kv.tileIdx == tileIdx) {
                return idx;
            }
        }
        return null;
    }

    pub fn update(self: *Self, tileIdx: usize, bufferIdx: usize) bool {
        if (self.getIdxFromTileIndex(tileIdx)) |idx| {
            self.arr.items[idx].bufferIdx = bufferIdx;
            return true;
        } else {
            return false;
        }
    }

    pub fn removeByTileIndex(self: *Self, tileIndex: usize) bool {
        if (self.getIdxFromTileIndex(tileIndex)) |idx| {
            _ = self.arr.swapRemove(idx);
            return true;
        } else {
            return false;
        }
    }

    pub fn put(self: *Self, tileIndex: usize, bufferIndex: usize) !bool {
        const val: KV = .{ .tileIdx = tileIndex, .bufferIdx = bufferIndex };
        if (self.getIdxFromTileIndex(tileIndex)) |idx| {
            self.arr.items[idx] = val;
            return true;
        } else {
            try self.arr.append(self.alloc, val);
            return false;
        }
    }
};
