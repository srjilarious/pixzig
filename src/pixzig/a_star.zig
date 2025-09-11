const std = @import("std");
const Vec2I = @import("./common.zig").Vec2I;
const tiles = @import("./tile.zig");

const TileLayer = tiles.TileLayer;

pub const TileLoc = struct {
    x: i32,
    y: i32,

    pub fn equals(self: *const TileLoc, other: TileLoc) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn isLeftOf(self: *const TileLoc, other: TileLoc) bool {
        return self.x < other.x and self.y == other.y;
    }

    pub fn isRightOf(self: *const TileLoc, other: TileLoc) bool {
        return self.x > other.x and self.y == other.y;
    }

    pub fn isAbove(self: *const TileLoc, other: TileLoc) bool {
        return self.x == other.x and self.y < other.y;
    }

    pub fn isBelow(self: *const TileLoc, other: TileLoc) bool {
        return self.x == other.x and self.y > other.y;
    }
};

const TilePathInfo = struct {
    score: i32,
};

const PathElem = struct {
    location: TileLoc,
    score: f32,
};

pub const Path = std.ArrayList(TileLoc);

const LocData = struct {
    cameFrom: TileLoc = .{ .x = -1, .y = -1 },
    costSoFar: f32 = -1.0,
};

const EmptyContext = struct {};

fn comparePathElem(_: EmptyContext, a: PathElem, b: PathElem) std.math.Order {
    return std.math.order(a.score, b.score);
}

const AStarPriorityQueue = std.PriorityQueue(PathElem, EmptyContext, comparePathElem);

const LocDataArray = std.ArrayList(LocData);

pub const BasicTileMapPathChecker = struct {
    tileLayer: *const TileLayer,

    pub fn init(tileLayer: *const TileLayer) BasicTileMapPathChecker {
        return .{ .tileLayer = tileLayer };
    }

    pub fn checkPosition(self: *BasicTileMapPathChecker, loc: TileLoc) bool {
        const tile = self.tileLayer.tile(loc.x, loc.y);
        if (tile == null) return true;

        return (tile.?.core & tiles.BlocksAll) == 0;
    }
};

pub fn AStarPathFinder(comptime CheckContext: type) type {
    return struct {
        locDataArr: LocDataArray,
        size: Vec2I,
        alloc: std.mem.Allocator,
        checker: CheckContext,

        pub fn init(checker: CheckContext, alloc: std.mem.Allocator, size: Vec2I) !@This() {
            if (size.x < 0 or size.y < 0) return error.NegativeBoundsGiven;

            var locDataArr: LocDataArray = .{};
            const amount: usize = @intCast(size.x * size.y);
            try locDataArr.appendNTimes(alloc, LocData{}, amount);
            return .{
                .locDataArr = locDataArr,
                .size = size,
                .alloc = alloc,
                .checker = checker,
            };
        }

        fn heuristic(a: TileLoc, b: TileLoc) f32 {
            return @floatFromInt(@abs(a.x - b.x) + @abs(a.y - b.y));
        }

        fn locData(self: *@This(), pos: TileLoc) ?*LocData {
            if (pos.x < 0 or pos.x >= self.size.x or pos.y < 0 or pos.y >= self.size.y) {
                return null;
            }

            const index: usize = @intCast(pos.y * self.size.x + pos.x);
            return &self.locDataArr.items[index];
        }

        pub fn findPath(self: *@This(), start: TileLoc, goal: TileLoc, path: *Path) !void {
            var frontier = AStarPriorityQueue.init(self.alloc, .{});
            try frontier.add(.{ .location = start, .score = 0.0 });
            @memset(self.locDataArr.items, LocData{});
            path.clearRetainingCapacity();

            const startLoc = self.locData(start);
            if (startLoc == null) return;

            startLoc.?.cameFrom = start;

            // Explore the frontier
            while (frontier.count() > 0) {
                const curr = frontier.remove();
                if (curr.location.equals(goal)) {
                    break;
                }

                const nextTileLocs: [4]TileLoc = .{
                    .{ .x = curr.location.x + 1, .y = curr.location.y },
                    .{ .x = curr.location.x - 1, .y = curr.location.y },
                    .{ .x = curr.location.x, .y = curr.location.y + 1 },
                    .{ .x = curr.location.x, .y = curr.location.y - 1 },
                };

                const currLoc = self.locData(curr.location);
                for (nextTileLocs) |nextTileLoc| {
                    if (nextTileLoc.equals(curr.location)) continue;

                    const nextLoc = self.locData(nextTileLoc);
                    if (nextLoc == null) continue;

                    if (!self.checker.checkPosition(nextTileLoc)) {
                        continue;
                    }

                    const newCost = currLoc.?.costSoFar + 1;
                    if (nextLoc.?.costSoFar < 0.0 or
                        newCost < nextLoc.?.costSoFar)
                    {
                        nextLoc.?.costSoFar = newCost;
                        const priority = newCost + heuristic(nextTileLoc, goal);
                        try frontier.add(.{ .location = nextTileLoc, .score = priority });
                        nextLoc.?.cameFrom = curr.location;
                    }
                }
            }

            // Reconstruct the path from goal back to start.
            var pLoc = self.locData(goal);
            try path.append(self.alloc, goal);
            while (pLoc != null and !pLoc.?.cameFrom.equals(start)) {
                try path.append(self.alloc, pLoc.?.cameFrom);
                pLoc = self.locData(pLoc.?.cameFrom);
            }

            // Reverse the path items to get from start to goal.
            std.mem.reverse(TileLoc, path.items);
        }
    };
}
