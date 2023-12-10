// zig fmt: off

const std = @import("std");
const xml = @import("xml");
const sdl = @import("zsdl");
const sprites = @import("sprites.zig");
const common = @import("common.zig");

const MaxFilesize = 1024 * 1024 * 1024;

const Vec2I = common.Vec2I;

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
                const newTile = try Tile.initFromElement(alloc, child);
                try tileset.tiles.append(newTile);
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

    pub fn tileData(self: *TileLayer, x: i32, y: i32) i32 {
        if(x < 0 or x >= self.size.x) return 0;
        if(y < 0 or y >= self.size.y) return 0;

        return self.tileDataUnchecked(x, y);
    }

    pub fn tileDataUnchecked(self: *TileLayer, x: i32, y: i32) i32 {
        return self.tiles.items[self.tileIndex(x, y)];
    }

    pub fn tileIndex(self: *TileLayer, x: i32, y: i32) usize {
        return @intCast(y*self.size.x + x);
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
                        std.debug.print("{: >3} ", .{ti});
                    }
                    std.debug.print("\n", .{});
                }
            }
        }

        return map;
    }
};

pub const TileMapRenderer = struct {
    vertices: std.ArrayList(sdl.Vertex),
    indices: std.ArrayList(u32),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !TileMapRenderer {
        return .{
            .vertices = std.ArrayList(sdl.Vertex).init(alloc),
            .indices = std.ArrayList(u32).init(alloc),
            .alloc = alloc
        };
    }

    pub fn deinit(self: *TileMapRenderer) void {
        self.vertices.deinit();
    }

    fn tileCoords(idx: i32, tileset: *TileSet) sdl.FRect {
        const i: i32 = @intCast(idx);
        if(idx < 0) {
            return .{
                .x = 0.0,
                .y = 0.0,
                .w = 0.0,
                .h = 0.0,
            };
        }

        const tu: f32 = @as(f32, @floatFromInt(@rem(i,tileset.columns)));
        const tv: f32 = @as(f32, @floatFromInt(@divTrunc(i,tileset.columns)));
        const tsx: f32 = @floatFromInt(tileset.tileSize.x);
        const tsy: f32 = @floatFromInt(tileset.tileSize.y);
        const txw: f32 = @floatFromInt(tileset.textureSize.x);
        const txh: f32 = @floatFromInt(tileset.textureSize.y);
        return .{
            .x = (tu * tsx) / txw,
            .y = (tv * tsy) / txh,
            .w = tsx / txw,
            .h = tsy / txh,
        };
    }

    pub fn recreateVertices(self: *TileMapRenderer, tileset: *TileSet, tiles: *TileLayer) !void {

        const tw = tileset.tileSize.x;
        const th = tileset.tileSize.y;
        const layerWidth: usize = @intCast(tiles.size.x);
        const layerHeight: usize = @intCast(tiles.size.y);
        try self.vertices.resize(@intCast(4*layerWidth*layerHeight));
        try self.indices.resize(@intCast(6*layerWidth*layerHeight));
        
        std.debug.print("Creating {} vertices\n", .{self.vertices.items.len});
        var idx: usize = 0;
        var indicesIdx: usize = 0;
        for(0..layerHeight) |yy| {
            for(0..layerWidth) |xx| {
                const y: i32 = @intCast(yy);
                const x: i32 = @intCast(xx);
                const tile = tiles.tileData(x, y);
                const uv = tileCoords(tile, tileset);
                
                self.vertices.items[idx] = .{
                    .position = .{ 
                        .x = @as(f32, @floatFromInt(x*tw)) - 0.01,
                        .y = @as(f32, @floatFromInt(y*th)) - 0.01,
                    },
                    .color = .{
                        .r = 255, .g = 255, .b = 255, .a = 255
                    },
                    .tex_coord = .{
                        .x = uv.x,
                        .y = uv.y,
                    }
                };
                idx += 1;

                self.vertices.items[idx] = .{
                    .position = .{ 
                        .x = @as(f32, @floatFromInt((x+1)*tw)) + 0.01,
                        .y = @as(f32, @floatFromInt(y*th)) - 0.01,
                    },
                    .color =.{
                        .r = 255, .g = 255, .b = 255, .a = 255
                    },
                    .tex_coord = .{
                        .x = uv.x + uv.w,
                        .y = uv.y,
                    }
                };
                idx += 1;

                self.vertices.items[idx] = .{
                    .position = .{ 
                        .x = @as(f32, @floatFromInt((x+1)*tw)) + 0.01,
                        .y = @as(f32, @floatFromInt((y+1)*th)) + 0.01,
                    },
                    .color = .{
                        .r = 255, .g = 255, .b = 255, .a = 255
                    },
                    .tex_coord = .{
                        .x = uv.x + uv.w,
                        .y = uv.y + uv.h,
                    }
                };
                idx += 1;

                self.vertices.items[idx] = .{
                    .position = .{ 
                        .x = @as(f32, @floatFromInt(x*tw)) - 0.01,
                        .y = @as(f32, @floatFromInt((y+1)*th)) + 0.01,
                    },
                    .color = .{
                        .r = 255, .g = 255, .b = 255, .a = 255
                    },
                    .tex_coord = .{
                        .x = uv.x,
                        .y = uv.y + uv.h,
                    }
                };
                idx += 1;

                const baseIdx: u32 = 4 * @as(u32, @intCast(y*@as(i32, @intCast(layerWidth)) + x));
                self.indices.items[indicesIdx] = baseIdx;
                self.indices.items[indicesIdx + 1] = baseIdx + 1;
                self.indices.items[indicesIdx + 2] = baseIdx + 3;
                self.indices.items[indicesIdx + 3] = baseIdx + 1;
                self.indices.items[indicesIdx + 4] = baseIdx + 2;
                self.indices.items[indicesIdx + 5] = baseIdx + 3;
                indicesIdx += 6;
            }
        }

        std.debug.print("{}\n", .{self.vertices.items[0]});
        // for (self.vertices.items) |vert| {
        //     std.debug.print("{}\n", .{vert});
        // }
    }

    pub fn draw(self: *TileMapRenderer, renderer: *sdl.Renderer, texture: *sdl.Texture, tiles: *TileLayer) !void {
        _ = tiles;

        renderer.drawGeometry(texture, self.vertices.items, self.indices.items) catch {};
    }
};
