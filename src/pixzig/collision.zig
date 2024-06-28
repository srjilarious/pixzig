const std = @import("std");
const common = @import("./common.zig");

const Vec2U = common.Vec2U;
const Vec2I = common.Vec2I;
const RectF = common.RectF;

pub fn CollisionGrid(comptime T: type, comptime maxItemsPerCell: usize) type {
    return struct {
        const Self = @This();

        grid: std.ArrayList([maxItemsPerCell]?T),
        gridSize: Vec2U,
        cellSize: Vec2U,

        pub fn init(alloc: std.mem.Allocator, gridSize: Vec2U, cellSize: Vec2U) !Self {
            var grid = std.ArrayList([maxItemsPerCell]?T).init(alloc);
            const gridLen = gridSize.x * gridSize.y;
            try grid.resize(gridLen);
            for (0..gridLen) |idx| {
                for (0..maxItemsPerCell) |subIdx| {
                    grid.items[idx][subIdx] = null;
                }
            }

            return .{
                .grid = grid,
                .gridSize = gridSize,
                .cellSize = cellSize,
            };
        }

        pub fn deinit(self: *Self) void {
            self.grid.deinit();
        }

        pub fn resize(self: *Self, sz: Vec2U) !void {
            self.gridSize = sz;
            // TODO: Handle copying contents into resized grid.
            try self.grid.resize(sz.x * sz.y);
        }

        pub fn insert(self: *Self, pixelPos: Vec2U, obj: T) !void {
            const cx: usize = @as(usize, @intCast(pixelPos.x)) / self.cellSize.x;
            const cy: usize = @as(usize, @intCast(pixelPos.y)) / self.cellSize.y;
            const idx: usize = cy * self.gridSize.x + cx;
            var items = &self.grid.items[idx];

            for (0..items.len) |itIdx| {
                if (items[itIdx] == null) {
                    items[itIdx] = obj;
                    return;
                }
            }

            return error.NoMoreSpace;
        }

        // pub fn insertRect(self: *Self, bounds: RectF, obj: T) !void {
        //
        // }

        // pub fn removeRect(self: *Self, bounds: RectF, obj: T) !void {
        //
        // }

        pub fn checkPoint(self: *Self, pixelPos: Vec2I, outList: *const []?T) !bool {
            if ((pixelPos.x < 0) or (@as(usize, @intCast(pixelPos.x)) >= self.gridSize.x)) {
                return false;
            }

            if ((pixelPos.y < 0) or (@as(usize, @intCast(pixelPos.y)) >= self.gridSize.y)) {
                return false;
            }

            const cx: usize = @as(usize, @intCast(pixelPos.x)) / self.cellSize.x;
            const cy: usize = @as(usize, @intCast(pixelPos.y)) / self.cellSize.y;
            const idx: usize = cy * self.gridSize.x + cx;
            const items = self.grid.items[idx];

            var foundItem: bool = false;
            for (0..items.len) |itIdx| {
                if (items[itIdx] == null) break;

                outList.*[itIdx] = items[itIdx];
                foundItem = true;
            }

            return foundItem;
        }
    };
}
