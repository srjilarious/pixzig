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

pub const TileMap = struct {
    pub fn initFromFile(filename: []const u8, alloc: std.mem.Allocator) !void {
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
                // for (newTileset.tiles.items) |tile| {
                //     std.debug.print(" Tile: {}\n", .{tile});
                // }
            }
        }
    }
};
