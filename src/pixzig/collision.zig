const std = @import("std");
const common = @import("./common.zig");

const Vec2U = common.Vec2U;
const Vec2I = common.Vec2I;
const RectF = common.RectF;

/// A spatial hash grid for broad phase collision detection.  This is a fixed
/// size grid that divides the world into cells of a specified size.  Each
/// cell can hold a fixed number of objects.  Objects are inserted into the
/// grid based on their position and size, and can be queried for potential
/// collisions with other objects in the same or neighboring cells.
pub fn CollisionGrid(comptime T: type, comptime maxItemsPerCell: usize) type {
    return struct {
        const Self = @This();

        const GridList = std.ArrayList([maxItemsPerCell]?T);

        /// The 2D grid of cells. Each cell can hold a fixed number of objects
        /// (maxItemsPerCell).
        grid: GridList,

        /// The size of the grid in terms of number of cells in x and y
        /// directions.
        gridSize: Vec2U,

        /// The total extent of the grid in pixels. This is calculated as
        /// gridSize * cellSize and is used for bounds checking when inserting
        /// or querying objects.
        gridExtent: Vec2U,

        /// The size of each cell in pixels. This determines how the world
        /// is divided into cells and how objects are mapped to cells based
        /// on their position and size.
        cellSize: Vec2U,
        alloc: std.mem.Allocator,

        /// Initializes the collision grid with the specified grid size and
        /// cell size. The grid size is the number of cells in the x and y
        /// directions, and the cell size is the size of each cell in pixels.
        /// The total extent of the grid in pixels is calculated as gridSize *
        /// cellSize. The grid is initialized with null values, indicating that
        /// there are no objects in any cells.
        pub fn init(alloc: std.mem.Allocator, gridSize: Vec2U, cellSize: Vec2U) !Self {
            var grid: GridList = .empty;
            const gridLen = gridSize.x * gridSize.y;
            try grid.resize(alloc, gridLen);
            for (0..gridLen) |idx| {
                for (0..maxItemsPerCell) |subIdx| {
                    grid.items[idx][subIdx] = null;
                }
            }

            std.debug.print("Initializing collision grid: {} x {} cells, cell size {} x {}, extent {} x {}\n", .{ gridSize.x, gridSize.y, cellSize.x, cellSize.y, gridSize.x * cellSize.x, gridSize.y * cellSize.y });

            return .{
                .grid = grid,
                .gridSize = gridSize,
                .gridExtent = .{ .x = gridSize.x * cellSize.x, .y = gridSize.y * cellSize.y },
                .cellSize = cellSize,
                .alloc = alloc,
            };
        }

        /// Deinitializes the collision grid by deinitializing the internal
        /// grid list.
        pub fn deinit(self: *Self) void {
            self.grid.deinit(self.alloc);
        }

        /// Resizes the collision grid to the new specified grid size. This
        /// will change the number of cells in the grid and the total extent
        /// of the grid in pixels. The contents of the grid are not preserved
        /// during resizing, so it is recommended to clear and reinsert
        /// objects after resizing.
        pub fn resize(self: *Self, sz: Vec2U) !void {
            std.debug.print("** Resizing collision grid to {} x {}\n", .{ sz.x, sz.y });
            self.gridSize = sz;
            // TODO: Handle copying contents into resized grid.
            try self.grid.resize(self.alloc, sz.x * sz.y);
        }

        /// Clears all objects from the collision grid by setting all cells to
        /// null.
        pub fn reset(self: *Self) void {
            const gridLen = self.gridSize.x * self.gridSize.y;
            for (0..gridLen) |idx| {
                for (0..maxItemsPerCell) |subIdx| {
                    self.grid.items[idx][subIdx] = null;
                }
            }
        }

        /// Inserts an object into the collision grid based on its pixel position.
        pub fn insert(self: *Self, pixelPos: Vec2U, obj: T) !void {
            const cx: usize = @as(usize, @intCast(pixelPos.x)) / self.cellSize.x;
            const cy: usize = @as(usize, @intCast(pixelPos.y)) / self.cellSize.y;
            const idx: usize = cy * self.gridSize.x + cx;
            var items = &self.grid.items[idx];

            for (0..items.len) |itIdx| {
                if (items[itIdx] == null) {
                    items[itIdx] = obj;
                    // std.debug.print("Inserted object {} at cell ({}, {}) idx {} at items[{}]\n", .{ obj, cx, cy, idx, itIdx });

                    return;
                }
            }

            return error.NoMoreSpace;
        }

        /// Inserts an object into the collision grid based on its bounding
        /// rectangle.
        pub fn insertRect(self: *Self, bounds: RectF, obj: T) !void {
            const cx: usize = @as(usize, @intFromFloat(bounds.l)) / self.cellSize.x;
            const cy: usize = @as(usize, @intFromFloat(bounds.t)) / self.cellSize.y;
            const nx: usize = (@as(usize, @intFromFloat(bounds.width())) + self.cellSize.x - 1) / self.cellSize.x;
            const ny: usize = (@as(usize, @intFromFloat(bounds.height())) + self.cellSize.y - 1) / self.cellSize.y;

            for (cy..cy + ny) |y| {
                if (y < 0) continue;
                if (y >= self.gridSize.y) break;

                for (cx..cx + nx) |x| {
                    if (x < 0) continue;
                    if (x >= self.gridSize.x) break;

                    // Go through the current cell's list and find a spot for the object.
                    const idx: usize = y * self.gridSize.x + x;
                    var items = &self.grid.items[idx];
                    var placed: bool = false;
                    for (0..items.len) |itIdx| {
                        if (items[itIdx] == null) {
                            items[itIdx] = obj;
                            placed = true;
                            break;
                        }
                    }

                    if (!placed) {
                        return error.NoMoreSpace;
                    }
                }
            }
        }

        /// Removes an object from the collision grid based on its pixel
        /// position.
        pub fn removePoint(self: *Self, pixelPos: Vec2I, obj: T) !usize {
            if (pixelPos.x < 0 or @as(usize, @intCast(pixelPos.x)) >= self.gridExtent.x) {
                return 0;
            }

            if (pixelPos.y < 0 or @as(usize, @intCast(pixelPos.y)) >= self.gridExtent.y) {
                return 0;
            }

            const cx: usize = @as(usize, @intCast(pixelPos.x)) / self.cellSize.x;
            const cy: usize = @as(usize, @intCast(pixelPos.y)) / self.cellSize.y;
            const idx: usize = cy * self.gridSize.x + cx;
            var items = &self.grid.items[idx];

            // std.debug.print("Trying to remove object {} at cell ({}, {}) idx {}\n", .{ obj, cx, cy, idx });

            var cellsRemoved: usize = 0;
            for (0..items.len) |itIdx| {
                // std.debug.print("Checking item at idx {}: {?}\n", .{ itIdx, items[itIdx] });
                if (items[itIdx] == obj) {
                    cellsRemoved += 1;
                    items[itIdx] = null;

                    // Swap this cell's null with the last non-null item to fill it in.
                    // First find the last non-null item.
                    var swapIdx: usize = itIdx + 1;
                    while (swapIdx < items.len) {
                        if (items[swapIdx] == null) {
                            break;
                        }

                        swapIdx += 1;
                    }

                    // Move back one from the last null item.  We'll make sure it's not the itIdx still.
                    swapIdx -= 1;

                    // Do the swap
                    if (swapIdx < items.len and swapIdx != itIdx) {
                        items[itIdx] = items[swapIdx];
                        items[swapIdx] = null;
                    }

                    break;
                }
            }

            return cellsRemoved;
        }

        /// Removes an object from the collision grid based on its bounding
        /// rectangle.
        pub fn removeRect(self: *Self, bounds: RectF, obj: T) !usize {
            var cellsRemoved: usize = 0;
            const cx: usize = @as(usize, @intFromFloat(bounds.l)) / self.cellSize.x;
            const cy: usize = @as(usize, @intFromFloat(bounds.t)) / self.cellSize.y;
            const nx: usize = (@as(usize, @intFromFloat(bounds.width())) + self.cellSize.x - 1) / self.cellSize.x;
            const ny: usize = (@as(usize, @intFromFloat(bounds.height())) + self.cellSize.y - 1) / self.cellSize.y;

            for (cy..cy + ny) |y| {
                if (y < 0) continue;
                if (y >= self.gridSize.y) break;

                for (cx..cx + nx) |x| {
                    if (x < 0) continue;
                    if (x >= self.gridSize.x) break;

                    // Go through the current cell's list and find a spot for the object.
                    const idx: usize = y * self.gridSize.x + x;
                    var items = &self.grid.items[idx];
                    for (0..items.len) |itIdx| {
                        if (items[itIdx] == obj) {
                            cellsRemoved += 1;
                            items[itIdx] = null;

                            // Swap this cell's null with the last non-null item to fill it in.
                            // First find the last non-null item.
                            var swapIdx: usize = itIdx + 1;
                            while (swapIdx < items.len) {
                                if (items[swapIdx] == null) {
                                    break;
                                }

                                swapIdx += 1;
                            }

                            // Move back one from the last null item.  We'll make sure it's not the itIdx still.
                            swapIdx -= 1;

                            // Do the swap
                            if (swapIdx < items.len and swapIdx != itIdx) {
                                items[itIdx] = items[swapIdx];
                                items[swapIdx] = null;
                            }

                            break;
                        }
                    }
                }
            }

            return cellsRemoved;
        }

        /// Checks for collisions at a point in the grid and returns a list of
        /// objects that are in the cell at that point.
        ///
        /// The list is returned through the outList parameter and the function
        /// returns the number of objects found.
        pub fn checkPoint(self: *Self, pixelPos: Vec2I, outList: *const []?T) !usize {
            if ((pixelPos.x < 0) or (@as(usize, @intCast(pixelPos.x)) >= self.gridExtent.x)) {
                // std.debug.print("pos = {}\n", .{pixelPos.x});
                return 0;
            }

            if ((pixelPos.y < 0) or (@as(usize, @intCast(pixelPos.y)) >= self.gridExtent.y)) {
                return 0;
            }

            const cx: usize = @as(usize, @intCast(pixelPos.x)) / self.cellSize.x;
            const cy: usize = @as(usize, @intCast(pixelPos.y)) / self.cellSize.y;
            const idx: usize = cy * self.gridSize.x + cx;
            const items = &self.grid.items[idx];

            var numFound: usize = 0;
            for (0..items.len) |itIdx| {
                if (items[itIdx] == null) break;

                outList.*[itIdx] = items[itIdx];
                numFound += 1;
            }

            // null the rest of the list
            for (0..maxItemsPerCell - numFound) |i| {
                outList.*[numFound + i] = null;
            }

            return numFound;
        }

        /// Checks for collisions along a horizontal line from (cxStart, cy)
        /// to (cxEnd, cy) and returns a list of objects that
        /// are in the cells along that line.
        ///
        /// The list is returned through the outList parameter and the function
        /// returns the number of objects found.
        pub fn checkHorz(self: *Self, cxStart: i32, cxEnd: i32, cy: i32, outList: *const []?T) !usize {

            // Check bounds
            if (cy < 0 or cy >= @as(i32, @intCast(self.gridSize.y))) {
                return 0;
            }

            if (cxEnd < 0 or cxStart >= @as(i32, @intCast(self.gridSize.x))) {
                return 0;
            }

            var cxS = cxStart;
            var cxE = cxEnd;
            if (cxStart < 0) {
                cxS = 0;
            }

            if (cxEnd >= @as(i32, @intCast(self.gridSize.x))) {
                cxE = @as(i32, @intCast(self.gridSize.x)) - 1;
            }

            var baseIdx: usize = 0;
            var numFound: usize = 0;
            const cxStartU: usize = @intCast(cxS);
            const cxEndU: usize = @intCast(cxE);
            const cyU: usize = @intCast(cy);
            for (cxStartU..cxEndU + 1) |cx| {
                const idx: usize = cyU * self.gridSize.x + cx;
                const items = &self.grid.items[idx];

                var subNumFound: usize = 0;
                for (0..items.len) |itIdx| {
                    if (items[itIdx] == null) break;

                    var itemFound: bool = false;
                    for (0..baseIdx) |olIdx| {
                        if (outList.*[olIdx] == items[itIdx]) {
                            itemFound = true;
                            break;
                        }
                    }
                    if (!itemFound) {
                        if (baseIdx + itIdx >= outList.len) {
                            return error.NoMoreSpace;
                        }

                        outList.*[baseIdx + subNumFound] = items[itIdx];
                        subNumFound += 1;
                    }
                }

                numFound += subNumFound;
                baseIdx += subNumFound;
            }

            // Null out remaining part of hit list.
            for (numFound..outList.len) |idx| {
                outList.*[idx] = null;
            }

            return numFound;
        }

        /// Checks for potential collisions along a vertical line from (cx, cyStart)
        /// to (cx, cyEnd).
        ///
        /// It returns a list of objects that are in the cells along that line
        /// in the outList param. The function returns the number of objects found.
        pub fn checkVert(self: *Self, cx: i32, cyStart: i32, cyEnd: i32, outList: *const []?T) !usize {
            var baseIdx: usize = 0;
            var numFound: usize = 0;

            var cyS = cyStart;
            var cyE = cyEnd;

            // Check bounds
            if (cx < 0 or cx >= @as(i32, @intCast(self.gridSize.x))) {
                return 0;
            }

            if (cyEnd < 0 or cyStart >= @as(i32, @intCast(self.gridSize.y))) {
                return 0;
            }

            if (cyStart < 0) {
                cyS = 0;
            }

            if (cyEnd >= @as(i32, @intCast(self.gridSize.y))) {
                cyE = @as(i32, @intCast(self.gridSize.y)) - 1;
            }

            const cyStartU: usize = @intCast(cyS);
            const cyEndU: usize = @intCast(cyE);
            const cxU: usize = @intCast(cx);
            for (cyStartU..cyEndU + 1) |cy| {
                const idx: usize = cy * self.gridSize.x + cxU;
                const items = &self.grid.items[idx];

                var subNumFound: usize = 0;
                for (0..items.len) |itIdx| {
                    if (items[itIdx] == null) break;

                    var itemFound: bool = false;
                    for (0..baseIdx) |olIdx| {
                        if (outList.*[olIdx] == items[itIdx]) {
                            itemFound = true;
                            break;
                        }
                    }
                    if (!itemFound) {
                        if (baseIdx + itIdx >= outList.len) {
                            return error.NoMoreSpace;
                        }

                        outList.*[baseIdx + subNumFound] = items[itIdx];
                        subNumFound += 1;
                    }
                }

                numFound += subNumFound;
                baseIdx += subNumFound;
            }

            // Null out remaining part of hit list.
            for (numFound..outList.len) |idx| {
                outList.*[idx] = null;
            }

            return numFound;
        }

        /// Checks for potential collisions along the left line from (objRect.l,
        /// objRect.t) to (objRect.l, objRect.b) and returns a list of objects
        /// that are in the cells along that line in the outList param. The
        /// function returns the number of objects found.
        pub fn checkLeft(self: *Self, objRect: *const RectF, outList: *const []?T) !usize {
            const left: i32 = @intFromFloat(objRect.l);
            const top: i32 = @as(i32, @intFromFloat(objRect.t)) + 1;
            const bottom: i32 = @as(i32, @intFromFloat(objRect.b)) - 1;

            const leftTileX = @divTrunc(left, @as(i32, @intCast(self.cellSize.x)));
            const tyStart = @divTrunc(top, @as(i32, @intCast(self.cellSize.y)));
            const tyEnd = @divTrunc(bottom, @as(i32, @intCast(self.cellSize.y)));

            return self.checkVert(leftTileX, tyStart, tyEnd, outList);
        }

        /// Checks for potential collisions along the right line from (objRect.r,
        /// objRect.t) to (objRect.r, objRect.b) and returns a list of objects
        /// that are in the cells along that line in the outList param. The
        /// function returns the number of objects found.
        pub fn checkRight(self: *Self, objRect: *const RectF, outList: *const []?T) !usize {
            const right: i32 = @intFromFloat(objRect.r);
            const top: i32 = @as(i32, @intFromFloat(objRect.t)) + 1;
            const bottom: i32 = @as(i32, @intFromFloat(objRect.b)) - 1;

            const rightTileX = @divTrunc(right, @as(i32, @intCast(self.cellSize.x)));
            const tyStart = @divTrunc(top, @as(i32, @intCast(self.cellSize.y)));
            const tyEnd = @divTrunc(bottom, @as(i32, @intCast(self.cellSize.y)));

            return self.checkVert(rightTileX, tyStart, tyEnd, outList);
        }

        /// Checks for potential collisions along the top line from (objRect.l,
        /// objRect.t) to (objRect.r, objRect.t) and returns a list of objects
        /// that are in the cells along that line in the outList param. The
        /// function returns the number of objects found.
        pub fn checkUp(self: *Self, objRect: *const RectF, outList: *const []?T) !usize {
            const top: i32 = @intFromFloat(objRect.t);
            const left: i32 = @as(i32, @intFromFloat(objRect.l)) + 1;
            const right: i32 = @as(i32, @intFromFloat(objRect.r)) - 1;

            const topTileY = @divTrunc(top, @as(i32, @intCast(self.cellSize.y)));
            const txStart = @divTrunc(left, @as(i32, @intCast(self.cellSize.x)));
            const txEnd = @divTrunc(right, @as(i32, @intCast(self.cellSize.x)));

            return self.checkHorz(txStart, txEnd, topTileY, outList);
        }

        /// Checks for potential collisions along the bottom line from (objRect.l,
        /// objRect.b) to (objRect.r, objRect.b) and returns a list of objects
        /// that are in the cells along that line in the outList param. The
        /// function returns the number of objects found.
        pub fn checkDown(self: *Self, objRect: *const RectF, outList: *const []?T) !usize {
            const bottom: i32 = @intFromFloat(objRect.b);
            const left: i32 = @as(i32, @intFromFloat(objRect.l)) + 1;
            const right: i32 = @as(i32, @intFromFloat(objRect.r)) - 1;

            const bottomTileY = @divTrunc(bottom, @as(i32, @intCast(self.cellSize.y)));
            const txStart = @divTrunc(left, @as(i32, @intCast(self.cellSize.x)));
            const txEnd = @divTrunc(right, @as(i32, @intCast(self.cellSize.x)));

            return self.checkHorz(txStart, txEnd, bottomTileY, outList);
        }
    };
}
