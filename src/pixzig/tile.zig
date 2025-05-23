// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");
const xml = @import("xml");

const common = @import("./common.zig");
const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Texture = textures.Texture;
const Shader = shaders.Shader;

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

pub const Property = struct { name: []const u8, value: []const u8 };

pub const PropertyList = std.ArrayList(Property);

pub const Tile = struct {
    core: CoreTileProperty,
    properties: ?PropertyList,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !Tile {
        return .{ .core = Clear, .properties = null, .alloc = alloc };
    }

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
                self.properties = PropertyList.init(self.alloc);
            }

            const newName = try self.alloc.dupe(u8, name);
            const newValue = try self.alloc.dupe(u8, value);
            const newProp: Property = .{ .name = newName, .value = newValue };
            try self.properties.?.append(newProp);
        }
    }

    pub fn deinit(self: *Tile) void {
        if (self.properties != null) {
            for (0..self.properties.?.items.len) |idx| {
                const prop = self.properties.?.items[idx];
                self.alloc.free(prop.name);
                self.alloc.free(prop.value);
            }
            self.properties.?.deinit();
        }
    }
};

fn intFromFloatAttr(node: *xml.Element, attr: []const u8) !i32 {
    const str = node.getAttribute(attr);
    if(str == null) return error.NoAttribute;
   
    const f = try std.fmt.parseFloat(f32, str.?);
    const val: i32 = @intFromFloat(f);
    return val;
}

pub const Object = struct {
    alloc: std.mem.Allocator,
    id: i32 = -1,
    gid: i32 = -1,
    pos: Vec2I = .{ .x = -1, .y = -1},
    size: Vec2I = .{ .x = 0, .y = 0},
    name: ?[]const u8 = null,
    class: ?[]const u8 = null,
    properties: ?PropertyList = null,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{ .alloc = alloc };
    }

    pub fn initFromElement(alloc: std.mem.Allocator, node: *xml.Element) !Self {
        var obj = try Object.init(alloc);

        if (!std.mem.eql(u8, node.tag, "object")) return error.BadNodeTag;

        obj.id = try std.fmt.parseInt(i32, node.getAttribute("id").?, 0);
        obj.gid = try std.fmt.parseInt(i32, node.getAttribute("gid").?, 0);
        obj.pos = .{
            .x = try intFromFloatAttr(node,"x"),
            .y = try intFromFloatAttr(node,"y"),
        };
        obj.size = .{
            .x = try intFromFloatAttr(node,"width"),
            .y = try intFromFloatAttr(node,"height"),
        };
        
        const classOpt = node.getAttribute("class");
        if(classOpt != null) {
            obj.class = try alloc.dupe(u8, classOpt.?);
        }

        // Get any props from the object.
        const propsNodeOpt = node.findChildByTag("properties");

        if(propsNodeOpt ) |propsNode| {
            var propsChildren = propsNode.elements();
            while (propsChildren.next()) |prop| {
                const name = prop.getAttribute("name").?;
                const value = prop.getAttribute("value").?;

                // Lazy init string/value property list.
                if (obj.properties == null) {
                    obj.properties = PropertyList.init(alloc);
                }

                const newProp: Property = .{ 
                    .name = try alloc.dupe(u8, name), 
                    .value = try alloc.dupe(u8, value), 
                };
                try obj.properties.?.append(newProp);
            }
        }

        return obj;
    }

    pub fn deinit(self: *Self) void {
        if(self.name != null) {
            self.alloc.free(self.name.?);
        }

        if(self.class != null) {
            self.alloc.free(self.class.?);
        }

        if(self.properties != null) {
            for (0..self.properties.?.items.len) |idx| {
                const prop = &self.properties.?.items[idx];
                self.alloc.free(prop.name);
                self.alloc.free(prop.value);
            }
        }
    }
};

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
            .tiles = std.ArrayList(Tile).init(alloc),
            .tileSize = .{ .x = 0, .y = 0 },
            .textureSize = .{ .x = 0, .y = 0 },
            .columns = 0,
            .name = null,
            .alloc = alloc,
        };
    }

    pub fn initEmpty(alloc: std.mem.Allocator, tileSize: Vec2I, textureSize: Vec2I, tileCount: usize) !TileSet {
        var tiles = std.ArrayList(Tile).init(alloc);
        const baseTile = Tile{
            .core = Clear,
            .properties = null,
            .alloc = alloc
        };
        try tiles.appendNTimes(baseTile, tileCount);

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

        tileset.tileSize = .{ 
            .x = try std.fmt.parseInt(i32, node.getAttribute("tilewidth").?, 0),
            .y = try std.fmt.parseInt(i32, node.getAttribute("tileheight").?, 0)
        };

        tileset.columns = try std.fmt.parseInt(i32, node.getAttribute("columns").?, 0);

        const tileCount = try std.fmt.parseInt(usize, node.getAttribute("tilecount").?, 0);
        const baseTile = Tile{
            .core = Clear,
            .properties = null,
            .alloc = alloc
        };
        try tileset.tiles.appendNTimes(baseTile, tileCount);

        var children = node.elements();
        while (children.next()) |child| {
            if (std.mem.eql(u8, child.tag, "tile")) {
                const newTile = try Tile.initFromElement(alloc, child);
                const tileId = try std.fmt.parseInt(usize, child.getAttribute("id").?, 0);
                tileset.tiles.items[tileId] = newTile;
            } else if(std.mem.eql(u8, child.tag, "image")) {
                tileset.textureSize = .{ 
                    .x = try std.fmt.parseInt(i32, child.getAttribute("width").?, 0),
                    .y = try std.fmt.parseInt(i32, child.getAttribute("height").?, 0)
                };
            }
            else {
                std.debug.print("Unhandled tileset child: {s}\n", .{child.tag});
            }
        }

        return tileset;
    }

    pub fn deinit(self: *TileSet) void {
        if(self.name != null) {
            self.alloc.free(self.name.?);
        }

        for (0..self.tiles.items.len) |idx| {
            self.tiles.items[idx].deinit();
        }

        self.tiles.deinit();
    }

    pub fn tile(self: *TileSet, idx: usize) ?*Tile {
        if(idx > self.tiles.items.len) return null;

        return &self.tiles.items[idx];
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
        return .{
            .objects = std.ArrayList(Object).init(alloc),
            .properties = PropertyList.init(alloc),
            .id = 0,
            .name = null,
            .alloc = alloc
        };
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
                    if(!std.mem.eql(u8, prop.tag, "property")) {
                        return error.UnexpectedElement;
                    }

                    const name = prop.getAttribute("name").?;
                    const value = prop.getAttribute("value").?;
                    const newProp: Property = .{ 
                        .name = try alloc.dupe(u8, name), 
                        .value = try alloc.dupe(u8, value), 
                    };

                    try layer.properties.append(newProp);
                }
            }
            else if(std.mem.eql(u8, elem.tag, "object")) {
                const newObj = try Object.initFromElement(alloc, elem);
                try layer.objects.append(newObj);
            }
        }

        return layer;
    }

    pub fn deinit(self: *Self) void {
        if(self.name != null) {
            self.alloc.free(self.name.?);
            self.name = null;
        }

        for(0..self.objects.items.len) |idx| {
            const obj = &self.objects.items[idx];
            obj.deinit();
        }
        self.objects.deinit();

        for (0..self.properties.items.len) |idx| {
            const prop = &self.properties.items[idx];
            self.alloc.free(prop.name);
            self.alloc.free(prop.value);
        }

        self.properties.deinit();
    }

    const ObjectGroupIterator = struct {
        parent: *const ObjectGroup,
        class: ?[]const u8 = null,
        index: usize = 0,

        pub fn init(parent: *const ObjectGroup, class: ?[]const u8) ObjectGroupIterator {
            return .{ .parent = parent, .class = class };
        }

        pub fn next(self: *ObjectGroupIterator) ?*Object {
            
            while(self.index < self.parent.objects.items.len) {
                const currItem = &self.parent.objects.items[self.index];

                // Handle the iterator filtering by class name.
                if(self.class) |classStr| {
                    if(currItem.class) |itemClassStr| {
                        if(std.mem.eql(u8, classStr, itemClassStr)) {
                            self.index += 1;
                            return currItem;
                        } 
                        else {
                            self.index += 1;
                        }
                    }
                    else {
                        self.index += 1;
                    }
                }
                else {
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
        for(0..self.objects.items.len) |idx| {
            const curr = &self.objects.items[idx];
            if(curr.class != null and std.mem.eql(u8, curr.class.?, class)) {
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

pub const TileLayer = struct {
    tiles: std.ArrayList(i32),
    properties: PropertyList,
    size: Vec2I,
    name: ?[]const u8,
    tileset: ?*TileSet,
    tileSize: Vec2I,
    isDirty: bool,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !TileLayer {
        return .{
            .tiles = std.ArrayList(i32).init(alloc),
            .properties = PropertyList.init(alloc),
            .size = .{ .x = 0, .y = 0 },
            .name = null,
            .tileset = null,
            .tileSize = .{ .x = 0, .y = 0 },
            .isDirty = false,
            .alloc = alloc
        };
    }

    pub fn initEmpty(alloc: std.mem.Allocator, size: Vec2I, tileSize: Vec2I) !TileLayer {
        var tilesArr = std.ArrayList(i32).init(alloc);
        try tilesArr.appendNTimes(-1, @intCast(size.x*size.y));
        return .{
            .tiles = tilesArr,
            .properties = PropertyList.init(alloc),
            .size = size,
            .name = null,
            .tileset = null,
            .tileSize = tileSize,
            .isDirty = false,
            .alloc = alloc
        };
    }

    pub fn initFromElement(alloc: std.mem.Allocator, node: *xml.Element) !TileLayer {
        var layer = try init(alloc);

        const nameAttr = node.getAttribute("name");
        if (nameAttr != null) {
            layer.name = try alloc.dupe(u8, nameAttr.?);
        }

        layer.size = .{ 
            .x = try std.fmt.parseInt(i32, node.getAttribute("width").?, 0),
            .y = try std.fmt.parseInt(i32, node.getAttribute("height").?, 0)
        };

        const dataNode = node.findChildByTag("data").?;
        const encoding = dataNode.getAttribute("encoding").?;
        if(!std.mem.eql(u8, encoding, "csv")) return error.UnsupportedLayerEncoding;

        // Resize the layer to have space for all of our tile indices.
        try layer.tiles.resize(@intCast(layer.size.x*layer.size.y));

        const tileDataVal = node.getCharData("data").?;
        var it = std.mem.tokenizeAny(u8, tileDataVal, ",\n");
        var buffIdx: usize = 0;
        while (it.next()) |curr| {
            const idx = std.fmt.parseInt(i32, curr, 0) catch |err| {
                std.debug.print("Unable to parse index: {s}: {}", .{curr, err});
                continue;
            };

            layer.tiles.items[buffIdx] = idx - 1;
            buffIdx += 1;
        }
        
        // const propsNode = node.findChildByTag("properties").?;
        
        return layer;
    }

    pub fn deinit(self: *TileLayer) void {
        if(self.name != null) {
            self.alloc.free(self.name.?);
            self.name = null;
        }

        self.tiles.deinit();

        for (0..self.properties.items.len) |idx| {
            const prop = &self.properties.items[idx];
            self.alloc.free(prop.name);
            self.alloc.free(prop.value);
        }

        self.properties.deinit();

        self.tileset = null;
    }

    pub fn tileDataPtrUnchecked(self: *TileLayer, x: i32, y: i32) *i32 {
        return &self.tiles.items[self.tileIndex(x, y)];
    }

    pub fn setTileData(self: *TileLayer, x: i32, y: i32, val: i32) void {
        if(x < 0 or x >= self.size.x) return;
        if(y < 0 or y >= self.size.y) return;

        self.tileDataPtrUnchecked(x, y).* = val;
    }

    pub fn tileData(self: *const TileLayer, x: i32, y: i32) i32 {
        if(x < 0 or x >= self.size.x) return -1;
        if(y < 0 or y >= self.size.y) return -1;

        return self.tileDataUnchecked(x, y);
    }

    pub fn tileDataUnchecked(self: *const TileLayer, x: i32, y: i32) i32 {
        return self.tiles.items[self.tileIndex(x, y)];
    }

    pub fn tileIndex(self: *const TileLayer, x: i32, y: i32) usize {
        return @intCast(y*self.size.x + x);
    }

    pub fn tile(self: *const TileLayer, x: i32, y:i32) ?*Tile {
        if(self.tileset == null) return null;
        if(x < 0 or x >= self.size.x) return null;
        if(y < 0 or y >= self.size.y) return null;

        const tsVal = self.tileDataUnchecked(x, y);
        if(tsVal < 0) return null;
   
        const tsIdx:usize = @intCast(tsVal);
        return self.tileset.?.tile(tsIdx);
    }

    pub fn dumpLayer(self: *const TileLayer) void {
        for(0..@intCast(self.size.y)) |yy| {
            for(0..@intCast(self.size.x)) |xx| {
                std.debug.print("{} ", .{self.tileData(@intCast(xx), @intCast(yy))});
            }
            std.debug.print("\n", .{});
        }
    }
};

pub const TileMap = struct {
    tilesets: std.ArrayList(TileSet),
    layers: std.ArrayList(TileLayer),
    objectGroups: std.ArrayList(ObjectGroup),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !TileMap {
        return .{
            .tilesets = std.ArrayList(TileSet).init(alloc),
            .layers = std.ArrayList(TileLayer).init(alloc),
            .objectGroups = std.ArrayList(ObjectGroup).init(alloc),
            .alloc = alloc
        };
    }

    pub fn initFromFile(filename: []const u8, alloc: std.mem.Allocator) !TileMap {
        const fileContents = try std.fs.cwd().readFileAlloc(alloc, filename, MaxFilesize);
        defer alloc.free(fileContents);

        std.log.debug("Loaded tile map file contents.", .{});
        const doc = try xml.parse(alloc, fileContents);
        return initFromElement(doc.root, alloc);
    }

    pub fn initFromElement(node: *xml.Element, alloc: std.mem.Allocator) !TileMap {
        var map = try init(alloc);
        var elems = node.elements();
        while (elems.next()) |elem| {
            if (std.mem.eql(u8, elem.tag, "tileset")) {
                const newTileset = try TileSet.initFromElement(alloc, elem);
                std.log.debug("Loaded a tileset '{s}', with {} tiles, {}x{} tile size, {} columns\n", .{
                    newTileset.name.?, 
                    newTileset.tiles.items.len, 
                    newTileset.tileSize.x, 
                    newTileset.tileSize.y, 
                    newTileset.columns
                });
                
                try map.tilesets.append(newTileset);
            }
            else if(std.mem.eql(u8, elem.tag, "layer")) {
                const newLayer = try TileLayer.initFromElement(alloc, elem);
                std.log.debug("Loaded a tile layer: '{?s}'", .{newLayer.name});
                try map.layers.append(newLayer);
            }
            else if(std.mem.eql(u8, elem.tag, "objectgroup")) {
                const newObjGroup = try ObjectGroup.initFromElement(alloc, elem);
                std.log.debug("Loaded object group: '{?s}'", .{ newObjGroup.name});
                try map.objectGroups.append(newObjGroup);
            }
        }

        if(map.tilesets.items.len == 0) {
            std.log.warn("No tileset found in map!\n", .{});
        }

        for (0..map.layers.items.len) |idx| {
            var layer = &map.layers.items[idx];

            if(layer.tileset == null) {
                layer.tileset = &map.tilesets.items[0];
                layer.tileSize = map.tilesets.items[0].tileSize;
            }
        }

        return map;
    }

    pub fn layerByIndex(self: *const TileMap, idx: usize) ?*TileLayer {
        if(idx >= self.layers.items.len) return null;
        return &self.layers.items[idx];
    }

    pub fn objectGroupByIndex(self: *const TileMap, idx: usize) ?*ObjectGroup {
        if(idx >= self.objectGroups.items.len) return null;
        return &self.objectGroups.items[idx];
    }

    pub fn layerByName(self: *const TileMap, name: []const u8) ?*TileLayer {
        for(0..self.layers.items.len) |idx| {
            const layer = & self.layers.items[idx];
            if(layer.name != null and std.mem.eql(u8, layer.name.?, name)) {
                return layer;
            }
        }
        return null;
    }

    pub fn objectGroupByName(self: *const TileMap, name: []const u8) ?*ObjectGroup {
        for(0..self.objectGroups.items.len) |idx| {
            const objGroup = & self.objectGroups.items[idx];
            if(objGroup.name != null and std.mem.eql(u8, objGroup.name.?, name)) {
                return objGroup;
            }
        }
        return null;
    }

    pub fn deinit(self: *TileMap) void {
        for(0..self.tilesets.items.len) |idx| {
            self.tilesets.items[idx].deinit();
        }

        self.tilesets.deinit();

        for(0..self.layers.items.len) |idx| {
            self.layers.items[idx].deinit();
        }

        self.layers.deinit();
    }
};

const TileIndexMap = struct {
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
            .arr = std.ArrayList(KV).init(alloc)
        };
    }

    pub fn deinit(self: *Self) void {
        self.arr.deinit();
    }

    pub fn getBuffIndex(self: *const Self, tileIdx: usize) ?usize {
        for(self.arr.items) |kv| {
            if(kv.tileIdx == tileIdx) {
                return kv.bufferIdx;
            }
        }
        return null;
    }

    pub fn getTileIndex(self: *const Self, bufferIdx: usize) ?usize {
        for(self.arr.items) |kv| {
            if(kv.bufferIdx == bufferIdx) {
                return kv.tileIdx;
            }
        }
        return null;
    }

    pub fn getIdxFromTileIndex(self: *const Self, tileIdx: usize) ?usize {
        for(self.arr.items, 0..) |kv, idx| {
            if(kv.tileIdx == tileIdx) {
                return idx;
            }
        }
        return null;
    }

    pub fn update(self: *Self, tileIdx: usize, bufferIdx: usize) bool {
        if(self.getIdxFromTileIndex(tileIdx)) |idx| {
            self.arr.items[idx].bufferIdx = bufferIdx;
            return true;
        }
        else {
            return false;
        }
    }

    pub fn removeByTileIndex(self: *Self, tileIndex: usize) bool {
        if(self.getIdxFromTileIndex(tileIndex)) |idx| {
            _ = self.arr.swapRemove(idx);
            return true;
        }
        else {
            return false;
        }
    }

    pub fn put(self: *Self, tileIndex: usize, bufferIndex: usize) !bool {
        const val: KV = .{.tileIdx = tileIndex, .bufferIdx = bufferIndex};
        if(self.getIdxFromTileIndex(tileIndex)) |idx| {
            self.arr.items[idx] = val;
            return true;
        }
        else {
            try self.arr.append(val);
            return false;
        }
    }
};

pub const TileMapRenderer = struct {
    mapSize: Vec2U = undefined,
    shader: Shader = undefined,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboTexCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: []f32 = undefined,
    texCoords: []f32 = undefined,
    indices: []u16 = undefined,
    alloc: std.mem.Allocator,
    attrCoord: c_uint = 0,
    attrTexCoord: c_uint = 0,
    uniformMVP: c_int = 0,
    numActualIndices: usize = 0,
    numBuffVals: usize = 0,
    tileIndexMap: TileIndexMap,

    pub fn init(alloc: std.mem.Allocator, shader: Shader) !TileMapRenderer {
        var tr = TileMapRenderer{
            .shader = shader,
            .alloc = alloc,
            .tileIndexMap = TileIndexMap.init(alloc),
        };

        gl.genVertexArrays(1, &tr.vao);

        gl.genBuffers(1, &tr.vboVertices);
        gl.genBuffers(1, &tr.vboTexCoords);
        gl.genBuffers(1, &tr.vboIndices);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.TEXTURE_2D);
        
        tr.attrCoord = @intCast(gl.getAttribLocation(tr.shader.program, "coord3d"));
        tr.attrTexCoord = @intCast(gl.getAttribLocation(tr.shader.program, "texcoord"));
        tr.uniformMVP = @intCast(gl.getUniformLocation(tr.shader.program, "projectionMatrix"));

        return tr;
    }

    pub fn deinit(self: *TileMapRenderer) void {
        self.alloc.free(self.vertices);
        self.alloc.free(self.texCoords);
        self.alloc.free(self.indices);
        self.tileIndexMap.deinit();
    }

    fn tileCoords(idx: i32, tileset: *TileSet) RectF {
        const i: i32 = @intCast(idx);
        if(idx < 0) {
            return .{
                .l = 0.99,
                .t = 0.99,
                .r = 0.99,
                .b = 0.99,
            };
        }

        const tu: f32 = @as(f32, @floatFromInt(@rem(i,tileset.columns)));
        const tv: f32 = @as(f32, @floatFromInt(@divTrunc(i,tileset.columns)));
        const tsx: f32 = @floatFromInt(tileset.tileSize.x);
        const tsy: f32 = @floatFromInt(tileset.tileSize.y);
        const txw: f32 = @floatFromInt(tileset.textureSize.x);
        const txh: f32 = @floatFromInt(tileset.textureSize.y);
        const l = (tu * tsx) / txw;
        const t = (tv * tsy) / txh;
        return .{
            .l = l,
            .t = t,
            .r = l + tsx / txw,
            .b = t + tsy / txh,
        };
    }

    fn dump(self: *TileMapRenderer) void {
        std.debug.print("*****************\n", .{});
        
        std.debug.print("### tileIndexMap:\n", .{});
        for(self.tileIndexMap.arr.items, 0..) |kv, idx| {

            std.debug.print("[{}] tIdx={}, bIdx={}\n", .{idx, kv.tileIdx, kv.bufferIdx});
            var vIdx = (kv.bufferIdx)*8;
            var iIdx = (kv.bufferIdx)*6;

            std.debug.print("Vertices: \n", .{});
            for(0..4) |_| {
                std.debug.print("({}, {}) ", .{ @as(i32, @intFromFloat(self.vertices[vIdx])), @as(i32, @intFromFloat(self.vertices[vIdx+1])) });
                vIdx += 2;
            }
            std.debug.print("\n", .{});

            std.debug.print("Indices: \n", .{});
            for(0..2) |_| {
                std.debug.print("({}, {}, {}) ", .{ self.indices[iIdx], self.indices[iIdx+1], self.indices[iIdx+2] });
                iIdx += 3;
            }
            std.debug.print("\n\n", .{});
        }

        std.debug.print("*****************\n", .{});
    }

    pub fn tileChanged(self: *TileMapRenderer, tileset: *TileSet, tiles: *TileLayer, loc: Vec2I, tile: i32) !void {
        const layerWidth: usize = @intCast(tiles.size.x);
        const layerHeight: usize = @intCast(tiles.size.y);
        if(loc.x < 0 or loc.x >= layerWidth) return;
        if(loc.y < 0 or loc.y >= layerHeight) return;

        const tileIdx: usize = @intCast(loc.y*@as(i32, @intCast(layerWidth))+loc.x);

        // Check for a tile add/change
        if(tile >= 0) {
            // if location exists in map
            if(self.tileIndexMap.getBuffIndex(tileIdx)) |buffIdx| {
                // Update buffer data
                const vertIdx = buffIdx*8;
                const indicesIdx = buffIdx*6;
                self.setTileRenderData(loc, vertIdx, indicesIdx, tiles.tileSize, tile, tileset);
            }
            // if location no in map
            else {
                // Add to end of buffer
                const vertIdx = self.numBuffVals*8;
                const indicesIdx = self.numBuffVals*6;
                self.setTileRenderData(loc, vertIdx, indicesIdx, tiles.tileSize, tile, tileset);

                _ = try self.tileIndexMap.put(tileIdx, self.numBuffVals);

                self.numBuffVals += 1;
                self.numActualIndices += 6;
            }
        }
        // A tile is being removed.
        else {
            std.debug.print("Removing block at {}, {}\n", .{loc.x, loc.y});

            // Find the bufferIndex if location exists in map
            if(self.tileIndexMap.getBuffIndex(tileIdx)) |buffIdx| {
                const lastBuffIdx = self.numBuffVals-1;

                // If buffIdx is the last, simply stop drawing its indices
                if(buffIdx == lastBuffIdx) {
                    const rem = self.tileIndexMap.removeByTileIndex(tileIdx);
                    std.debug.assert(rem);
                    self.numBuffVals -= 1;
                    self.numActualIndices -= 6;
                }
                // Otherwise, the block to remove is somewhere in the middle,
                // so swap the last block with it updating our map indices.
                else {
                    // Update buffer data
                    const destVertIdx = buffIdx*8;
                    
                    const srcVertIdx = (lastBuffIdx)*8;
                    const lastK = self.tileIndexMap.getTileIndex(lastBuffIdx).?;

                    // Copy from the end into the slot we want to erase
                    // Note we don't want to change the indices, since we're moving the vertex data
                    // the indices in that slot should stay the same.
                    @memcpy(self.vertices[destVertIdx..destVertIdx+8], self.vertices[srcVertIdx..srcVertIdx+8]);
                    @memcpy(self.texCoords[destVertIdx..destVertIdx+8], self.texCoords[srcVertIdx..srcVertIdx+8]);

                    // Remove the bufferIndex of the removed item.
                    _ = self.tileIndexMap.removeByTileIndex(tileIdx);
                    _ = self.tileIndexMap.update(lastK, buffIdx);

                    self.numBuffVals -= 1;
                    self.numActualIndices -= 6;
                }
                
            }
            else {
                std.debug.print("No tile set in position!\n", .{});
            }
        }

        // self.dump();
    }

    fn setTileRenderData(self: *TileMapRenderer,
        loc: Vec2I,
        vertIdx: usize, 
        indicesIdx: usize,
        ts: Vec2I,
        tile: i32, 
        tileset: *TileSet) void 
    {
        const uv = tileCoords(tile, tileset);
        var idx = vertIdx;
        const x = loc.x;
        const y = loc.y;

        // Coord 1
        self.vertices[idx] = @as(f32, @floatFromInt(x*ts.x)) - 0.01;
        self.vertices[idx+1] = @as(f32, @floatFromInt(y*ts.y)) - 0.01;
        self.texCoords[idx] = uv.l;
        self.texCoords[idx+1] = uv.t;
        idx += 2;

        // Coord 2
        self.vertices[idx] = @as(f32, @floatFromInt((x+1)*ts.x)) + 0.01;
        self.vertices[idx+1] = @as(f32, @floatFromInt(y*ts.y)) - 0.01;
        self.texCoords[idx] = uv.r;
        self.texCoords[idx+1] = uv.t;
        idx += 2;

        // Coord 3
        self.vertices[idx] = @as(f32, @floatFromInt((x+1)*ts.x)) + 0.01;
        self.vertices[idx+1] = @as(f32, @floatFromInt((y+1)*ts.y)) + 0.01;
        self.texCoords[idx] = uv.r;
        self.texCoords[idx+1] = uv.b;
        idx += 2;

        // Coord 4
        self.vertices[idx] = @as(f32, @floatFromInt(x*ts.x)) - 0.01;
        self.vertices[idx+1] = @as(f32, @floatFromInt((y+1)*ts.y)) + 0.01;
        self.texCoords[idx] = uv.l;
        self.texCoords[idx+1] = uv.b;
        idx += 2;

        // const baseIdx: u16 = 4 * @as(u16, @intCast(y*@as(i32, @intCast(layerWidth)) + x));
        const baseIdx: u16 = @divTrunc(@as(u16, @intCast(idx - 8)), 2);
        self.indices[indicesIdx] = baseIdx;
        self.indices[indicesIdx + 1] = baseIdx + 1;
        self.indices[indicesIdx + 2] = baseIdx + 3;
        self.indices[indicesIdx + 3] = baseIdx + 1;
        self.indices[indicesIdx + 4] = baseIdx + 2;
        self.indices[indicesIdx + 5] = baseIdx + 3;
    }

    pub fn recreateVertices(self: *TileMapRenderer, tileset: *TileSet, tiles: *TileLayer) !void {

        // const tw = tileset.tileSize.x;
        // const th = tileset.tileSize.y;
        const layerWidth: usize = @intCast(tiles.size.x);
        const layerHeight: usize = @intCast(tiles.size.y);
        self.mapSize = .{ .x=@intCast(layerWidth), .y=@intCast(layerHeight) };
        const mapSize: i32 = @intCast(layerWidth*layerHeight);
        _ = mapSize;
        const numVerts: usize = @intCast(2*4*layerWidth*layerHeight);
        const numIndices: usize = @intCast(6*layerWidth*layerHeight);

        std.log.debug("Creating map render data: verts={}, texCoords={}, indices={}", .{numVerts, numVerts, numIndices});
        self.vertices = try self.alloc.alloc(f32, numVerts);
        self.texCoords = try self.alloc.alloc(f32, numVerts);
        self.indices = try self.alloc.alloc(u16, numIndices);
        
        std.log.debug("Creating {} vertices\n", .{self.vertices.len});
        // self.tileIndexMap.clearRetainingCapacity();
        var buffIdx: usize = 0;
        var idx: usize = 0;
        var indicesIdx: usize = 0;
        for(0..layerHeight) |yy| {
            for(0..layerWidth) |xx| {
                const y: i32 = @intCast(yy);
                const x: i32 = @intCast(xx);
                const tile = tiles.tileData(x, y);
                if(tile < 0) continue;

                // Keep a map of which tile index maps to what buffer index.
                // This lets us handle adding/removing tiles dynamically.
                const tileIdx = y*@as(i32, @intCast(layerWidth))+x;
                _ = try self.tileIndexMap.put(@intCast(tileIdx), buffIdx);
                // std.debug.print("Placing tileIdx={} in buffIdx={}\n", .{tileIdx, buffIdx});
                self.setTileRenderData(.{.x=x, .y=y}, idx, indicesIdx, tileset.tileSize, tile, tileset);
                idx += 8;
                indicesIdx += 6;

                // Since we skip empty tiles, keep track of which index in the buffer each drawn tile
                // is going to map to.
                buffIdx += 1;
            }
        }

        self.numActualIndices = indicesIdx;
        self.numBuffVals = buffIdx;
        std.log.info("TileMapRenderer.recreateVertices finished.", .{});
    }

    pub fn draw(self: *TileMapRenderer, 
                texture: *Texture, 
                tiles: *TileLayer, 
                mvp: zmath.Mat) !void 
    {
        const mvpArr = zmath.matToArr(mvp);
        const layerWidth: usize = @intCast(tiles.size.x);
        const layerHeight: usize = @intCast(tiles.size.y);
        const mapSize: i32 = @intCast(layerWidth*layerHeight);
        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&mvpArr[0]));

        // Set 'tex' to use texture unit 0
        gl.activeTexture(gl.TEXTURE0); 
        gl.bindTexture(gl.TEXTURE_2D, texture.texture); 
        gl.uniform1i(gl.getUniformLocation(self.shader.program, "tex"), 0); 

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * mapSize), &self.vertices[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrCoord,
            2, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.enableVertexAttribArray(self.attrTexCoord);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * mapSize), &self.texCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrTexCoord,
            2, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(u16) * self.numActualIndices), &self.indices[0], gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(self.numActualIndices), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrTexCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    }
};


pub const GridRenderer = struct {
    shader: Shader = undefined,
    color: Color = undefined,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboColorCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: []f32 = undefined,
    colorCoords: []f32 = undefined,
    indices: []u16 = undefined,
    alloc: std.mem.Allocator,
    attrCoord: c_uint = 0,
    attrColor: c_uint = 0,
    uniformMVP: c_int = 0,

    currVert: usize = 0,
    currColorCoord: usize = 0,
    currIdx: usize = 0,
    numRects: usize = 0,
    initialized: bool = false,

    pub fn init(alloc: std.mem.Allocator, shader: Shader, mapSize: Vec2I, tileSize: Vec2I, borderSize: usize, color: Color) !GridRenderer {
        var gr = GridRenderer{
            .shader = shader,
            .color = color,
            .alloc = alloc
        };
        gl.genVertexArrays(1, &gr.vao);

        gl.genBuffers(1, &gr.vboVertices);
        gl.genBuffers(1, &gr.vboColorCoords);
        gl.genBuffers(1, &gr.vboIndices);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.TEXTURE_2D);
        
        gr.attrCoord = @intCast(gl.getAttribLocation(gr.shader.program, "coord3d"));
        gr.attrColor = @intCast(gl.getAttribLocation(gr.shader.program, "color"));
        gr.uniformMVP = @intCast(gl.getUniformLocation(gr.shader.program, "projectionMatrix"));

        try gr.recreateVertices(mapSize, tileSize, borderSize, color);
        return gr;
    }

    pub fn deinit(self: *GridRenderer) void {
        self.alloc.free(self.vertices);
        self.alloc.free(self.colorCoords);
        self.alloc.free(self.indices);

        gl.deleteBuffers(1, &self.vboVertices);
        gl.deleteBuffers(1, &self.vboColorCoords);
        gl.deleteBuffers(1, &self.vboIndices);
    }

    fn drawFilledRect(self: *GridRenderer, dest: RectF, color: Color) void {

        const verts = self.vertices[self.currVert..self.currVert+8];
        verts[0] = dest.l;
        verts[1] = dest.b;

        verts[2] = dest.l;
        verts[3] = dest.t;

        verts[4] = dest.r;
        verts[5] = dest.t;

        verts[6] = dest.r;
        verts[7] = dest.b;

        const colorCoords = self.colorCoords[self.currColorCoord..self.currColorCoord+16];
        colorCoords[0] = color.r;
        colorCoords[1] = color.g;
        colorCoords[2] = color.b;
        colorCoords[3] = color.a;
        
        colorCoords[4] = color.r;
        colorCoords[5] = color.g;
        colorCoords[6] = color.b;
        colorCoords[7] = color.a;
        
        colorCoords[8] = color.r;
        colorCoords[9] = color.g;
        colorCoords[10] = color.b;
        colorCoords[11] = color.a;
        
        colorCoords[12] = color.r;
        colorCoords[13] = color.g;
        colorCoords[14] = color.b;
        colorCoords[15] = color.a;

        const indices = self.indices[self.currIdx..self.currIdx+6];
        const currVertIdx: u16 = @intCast(self.currVert / 2);
        indices[0] = currVertIdx+0;
        indices[1] = currVertIdx+1;
        indices[2] = currVertIdx+2;
        indices[3] = currVertIdx+2;
        indices[4] = currVertIdx+3;
        indices[5] = currVertIdx+0;

        self.currVert += 8;
        self.currColorCoord += 16;
        self.currIdx += 6;

        self.numRects += 1;
    }

    fn drawVertLine(self: *GridRenderer, x: i32, w: i32, h: i32, color:Color) void {
        self.drawFilledRect(RectF.fromPosSize(x, 0, w, h), color);
    }

    fn drawHorzLine(self: *GridRenderer, y: i32, w: i32, h: i32, color:Color) void {
        self.drawFilledRect(RectF.fromPosSize(0, y, w, h), color);
    }

    pub fn recreateVertices(self: *GridRenderer, mapSize: Vec2I, tileSize: Vec2I, borderSize: usize, color:Color) !void {
        self.currVert = 0;
        self.currColorCoord = 0;
        self.currIdx = 0;
        self.numRects = 0;

        const tw:usize = @intCast(tileSize.x);
        const th:usize = @intCast(tileSize.y);
        const numHorz: usize = @as(usize, @intCast(mapSize.x)) + 1;
        const numVert: usize = @as(usize, @intCast(mapSize.y)) + 1;
        // const mapSize: i32 = @intCast(layerWidth*layerHeight);
        // _ = mapSize;
    
        // Check if we need to release previous buffers.
        if(self.initialized) {
            self.alloc.free(self.vertices);
            self.alloc.free(self.colorCoords);
            self.alloc.free(self.indices);
        }

        self.vertices = try self.alloc.alloc(f32, @intCast(2*4*numHorz*numVert*2));
        self.colorCoords = try self.alloc.alloc(f32, @intCast(4*4*numHorz*numVert*2));
        self.indices = try self.alloc.alloc(u16, @intCast(6*numHorz*numVert*2));
        self.initialized = true;

        std.debug.print("Creating {} vertices\n", .{self.vertices.len});
        const gridWidth:i32 = @intCast((numHorz-1)*tw);
        const gridHeight:i32 = @intCast((numVert-1)*th);
        for(0..numVert) |yy| {
            for(0..numHorz) |xx| {
                self.drawHorzLine(@intCast(yy*th), gridWidth, @intCast(borderSize), color); 
                self.drawVertLine(@intCast(xx*tw), @intCast(borderSize), gridHeight, color); 
            }
        }
    }

    pub fn draw(self: *GridRenderer,
                mvp: zmath.Mat) !void
    {
        const mvpArr = zmath.matToArr(mvp);
        // const layerWidth: usize = @intCast(tiles.size.x);
        // const layerHeight: usize = @intCast(tiles.size.y);
        // const mapSize: i32 = @intCast(layerWidth*layerHeight);
        gl.useProgram(self.shader.program);
        gl.uniformMatrix4fv(self.uniformMVP, 1, gl.FALSE, @ptrCast(&mvpArr[0]));

        gl.disable(gl.TEXTURE_2D);

        gl.bindVertexArray(self.vao);
        gl.enableVertexAttribArray(self.attrCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * self.numRects), &self.vertices[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrCoord,
            2, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.enableVertexAttribArray(self.attrColor);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboColorCoords); 
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(4 * 4 * @sizeOf(f32) * self.numRects), &self.colorCoords[0], gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrColor,
            4, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * self.numRects), &self.indices[0], gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(6 * self.numRects), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrColor);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    }
};



pub const Mover = struct {

    // fn isTileMovable(x: i32, y: i32) bool {
    //     return false;
    // }
    //
    // fn checkCollide(px: i32, py: i32) bool {
    //
    // }

    pub fn moveLeft(objRect: *RectF, amount: f32, layer: *TileLayer, tileMask: u32) bool {
        const left: i32 = @intFromFloat(objRect.l - amount);
        const top: i32 = @intFromFloat(@ceil(objRect.t) + 0.5);
        const bottom: i32 = @intFromFloat(@floor(objRect.b) - 0.5);
        const width = objRect.width();

        const leftTileX = @divTrunc(left, layer.tileSize.x);
        const tY_Start = @divTrunc(top,layer.tileSize.y);
        const tY_End = @divTrunc(bottom, layer.tileSize.y);

        var ty = tY_Start;
        while(ty <= tY_End) : (ty += 1) {
            const currTile = layer.tile(leftTileX, ty);
            if(currTile != null and (currTile.?.core & tileMask) > Clear) {
                objRect.l = @floatFromInt((leftTileX+1)*layer.tileSize.x);
                // Make sure the width remains unchanged.
                objRect.r = objRect.l + width;
                return true;
            }
        }

        objRect.l -= amount;
        objRect.r = objRect.l + width;
        return false;
    }

    pub fn moveRight(objRect: *RectF, amount: f32, layer: *TileLayer, tileMask: u32) bool {
        const right: i32 = @intFromFloat(objRect.r + amount);
        const top: i32 = @intFromFloat(@ceil(objRect.t) + 0.5);
        const bottom: i32 = @intFromFloat(@floor(objRect.b) - 0.5);
        const width = objRect.width();

        const rightTileX = @divTrunc(right, layer.tileSize.x);
        const tY_Start = @divTrunc(top, layer.tileSize.y);
        const tY_End = @divTrunc(bottom, layer.tileSize.y);

        var ty = tY_Start;
        while(ty <= tY_End) : (ty += 1) {
            const currTile = layer.tile(rightTileX, ty);
            if(currTile != null and (currTile.?.core & tileMask) > Clear) {
                objRect.r = @floatFromInt(rightTileX*layer.tileSize.x);
                // Make sure the width remains unchanged.
                objRect.l = objRect.r - width;
                return true;
            }
        }

        objRect.r += amount;
        objRect.l = objRect.r - width;
        return false;
    }

    pub fn moveUp(objRect: *RectF, amount: f32, layer: *TileLayer, tileMask: u32) bool {
        const top: i32 = @intFromFloat(objRect.t - amount);
        const left: i32 = @intFromFloat(@ceil(objRect.l) + 0.5);
        const right: i32 = @intFromFloat(@floor(objRect.r) - 0.5);
        const height = objRect.width();

        const topTileY = @divTrunc(top, layer.tileSize.y);
        const tX_Start = @divTrunc(left,layer.tileSize.x);
        const tX_End = @divTrunc(right, layer.tileSize.x);

        var tx = tX_Start;
        while(tx <= tX_End) : (tx += 1) {
            const currTile = layer.tile(tx, topTileY);
            if(currTile != null and (currTile.?.core & tileMask) > Clear) {
                objRect.t = @floatFromInt((topTileY+1)*layer.tileSize.y);
                // Make sure the width remains unchanged.
                objRect.b = objRect.t + height;
                return true;
            }
        }

        objRect.t -= amount;
        objRect.b = objRect.t + height;
        return false;
    }

    pub fn moveDown(objRect: *RectF, amount: f32, layer: *TileLayer, tileMask: u32) bool {
        const bottom: i32 = @intFromFloat(objRect.b + amount);
        const left: i32 = @intFromFloat(@ceil(objRect.l) + 0.5);
        const right: i32 = @intFromFloat(@floor(objRect.r) - 0.5);
        const height = objRect.width();

        const bottomTileY = @divTrunc(bottom, layer.tileSize.y);
        const tX_Start = @divTrunc(left,layer.tileSize.x);
        const tX_End = @divTrunc(right, layer.tileSize.x);

        var tx = tX_Start;
        while(tx <= tX_End) : (tx += 1) {
            const currTile = layer.tile(tx, bottomTileY);
            if(currTile != null and (currTile.?.core & tileMask) > Clear) {
                objRect.t = @as(f32, @floatFromInt(bottomTileY*layer.tileSize.y)) - height;
                // Make sure the width remains unchanged.
                objRect.b = objRect.t + height;
                return true;
            }
        }

        objRect.t += amount;
        objRect.b = objRect.t + height;
        return false;
    }
};
