const std = @import("std");
const Vec2I = @import("./common.zig").Vec2I;
const tiles = @import("./tile.zig");

const TileLayer = tiles.TileLayer;

/// A location on a tilemap with helpers for checking relative positions.
/// We assume a coordinate system of the top left of the map at 0,0 and the
/// bottom right at size.x, size.y.
pub const TileLoc = struct {
    /// The x coordinate of the tile location
    x: i32,

    /// The y coordinate of the tile location
    y: i32,

    /// Checks if this location is equal to another location
    pub fn equals(self: *const TileLoc, other: TileLoc) bool {
        return self.x == other.x and self.y == other.y;
    }

    /// Checks if this location is directly left of another location
    pub fn isLeftOf(self: *const TileLoc, other: TileLoc) bool {
        return self.x < other.x and self.y == other.y;
    }

    /// Checks if this location is directly right of another location
    pub fn isRightOf(self: *const TileLoc, other: TileLoc) bool {
        return self.x > other.x and self.y == other.y;
    }

    /// Checks if this location is directly above another location
    pub fn isAbove(self: *const TileLoc, other: TileLoc) bool {
        return self.x == other.x and self.y < other.y;
    }

    /// Checks if this location is directly below another location
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

/// A list of tile locations representing a path from a start to a goal.
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

/// A basic tilemap path checker that uses the Tile core properties and checks
/// for BlocksAll (i.e. any direction).  This can be used as the CheckContext
/// for AStarPathFinder for basic tile map use cases.
pub const BasicTileMapPathChecker = struct {
    tileLayer: *const TileLayer,

    /// Initializes the path checker with a reference to the tile layer. The
    /// path checker will use the tile layer to check if tiles are walkable based
    /// on their core properties.
    pub fn init(tileLayer: *const TileLayer) BasicTileMapPathChecker {
        return .{ .tileLayer = tileLayer };
    }

    /// Checks if the tile at the given location is walkable (i.e. does not have
    /// the BlocksAll property). If the location is out of bounds or has no
    /// tile, it is considered walkable.
    pub fn checkPosition(self: *BasicTileMapPathChecker, loc: TileLoc) bool {
        const tile = self.tileLayer.tile(loc.x, loc.y);
        if (tile == null) return true;

        return (tile.?.core & tiles.BlocksAll) == 0;
    }
};

/// A* Pathfinding implementation for tilemaps. The CheckContext must provide a checkPosition(loc: TileLoc) bool function to determine if a tile can be pathwalked on.
pub fn AStarPathFinder(comptime CheckContext: type) type {
    return struct {
        locDataArr: LocDataArray,
        size: Vec2I,
        alloc: std.mem.Allocator,
        checker: CheckContext,

        const Self = @This();

        /// Initializes the pathfinder with the provided size. The size is used for bounds checking and should be the size of the tilemap. The pathfinder will allocate internal data structures based on the size, so it is recommended to reuse a single pathfinder instance for multiple pathfinding calls on the same map.
        pub fn init(checker: CheckContext, alloc: std.mem.Allocator, size: Vec2I) !Self {
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

        fn locData(self: *Self, pos: TileLoc) ?*LocData {
            if (pos.x < 0 or pos.x >= self.size.x or pos.y < 0 or pos.y >= self.size.y) {
                return null;
            }

            const index: usize = @intCast(pos.y * self.size.x + pos.x);
            return &self.locDataArr.items[index];
        }

        /// Finds a path from start to goal and appends the path locations to the provided path
        /// list. The path will be from start to goal order.  If no path can be found, the path
        /// list will be left with just the start location.
        pub fn findPath(self: *Self, start: TileLoc, goal: TileLoc, path: *Path) !void {
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
