// zig fmt: off

const std = @import("std");
const xml = @import("xml");
const sdl = @import("sdl");
const sprites = @import("sprites.zig");

const MaxFilesize = 1024 * 1024 * 1024;

const Vec2I = sprites.Vec2I;

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
            const newProp = .{ .name = newName, .value = newValue };
            try self.properties.?.append(newProp);
        }
    }

    pub fn deinit(self: *Tile) void {
        if (self.properties != null) {
            for (self.properties.?) |prop| {
                self.alloc.free(prop.name);
                self.alloc.free(prop.value);
            }
            self.properties.?.deinit();
        }
    }
};

pub const TileSet = struct {
    //tileTexture: *Texture,

    tiles: std.ArrayList(Tile),
    tileSize: Vec2I,
    columns: i32,
    name: ?[]const u8,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !TileSet {
        return .{
            .tiles = std.ArrayList(Tile).init(alloc),
            .tileSize = .{ .x = 0, .y = 0 },
            .columns = 0,
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

        var children = node.elements();
        while (children.next()) |child| {
            if (std.mem.eql(u8, child.tag, "tile")) {
                var newTile = try Tile.initFromElement(alloc, child);
                try tileset.tiles.append(newTile);
            } else {
                std.debug.print("Unhandled tileset child: {s}\n", .{child.tag});
            }
        }

        return tileset;
    }

    pub fn deinit(self: *TileSet) void {
        if(self.name != null) {
            self.alloc.free(self.name);
        }

        for (self.tiles) |tile| {
            tile.deinit();
        }

        self.tiles.deinit();
    }

};


pub const TileLayer = struct {
    tiles: std.ArrayList(i32),
    properties: PropertyList,
    size: Vec2I,
    name: ?[]const u8,
    tileset: ?TileSet,
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

        const tileData = node.getCharData("data").?;
        var it = std.mem.tokenizeAny(u8, tileData, ",\n");
        var buffIdx: usize = 0;
        while (it.next()) |curr| {
            const idx = std.fmt.parseInt(i32, curr, 0) catch |err| {
                std.debug.print("Unable to parse index: {s}: {}", .{curr, err});
                continue;
            };

            layer.tiles.items[buffIdx] = idx;
            buffIdx += 1;
        }
        
        // const propsNode = node.findChildByTag("properties").?;
        
        return layer;
    }

    pub fn deinit(self: TileLayer) void {
        if(self.name != null) {
            self.alloc.free(self.name);
            self.name = null;
        }

        self.tiles.deinit();

        for (self.properties) |prop| {
            self.alloc.free(prop.name);
            self.alloc.free(prop.value);
        }

        self.properties.deinit();

        self.tileset = null;
    }
};

pub const TileMap = struct {
    tilesets: std.ArrayList(TileSet),
    layers: std.ArrayList(TileLayer),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !TileMap {
        return .{
            .tilesets = std.ArrayList(TileSet).init(alloc),
            .layers = std.ArrayList(TileLayer).init(alloc),
            .alloc = alloc
        };
    }

    pub fn initFromFile(filename: []const u8, alloc: std.mem.Allocator) !TileMap {
        var map = try init(alloc);

        const fileContents = try std.fs.cwd().readFileAlloc(alloc, filename, MaxFilesize);
        defer alloc.free(fileContents);

        std.debug.print("\nContents:\n\n-------\n{s}\n--------\n\n", .{fileContents});

        const doc = try xml.parse(std.heap.page_allocator, fileContents);
        var elems = doc.root.elements();
        while (elems.next()) |elem| {
            std.debug.print("Element: {s}\n", .{elem.tag});
            if (std.mem.eql(u8, elem.tag, "tileset")) {
                const newTileset = try TileSet.initFromElement(alloc, elem);
                std.debug.print("Loaded a tileset '{s}', with {} tiles, {}x{} tile size, {} columns\n", .{
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
                std.debug.print("Loaded a tile layer: '{?s}'", .{newLayer.name});
                try map.layers.append(newLayer);

                for(0..@intCast(newLayer.size.y)) |y| {
                    const lineOffs = y*@as(usize, @intCast(newLayer.size.x));
                    for(0..@intCast(newLayer.size.x)) |x| {
                        const ti = newLayer.tiles.items[lineOffs + x];
                        std.debug.print("{: >3} ", .{@as(u32, @intCast(ti))});
                    }
                    std.debug.print("\n", .{});
                }
            }
        }

        return map;
    }
};
