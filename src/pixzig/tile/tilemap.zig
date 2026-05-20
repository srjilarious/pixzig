const std = @import("std");
const xml = @import("xml");

const common = @import("../common.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;

const CoreTileProperty = u32;
pub const Clear: u32 = 0x0;
pub const BlocksLeft: u32 = 0x1;
pub const BlocksTop: u32 = 0x2;
pub const BlocksRight: u32 = 0x4;
pub const BlocksBottom: u32 = 0x8;
pub const BlocksAll: u32 = 0x0f;
pub const Kills: u32 = 0x10;
pub const UserPropsStart: u32 = 0x20;

/// A string key/value pair used on objects, tiles, and layers for custom properties.
pub const Property = struct {
    name: []const u8,
    value: []const u8,
};

pub const PropertyList = std.ArrayList(Property);

/// A tile in a tileset, with its custom properties and a bitmask for core tile
///  properties the engine handles.
pub const Tile = struct {
    core: CoreTileProperty,
    properties: ?PropertyList,
    alloc: std.mem.Allocator,

    /// Initializes a tile with no properties and the Clear core property.
    pub fn init(alloc: std.mem.Allocator) !Tile {
        return .{ .core = Clear, .properties = null, .alloc = alloc };
    }

    /// Adds a property to the tile.  This can be used for custom properties,
    /// but also handles the "blocks" and "kills" properties that set core
    /// engine behavior.
    pub fn addProperty(self: *Tile, name: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, name, "blocks")) {
            if (std.mem.eql(u8, value, "left")) {
                self.core |= BlocksLeft;
            } else if (std.mem.eql(u8, value, "right")) {
                self.core |= BlocksRight;
            } else if (std.mem.eql(u8, value, "top")) {
                self.core |= BlocksTop;
            } else if (std.mem.eql(u8, value, "bottom")) {
                self.core |= BlocksBottom;
            } else if (std.mem.eql(u8, value, "all")) {
                self.core |= BlocksAll;
            }
        } else if (std.mem.eql(u8, name, "kills")) {
            if (std.mem.eql(u8, value, "true")) {
                self.core |= Kills;
            }
        } else {
            // Lazy init string/value property list.
            if (self.properties == null) {
                self.properties = .empty;
            }

            const newName = try self.alloc.dupe(u8, name);
            const newValue = try self.alloc.dupe(u8, value);
            const newProp: Property = .{ .name = newName, .value = newValue };
            try self.properties.?.append(self.alloc, newProp);
        }
    }

    /// Deinitializes the tile, freeing any allocated properties.
    pub fn deinit(self: *Tile) void {
        if (self.properties != null) {
            for (0..self.properties.?.items.len) |idx| {
                const prop = self.properties.?.items[idx];
                self.alloc.free(prop.name);
                self.alloc.free(prop.value);
            }
            self.properties.?.deinit(self.alloc);
        }
    }
};

/// A Tiled "object", with name, position, size, class and custom properties.
pub const Object = struct {
    alloc: std.mem.Allocator,
    id: i32 = -1,
    gid: i32 = -1,
    pos: Vec2I = .{ .x = -1, .y = -1 },
    size: Vec2I = .{ .x = 0, .y = 0 },
    name: ?[]const u8 = null,
    class: ?[]const u8 = null,
    properties: ?PropertyList = null,

    const Self = @This();

    /// Initializes an empty object with no name, class, or properties.
    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{ .alloc = alloc };
    }

    pub fn intPropWithDefault(self: *const Self, name: []const u8, default: i32) i32 {
        if (self.properties != null) {
            for (0..self.properties.?.items.len) |idx| {
                const prop = &self.properties.?.items[idx];
                if (std.mem.eql(u8, prop.name, name)) {
                    return std.fmt.parseInt(i32, prop.value, 0) orelse default;
                }
            }
        }

        return default;
    }

    pub fn intProp(self: *const Self, name: []const u8) !i32 {
        if (self.properties == null) return error.NoProperties;

        for (0..self.properties.?.items.len) |idx| {
            const prop = &self.properties.?.items[idx];
            if (std.mem.eql(u8, prop.name, name)) {
                return std.fmt.parseInt(i32, prop.value, 0) catch {
                    return error.BadPropertyFormat;
                };
            }
        }

        return error.PropertyNotFound;
    }

    /// Gets a string property from the object.  Returns an error if the
    /// property doesn't exist or if there are no properties on the object.
    pub fn stringProp(self: *const Self, name: []const u8) ![]const u8 {
        if (self.properties == null) return error.NoProperties;

        for (0..self.properties.?.items.len) |idx| {
            const prop = &self.properties.?.items[idx];
            if (std.mem.eql(u8, prop.name, name)) {
                return prop.value;
            }
        }

        return error.PropertyNotFound;
    }

    /// Deinitializes the tile, freeing any allocated properties.
    pub fn deinit(self: *Self) void {
        if (self.name != null) {
            self.alloc.free(self.name.?);
        }

        if (self.class != null) {
            self.alloc.free(self.class.?);
        }

        if (self.properties != null) {
            for (0..self.properties.?.items.len) |idx| {
                const prop = &self.properties.?.items[idx];
                self.alloc.free(prop.name);
                self.alloc.free(prop.value);
            }

            self.properties.?.deinit(self.alloc);
        }
    }
};

/// A collection of tiles with information about the size of the tiles and the
/// source texture.
pub const TileSet = struct {
    //tileTexture: *Texture,

    tiles: std.ArrayList(Tile),
    tileSize: Vec2I,
    textureSize: Vec2I,
    columns: i32,
    name: ?[]const u8,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !TileSet {
        return .{
            .tiles = .empty,
            .tileSize = .{ .x = 0, .y = 0 },
            .textureSize = .{ .x = 0, .y = 0 },
            .columns = 0,
            .name = null,
            .alloc = alloc,
        };
    }

    pub fn initEmpty(alloc: std.mem.Allocator, tileSize: Vec2I, textureSize: Vec2I, tileCount: usize) !TileSet {
        var tiles: std.ArrayList(Tile) = .empty;
        const baseTile = Tile{ .core = Clear, .properties = null, .alloc = alloc };
        try tiles.appendNTimes(alloc, baseTile, tileCount);

        return .{
            .tiles = tiles,
            .tileSize = tileSize,
            .textureSize = textureSize,
            .columns = @divFloor(textureSize.x, tileSize.x),
            .name = null,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *TileSet) void {
        if (self.name != null) {
            self.alloc.free(self.name.?);
        }

        for (0..self.tiles.items.len) |idx| {
            self.tiles.items[idx].deinit();
        }

        self.tiles.deinit(self.alloc);
    }

    pub fn tile(self: *TileSet, idx: usize) ?*Tile {
        if (idx > self.tiles.items.len) return null;

        return &self.tiles.items[idx];
    }

    const TileSetIterator = struct {
        parent: *const TileSet,
        class: ?[]const u8 = null,
        index: usize = 0,

        pub fn init(parent: *const TileSet) TileSetIterator {
            return .{ .parent = parent };
        }

        pub fn next(self: *TileSetIterator) ?*Tile {
            while (self.index < self.parent.tiles.items.len) {
                const currItem = &self.parent.tiles.items[self.index];

                // Case where we aren't filtering by class name.
                self.index += 1;
                return currItem;
            }

            return null;
        }
    };

    pub fn iterator(self: *const TileSet) TileSetIterator {
        return TileSetIterator.init(self);
    }
};

pub const ObjectGroup = struct {
    objects: std.ArrayList(Object),
    properties: PropertyList,
    id: i32,
    name: ?[]const u8,
    alloc: std.mem.Allocator,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{ .objects = .empty, .properties = .empty, .id = 0, .name = null, .alloc = alloc };
    }

    pub fn deinit(self: *Self) void {
        if (self.name != null) {
            self.alloc.free(self.name.?);
            self.name = null;
        }

        for (0..self.objects.items.len) |idx| {
            const obj = &self.objects.items[idx];
            obj.deinit();
        }
        self.objects.deinit(self.alloc);

        for (0..self.properties.items.len) |idx| {
            const prop = &self.properties.items[idx];
            self.alloc.free(prop.name);
            self.alloc.free(prop.value);
        }

        self.properties.deinit(self.alloc);
    }

    const ObjectGroupIterator = struct {
        parent: *const ObjectGroup,
        class: ?[]const u8 = null,
        index: usize = 0,

        pub fn init(parent: *const ObjectGroup, class: ?[]const u8) ObjectGroupIterator {
            return .{ .parent = parent, .class = class };
        }

        pub fn next(self: *ObjectGroupIterator) ?*Object {
            while (self.index < self.parent.objects.items.len) {
                const currItem = &self.parent.objects.items[self.index];

                // Handle the iterator filtering by class name.
                if (self.class) |classStr| {
                    if (currItem.class) |itemClassStr| {
                        if (std.mem.eql(u8, classStr, itemClassStr)) {
                            self.index += 1;
                            return currItem;
                        } else {
                            self.index += 1;
                        }
                    } else {
                        self.index += 1;
                    }
                } else {
                    // Case where we aren't filtering by class name.
                    self.index += 1;
                    return currItem;
                }
            }

            return null;
        }
    };

    pub fn iterator(self: *const ObjectGroup, class: ?[]const u8) ObjectGroupIterator {
        return ObjectGroupIterator.init(self, class);
    }

    pub fn firstByClass(self: *const ObjectGroup, class: []const u8) ?*Object {
        for (0..self.objects.items.len) |idx| {
            const curr = &self.objects.items[idx];
            if (curr.class != null and std.mem.eql(u8, curr.class.?, class)) {
                return &self.objects.items[idx];
            }
        }

        return null;
    }

    // pub fn dumpLayer(self: *const Self) void {
    //     for(0..@intCast(self.size.y)) |yy| {
    //         for(0..@intCast(self.size.x)) |xx| {
    //             std.debug.print("{} ", .{self.tileData(@intCast(xx), @intCast(yy))});
    //         }
    //         std.debug.print("\n", .{});
    //     }
    // }
};

/// A layer of tiles in a tilemap.
pub const TileLayer = struct {
    /// The tile indices for the layer, stored in row-major order.  A value
    /// of -1 means no tile.
    tiles: std.ArrayList(i32),

    /// Custom properties defined on the layer.
    properties: PropertyList,

    /// The size of the layer in tiles.
    size: Vec2I,

    /// The name of the layer, if it has one.
    name: ?[]const u8,

    /// The tileset this layer uses, if it has one.  This is used for looking up
    /// tile information like collision properties.
    tileset: ?*TileSet,

    /// The size of the tiles in this layer.  This is used for calculating
    /// source rectangles when rendering the layer.
    tileSize: Vec2I,

    /// Whether the layer has been modified since it was loaded or last
    /// rendered.  This can be used to optimize rendering by only
    /// re-uploading the tile data to the GPU when it has changed.
    isDirty: bool,

    /// Allocator used for any allocations on the layer, such as the tile data.
    alloc: std.mem.Allocator,

    /// Initializes an empty layer with no tiles, properties, or name.
    pub fn init(alloc: std.mem.Allocator) !TileLayer {
        return .{
            .tiles = .empty,
            .properties = .empty,
            .size = .{ .x = 0, .y = 0 },
            .name = null,
            .tileset = null,
            .tileSize = .{ .x = 0, .y = 0 },
            .isDirty = false,
            .alloc = alloc,
        };
    }

    /// Initializes a layer with the given size and tile size, with all tiles
    /// set to -1.
    pub fn initEmpty(alloc: std.mem.Allocator, size: Vec2I, tileSize: Vec2I) !TileLayer {
        var tilesArr: std.ArrayList(i32) = .empty;
        try tilesArr.appendNTimes(alloc, -1, @intCast(size.x * size.y));
        return .{
            .tiles = tilesArr,
            .properties = .empty,
            .size = size,
            .name = null,
            .tileset = null,
            .tileSize = tileSize,
            .isDirty = false,
            .alloc = alloc,
        };
    }

    /// Deinitializes the layer, freeing any allocated properties and tile data.
    pub fn deinit(self: *TileLayer) void {
        if (self.name != null) {
            self.alloc.free(self.name.?);
            self.name = null;
        }

        self.tiles.deinit(self.alloc);

        for (0..self.properties.items.len) |idx| {
            const prop = &self.properties.items[idx];
            self.alloc.free(prop.name);
            self.alloc.free(prop.value);
        }

        self.properties.deinit(self.alloc);

        self.tileset = null;
    }

    /// Gets a pointer to the tile set index at the given coordinates, it does
    /// no bounds checking.
    pub fn tileDataPtrUnchecked(self: *TileLayer, x: i32, y: i32) *i32 {
        return &self.tiles.items[self.tileIndex(x, y)];
    }

    /// Sets the tile set index at the given coordinates.  Does bounds checking
    /// and returns early if the coordinates are out of bounds.
    pub fn setTileData(self: *TileLayer, x: i32, y: i32, val: i32) void {
        if (x < 0 or x >= self.size.x) return;
        if (y < 0 or y >= self.size.y) return;

        self.tileDataPtrUnchecked(x, y).* = val;
    }

    /// Gets the tile set index at the given coordinates.  Does bounds checking
    /// and returns -1 if the coordinates are out of bounds.
    pub fn tileData(self: *const TileLayer, x: i32, y: i32) i32 {
        if (x < 0 or x >= self.size.x) return -1;
        if (y < 0 or y >= self.size.y) return -1;

        return self.tileDataUnchecked(x, y);
    }

    /// Gets the tile set index at the given coordinates with no bounds checking.
    pub fn tileDataUnchecked(self: *const TileLayer, x: i32, y: i32) i32 {
        return self.tiles.items[self.tileIndex(x, y)];
    }

    /// Gets the index into the tile data array for the given coordinates.
    /// Does not do any bounds checking, so the caller must ensure the
    /// coordinates are valid.
    pub fn tileIndex(self: *const TileLayer, x: i32, y: i32) usize {
        return @intCast(y * self.size.x + x);
    }

    /// Gets a pointer to the tile at the given coordinates, or null if there
    /// is no tileset for the layer, the coordinates are out of bounds or if
    /// there is no tile at those coordinates.
    pub fn tile(self: *const TileLayer, x: i32, y: i32) ?*Tile {
        if (self.tileset == null) return null;
        if (x < 0 or x >= self.size.x) return null;
        if (y < 0 or y >= self.size.y) return null;

        const tsVal = self.tileDataUnchecked(x, y);
        if (tsVal < 0) return null;

        const tsIdx: usize = @intCast(tsVal);
        return self.tileset.?.tile(tsIdx);
    }

    /// A debug function to print the tile indices for the layer to the console.
    pub fn dumpLayer(self: *const TileLayer) void {
        for (0..@intCast(self.size.y)) |yy| {
            for (0..@intCast(self.size.x)) |xx| {
                std.log.debug("{} ", .{self.tileData(@intCast(xx), @intCast(yy))});
            }
            std.log.debug("\n", .{});
        }
    }
};

/// The main tile map struct, containing all of the tilesets, layers, and
/// object groups for a tile map.
pub const TileMap = struct {
    tilesets: std.ArrayList(TileSet),
    layers: std.ArrayList(TileLayer),
    objectGroups: std.ArrayList(ObjectGroup),
    alloc: std.mem.Allocator,

    /// Initializes an empty tile map with no tilesets, layers, or object
    /// groups.
    pub fn init(alloc: std.mem.Allocator) !TileMap {
        return .{ .tilesets = .empty, .layers = .empty, .objectGroups = .empty, .alloc = alloc };
    }

    /// Gets a pointer to the layer at the given index, or null if the index
    /// is out of bounds.
    pub fn layerByIndex(self: *const TileMap, idx: usize) ?*TileLayer {
        if (idx >= self.layers.items.len) return null;
        return &self.layers.items[idx];
    }

    /// Gets a pointer to the object group at the given index, or null if the
    /// index is out of bounds.
    pub fn objectGroupByIndex(self: *const TileMap, idx: usize) ?*ObjectGroup {
        if (idx >= self.objectGroups.items.len) return null;
        return &self.objectGroups.items[idx];
    }

    /// Gets a pointer to the layer with the given name, or null if no layer has
    /// that name.
    pub fn layerByName(self: *const TileMap, name: []const u8) ?*TileLayer {
        for (0..self.layers.items.len) |idx| {
            const layer = &self.layers.items[idx];
            if (layer.name != null and std.mem.eql(u8, layer.name.?, name)) {
                return layer;
            }
        }
        return null;
    }

    /// Gets a pointer to the object group with the given name, or null if no
    /// object group has that name.
    pub fn objectGroupByName(self: *const TileMap, name: []const u8) ?*ObjectGroup {
        for (0..self.objectGroups.items.len) |idx| {
            const objGroup = &self.objectGroups.items[idx];
            if (objGroup.name != null and std.mem.eql(u8, objGroup.name.?, name)) {
                return objGroup;
            }
        }
        return null;
    }

    /// Deinitializes the tile map, freeing any allocated properties and tile
    /// data.
    pub fn deinit(self: *TileMap) void {
        for (0..self.tilesets.items.len) |idx| {
            self.tilesets.items[idx].deinit();
        }

        self.tilesets.deinit(self.alloc);

        for (0..self.layers.items.len) |idx| {
            self.layers.items[idx].deinit();
        }

        self.layers.deinit(self.alloc);

        for (0..self.objectGroups.items.len) |idx| {
            self.objectGroups.items[idx].deinit();
        }

        self.objectGroups.deinit(self.alloc);
    }
};
