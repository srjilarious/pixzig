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

        /// The total extent of the grid in pixels, calculated as gridSize *
        /// cellSize at `init` time. Not currently read by `insert`/`insertRect`/
        /// `removeRect` for bounds checking, and not updated by `resize` — treat
        /// it as informational only until that is fixed.
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

            std.log.debug("Initializing collision grid: {} x {} cells, cell size {} x {}, extent {} x {}\n", .{ gridSize.x, gridSize.y, cellSize.x, cellSize.y, gridSize.x * cellSize.x, gridSize.y * cellSize.y });

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
        /// changes the number of cells in the grid, but does **not** update
        /// `gridExtent` and does not preserve, migrate, or clear existing
        /// cell contents (known gap — see the engine review doc). Call
        /// `reset()` after resizing to put the grid back into a known state
        /// before inserting.
        pub fn resize(self: *Self, sz: Vec2U) !void {
            std.log.debug("** Resizing collision grid to {} x {}\n", .{ sz.x, sz.y });
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
        /// Does not bounds-check `pixelPos` against the grid extent first —
        /// a position outside the grid indexes out of bounds rather than
        /// returning an error. Callers must keep `pixelPos` within
        /// `gridSize * cellSize` themselves.
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

        /// Inclusive range of cells a rectangle overlaps, clamped to the grid.
        const CellRange = struct { x0: usize, x1: usize, y0: usize, y1: usize };

        /// Returns the cells `bounds` overlaps, clamped to the grid, or null
        /// when it lies entirely outside. The right/bottom edges are
        /// exclusive, so a rect ending exactly on a cell boundary doesn't
        /// spill into the next cell, but one straddling a boundary covers
        /// both cells.
        fn cellRange(self: *const Self, bounds: RectF) ?CellRange {
            const x = axisCells(bounds.l, bounds.r, self.cellSize.x, self.gridSize.x) orelse return null;
            const y = axisCells(bounds.t, bounds.b, self.cellSize.y, self.gridSize.y) orelse return null;
            return .{ .x0 = x[0], .x1 = x[1], .y0 = y[0], .y1 = y[1] };
        }

        /// First and last cell (inclusive) the span [lo, hi) covers along
        /// one axis, clamped to [0, numCells). A zero-width span still
        /// covers the cell it sits in.
        fn axisCells(lo: f32, hi: f32, cellSize: u32, numCells: u32) ?[2]usize {
            if (numCells == 0) return null;
            const cs: f32 = @floatFromInt(cellSize);
            const first = @floor(lo / cs);
            const last = @max(first, @ceil(hi / cs) - 1);
            const maxCell: f32 = @floatFromInt(numCells - 1);
            if (last < 0 or first > maxCell) return null;
            return .{ @intFromFloat(@max(first, 0)), @intFromFloat(@min(last, maxCell)) };
        }

        /// Removes the first `obj` from one cell, moving the cell's last item
        /// into the hole so occupied slots stay contiguous. Returns whether
        /// it was found.
        fn removeFromCell(items: *[maxItemsPerCell]?T, obj: T) bool {
            for (0..items.len) |itIdx| {
                if (items[itIdx] != obj) continue;

                // Find the last non-null item after this one.
                var lastIdx = itIdx;
                while (lastIdx + 1 < items.len and items[lastIdx + 1] != null) {
                    lastIdx += 1;
                }

                items[itIdx] = items[lastIdx];
                items[lastIdx] = null;
                return true;
            }
            return false;
        }

        /// Inserts an object into the collision grid based on its bounding
        /// rectangle, covering every cell the rectangle overlaps. Parts of
        /// the rectangle outside the grid are ignored.
        pub fn insertRect(self: *Self, bounds: RectF, obj: T) !void {
            const range = self.cellRange(bounds) orelse return;

            for (range.y0..range.y1 + 1) |y| {
                for (range.x0..range.x1 + 1) |x| {
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
            return if (removeFromCell(&self.grid.items[idx], obj)) 1 else 0;
        }

        /// Removes an object from the collision grid based on its bounding
        /// rectangle. Pass the same bounds it was inserted with.
        pub fn removeRect(self: *Self, bounds: RectF, obj: T) !usize {
            const range = self.cellRange(bounds) orelse return 0;

            var cellsRemoved: usize = 0;
            for (range.y0..range.y1 + 1) |y| {
                for (range.x0..range.x1 + 1) |x| {
                    const idx: usize = y * self.gridSize.x + x;
                    if (removeFromCell(&self.grid.items[idx], obj)) {
                        cellsRemoved += 1;
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
                        if (baseIdx + subNumFound >= outList.len) {
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
                        if (baseIdx + subNumFound >= outList.len) {
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
