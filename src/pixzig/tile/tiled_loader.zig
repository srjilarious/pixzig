const std = @import("std");
const xml = @import("xml");

const tilemap = @import("./tilemap.zig");

pub const Tile = tilemap.Tile;
pub const Property = tilemap.Property;
pub const Object = tilemap.Object;
pub const ObjectGroup = tilemap.ObjectGroup;
pub const TileLayer = tilemap.TileLayer;
pub const TileSet = tilemap.TileSet;
pub const TileMap = tilemap.TileMap;

pub const Clear = tilemap.Clear;

const MaxFilesize = 1024 * 1024 * 1024;

fn intFromFloatAttr(node: *xml.Element, attr: []const u8) !i32 {
    const str = node.getAttribute(attr);
    if (str == null) return error.NoAttribute;

    const f = try std.fmt.parseFloat(f32, str.?);
    const val: i32 = @intFromFloat(f);
    return val;
}

pub const TiledMapXmlLoader = struct {
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
        defer doc.deinit();
        return initFromElement(doc.root, alloc);
    }

    /// Initializes a tile map from the root XML element of a Tiled map file.
    ///
    /// This is used by `initFromFile` after reading the file contents, but
    /// is also helpful for testing.
    pub fn initFromElement(node: *xml.Element, alloc: std.mem.Allocator) !TileMap {
        var map = try TileMap.init(alloc);
        errdefer map.deinit();

        var elems = node.elements();
        while (elems.next()) |elem| {
            if (std.mem.eql(u8, elem.tag, "tileset")) {
                var newTileset = try initTileSetFromElement(alloc, elem);
                errdefer newTileset.deinit();

                std.log.debug("Loaded a tileset '{s}', with {} tiles, {}x{} tile size, {} columns\n", .{ newTileset.name.?, newTileset.tiles.items.len, newTileset.tileSize.x, newTileset.tileSize.y, newTileset.columns });

                try map.tilesets.append(alloc, newTileset);
            } else if (std.mem.eql(u8, elem.tag, "layer")) {
                var newLayer = try initTileLayerFromElement(alloc, elem);
                errdefer newLayer.deinit();

                std.log.debug("Loaded a tile layer: '{?s}'", .{newLayer.name});
                try map.layers.append(alloc, newLayer);
            } else if (std.mem.eql(u8, elem.tag, "objectgroup")) {
                var newObjGroup = try initObjectGroupFromElement(alloc, elem);
                errdefer newObjGroup.deinit();

                std.log.debug("Loaded object group: '{?s}'", .{newObjGroup.name});
                try map.objectGroups.append(alloc, newObjGroup);
            }
        }

        if (map.tilesets.items.len == 0) {
            std.log.err("No tileset found in map!\n", .{});
            return error.NoTileset;
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

    /// Initializes a layer from an XML element in the tilemap.  This will read
    /// the tile data from the XML and set up the layer's tiles accordingly.
    /// It will also read any properties defined on the layer in the XML.
    pub fn initTileLayerFromElement(alloc: std.mem.Allocator, node: *xml.Element) !TileLayer {
        var layer = try TileLayer.init(alloc);
        errdefer layer.deinit();

        var debugName: []const u8 = "unnamed";
        const nameAttr = node.getAttribute("name");
        if (nameAttr != null) {
            layer.name = try alloc.dupe(u8, nameAttr.?);
            debugName = layer.name.?;
        }

        layer.size = .{ .x = try std.fmt.parseInt(i32, node.getAttribute("width").?, 0), .y = try std.fmt.parseInt(i32, node.getAttribute("height").?, 0) };

        const dataNodeOpt = node.findChildByTag("data");
        if (dataNodeOpt == null) {
            std.log.err("No 'data' node found in tile layer '{s}'", .{debugName});
            return error.NoDataNodeInTileLayer;
        }

        const dataNode = dataNodeOpt.?;
        if (dataNode.getAttribute("encoding") == null) {
            std.log.err("No encoding on the 'data' element of tile layer '{s}", .{debugName});
            return error.NoEncodingOnDataNodeInTileLayer;
        }

        const encoding = dataNode.getAttribute("encoding").?;
        if (!std.mem.eql(u8, encoding, "csv")) {
            std.log.err("Only csv encodings are supported for tile layers currently: layer '{s}'", .{debugName});
            return error.UnsupportedLayerEncoding;
        }

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

    pub fn initObjectGroupFromElement(alloc: std.mem.Allocator, node: *xml.Element) !ObjectGroup {
        var layer = try ObjectGroup.init(alloc);
        errdefer layer.deinit();

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
                    const nameDup = try alloc.dupe(u8, name);
                    errdefer alloc.free(nameDup);

                    const value = prop.getAttribute("value").?;
                    const valueDup = try alloc.dupe(u8, value);
                    errdefer alloc.free(valueDup);

                    const newProp: Property = .{
                        .name = nameDup,
                        .value = valueDup,
                    };

                    try layer.properties.append(alloc, newProp);
                }
            } else if (std.mem.eql(u8, elem.tag, "object")) {
                var newObj = try initObjectFromElement(alloc, elem);
                errdefer newObj.deinit();

                try layer.objects.append(alloc, newObj);
            }
        }

        return layer;
    }

    pub fn initTileSetFromElement(alloc: std.mem.Allocator, node: *xml.Element) !TileSet {
        var tileset = try TileSet.init(alloc);
        errdefer tileset.deinit();

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
                var newTile = try initTileFromElement(alloc, child);
                errdefer newTile.deinit();

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

    pub fn initObjectFromElement(alloc: std.mem.Allocator, node: *xml.Element) !Object {
        var obj = try Object.init(alloc);
        errdefer obj.deinit();

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
                // Lazy init string/value property list.
                if (obj.properties == null) {
                    obj.properties = .empty;
                }

                const name = prop.getAttribute("name").?;
                const nameDup = try alloc.dupe(u8, name);
                errdefer alloc.free(nameDup);

                const value = prop.getAttribute("value").?;
                const valueDup = try alloc.dupe(u8, value);
                errdefer alloc.free(valueDup);

                const newProp: Property = .{
                    .name = nameDup,
                    .value = valueDup,
                };

                try obj.properties.?.append(alloc, newProp);
            }
        }

        return obj;
    }

    /// Initializes a tile from an XML element in the tileset.  This will add
    /// any properties defined on the tile in the tileset XML and set the core
    /// properties based on the "blocks" and "kills" properties defined in the XML.
    pub fn initTileFromElement(alloc: std.mem.Allocator, node: *xml.Element) !Tile {
        var tile = try Tile.init(alloc);
        errdefer tile.deinit();

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
};
