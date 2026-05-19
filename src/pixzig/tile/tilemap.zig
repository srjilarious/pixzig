const std = @import("std");
const xml = @import("xml");

const common = @import("../common.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;

const MaxFilesize = 1024 * 1024 * 1024;

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

    /// Initializes a tile from an XML element in the tileset.  This will add
    /// any properties defined on the tile in the tileset XML and set the core
    /// properties based on the "blocks" and "kills" properties defined in the XML.
    pub fn initFromElement(alloc: std.mem.Allocator, node: *xml.Element) !Tile {
        var tile = try Tile.init(alloc);

        if (!std.mem.eql(u8, node.tag, "tile")) return error.BadNodeTag;
        const propsNode = node.findChildByTag("properties").?;

        var propsChildren = propsNode.elements();
        while (propsChildren.next()) |prop| {
            const name = prop.getAttribute("name").?;
            const value = prop.getAttribute("value").?;
            try tile.addProperty(name, value);
        }

        return tile;
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

fn intFromFloatAttr(node: *xml.Element, attr: []const u8) !i32 {
    const str = node.getAttribute(attr);
    if (str == null) return error.NoAttribute;

    const f = try std.fmt.parseFloat(f32, str.?);
    const val: i32 = @intFromFloat(f);
    return val;
}

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

    pub fn initFromElement(alloc: std.mem.Allocator, node: *xml.Element) !Self {
        var obj = try Object.init(alloc);

        if (!std.mem.eql(u8, node.tag, "object")) return error.BadNodeTag;

        obj.id = try std.fmt.parseInt(i32, node.getAttribute("id").?, 0);

        if (node.getAttribute("gid")) |gid| {
            obj.gid = try std.fmt.parseInt(i32, gid, 0);
        }

        obj.pos = .{
            .x = try intFromFloatAttr(node, "x"),
            .y = try intFromFloatAttr(node, "y"),
        };
        obj.size = .{
            .x = try intFromFloatAttr(node, "width"),
            .y = try intFromFloatAttr(node, "height"),
        };

        const classOpt = node.getAttribute("class");
        if (classOpt != null) {
            obj.class = try alloc.dupe(u8, classOpt.?);
        }
        // Also allow the variable to be called type
        else {
            const typeOpt = node.getAttribute("type");
            if (typeOpt != null) {
                obj.class = try alloc.dupe(u8, typeOpt.?);
            }
        }

        // Get any props from the object.
        const propsNodeOpt = node.findChildByTag("properties");

        if (propsNodeOpt) |propsNode| {
            var propsChildren = propsNode.elements();
            while (propsChildren.next()) |prop| {
                const name = prop.getAttribute("name").?;
                const value = prop.getAttribute("value").?;

                // Lazy init string/value property list.
                if (obj.properties == null) {
                    obj.properties = .empty;
                }

                const newProp: Property = .{
                    .name = try alloc.dupe(u8, name),
                    .value = try alloc.dupe(u8, value),
                };
                try obj.properties.?.append(alloc, newProp);
            }
        }

        return obj;
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

    pub fn initFromElement(alloc: std.mem.Allocator, node: *xml.Element) !TileSet {
        var tileset = try TileSet.init(alloc);

        if (!std.mem.eql(u8, node.tag, "tileset")) return error.BadNodeTag;

        const nameAttr = node.getAttribute("name");
        if (nameAttr != null) {
            tileset.name = try alloc.dupe(u8, nameAttr.?);
        }

        tileset.tileSize = .{ .x = try std.fmt.parseInt(i32, node.getAttribute("tilewidth").?, 0), .y = try std.fmt.parseInt(i32, node.getAttribute("tileheight").?, 0) };

        tileset.columns = try std.fmt.parseInt(i32, node.getAttribute("columns").?, 0);

        const tileCount = try std.fmt.parseInt(usize, node.getAttribute("tilecount").?, 0);
        const baseTile = Tile{ .core = Clear, .properties = null, .alloc = alloc };
        try tileset.tiles.appendNTimes(alloc, baseTile, tileCount);

        var children = node.elements();
        while (children.next()) |child| {
            if (std.mem.eql(u8, child.tag, "tile")) {
                const newTile = try Tile.initFromElement(alloc, child);
                const tileId = try std.fmt.parseInt(usize, child.getAttribute("id").?, 0);
                tileset.tiles.items[tileId] = newTile;
            } else if (std.mem.eql(u8, child.tag, "image")) {
                tileset.textureSize = .{ .x = try std.fmt.parseInt(i32, child.getAttribute("width").?, 0), .y = try std.fmt.parseInt(i32, child.getAttribute("height").?, 0) };
            } else {
                std.log.err("Unhandled tileset child: {s}\n", .{child.tag});
            }
        }

        return tileset;
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

    pub fn initFromElement(alloc: std.mem.Allocator, node: *xml.Element) !Self {
        var layer = try init(alloc);

        const nameAttr = node.getAttribute("name");
        if (nameAttr != null) {
            layer.name = try alloc.dupe(u8, nameAttr.?);
        }

        layer.id = try std.fmt.parseInt(i32, node.getAttribute("id").?, 0);

        var elems = node.elements();
        while (elems.next()) |elem| {
            if (std.mem.eql(u8, elem.tag, "properties")) {
                var props = elem.elements();
                while (props.next()) |prop| {
                    if (!std.mem.eql(u8, prop.tag, "property")) {
                        return error.UnexpectedElement;
                    }

                    const name = prop.getAttribute("name").?;
                    const value = prop.getAttribute("value").?;
                    const newProp: Property = .{
                        .name = try alloc.dupe(u8, name),
                        .value = try alloc.dupe(u8, value),
                    };

                    try layer.properties.append(alloc, newProp);
                }
            } else if (std.mem.eql(u8, elem.tag, "object")) {
                const newObj = try Object.initFromElement(alloc, elem);
                try layer.objects.append(alloc, newObj);
            }
        }

        return layer;
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

    /// Initializes a layer from an XML element in the tilemap.  This will read
    /// the tile data from the XML and set up the layer's tiles accordingly.
    /// It will also read any properties defined on the layer in the XML.
    pub fn initFromElement(alloc: std.mem.Allocator, node: *xml.Element) !TileLayer {
        var layer = try init(alloc);

        const nameAttr = node.getAttribute("name");
        if (nameAttr != null) {
            layer.name = try alloc.dupe(u8, nameAttr.?);
        }

        layer.size = .{ .x = try std.fmt.parseInt(i32, node.getAttribute("width").?, 0), .y = try std.fmt.parseInt(i32, node.getAttribute("height").?, 0) };

        const dataNode = node.findChildByTag("data").?;
        const encoding = dataNode.getAttribute("encoding").?;
        if (!std.mem.eql(u8, encoding, "csv")) return error.UnsupportedLayerEncoding;

        // Resize the layer to have space for all of our tile indices.
        try layer.tiles.resize(alloc, @intCast(layer.size.x * layer.size.y));

        const tileDataVal = node.getCharData("data").?;
        var it = std.mem.tokenizeAny(u8, tileDataVal, ",\n");
        var buffIdx: usize = 0;
        while (it.next()) |curr| {
            const idx = std.fmt.parseInt(i32, curr, 0) catch |err| {
                std.log.err("Unable to parse index: {s}: {}", .{ curr, err });
                continue;
            };

            layer.tiles.items[buffIdx] = idx - 1;
            buffIdx += 1;
        }

        // const propsNode = node.findChildByTag("properties").?;

        return layer;
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

    /// Initializes a tile map from a Tiled map file. This will read the XML
    /// from the file and set up the tilesets, layers, and object groups
    /// accordingly.
    ///
    /// We only support tile layers with comma-separated values for the tile
    /// data, and we only support tilesets that are defined in the same file
    /// (i.e. no external tilesets).
    ///
    /// We have special handling for the properties "blocks" and "kills" on
    /// tiles in tilesets, which are stored as bitflags in the Tile struct's
    /// `core` field for easy access during collision and game logic.
    ///
    /// The "blocks" property can be set to "left", "right", "top", "bottom",
    /// or "all" to indicate which sides of the tile should be considered
    /// solid for collision purposes.
    ///
    /// The "kills" property can be set to "true" to indicate that the tile
    /// should be considered deadly to the player.  Any other properties
    /// defined on tiles, layers, or objects will be stored as string key/value
    /// pairs in the `properties` field of the respective struct.
    pub fn initFromFile(filename: []const u8, alloc: std.mem.Allocator) !TileMap {
        const io = std.Io.Threaded.global_single_threaded.io();
        const fileContents = try std.Io.Dir.cwd().readFileAlloc(io, filename, alloc, .limited(MaxFilesize));
        defer alloc.free(fileContents);

        std.log.debug("Loaded tile map file contents.", .{});
        const doc = try xml.parse(alloc, fileContents);
        return initFromElement(doc.root, alloc);
    }

    /// Initializes a tile map from the root XML element of a Tiled map file.
    ///
    /// This is used by `initFromFile` after reading the file contents, but
    /// is also helpful for testing.
    pub fn initFromElement(node: *xml.Element, alloc: std.mem.Allocator) !TileMap {
        var map = try init(alloc);
        var elems = node.elements();
        while (elems.next()) |elem| {
            if (std.mem.eql(u8, elem.tag, "tileset")) {
                const newTileset = try TileSet.initFromElement(alloc, elem);
                std.log.debug("Loaded a tileset '{s}', with {} tiles, {}x{} tile size, {} columns\n", .{ newTileset.name.?, newTileset.tiles.items.len, newTileset.tileSize.x, newTileset.tileSize.y, newTileset.columns });

                try map.tilesets.append(alloc, newTileset);
            } else if (std.mem.eql(u8, elem.tag, "layer")) {
                const newLayer = try TileLayer.initFromElement(alloc, elem);
                std.log.debug("Loaded a tile layer: '{?s}'", .{newLayer.name});
                try map.layers.append(alloc, newLayer);
            } else if (std.mem.eql(u8, elem.tag, "objectgroup")) {
                const newObjGroup = try ObjectGroup.initFromElement(alloc, elem);
                std.log.debug("Loaded object group: '{?s}'", .{newObjGroup.name});
                try map.objectGroups.append(alloc, newObjGroup);
            }
        }

        if (map.tilesets.items.len == 0) {
            std.log.warn("No tileset found in map!\n", .{});
        }

        for (0..map.layers.items.len) |idx| {
            var layer = &map.layers.items[idx];

            if (layer.tileset == null) {
                layer.tileset = &map.tilesets.items[0];
                layer.tileSize = map.tilesets.items[0].tileSize;
            }
        }

        return map;
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
