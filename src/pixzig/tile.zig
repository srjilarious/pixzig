// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl");
const zmath = @import("zmath");
const xml = @import("xml");

const common = @import("./common.zig");
const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");

const Vec2I = common.Vec2I;
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
    shader: *Shader = undefined,
    vao: u32 = 0,
    vboVertices: u32 = 0,
    vboTexCoords: u32 = 0,
    vboIndices: u32 = 0,
    vertices: std.ArrayList(f32),
    texCoords: std.ArrayList(f32),
    indices: std.ArrayList(u32),
    alloc: std.mem.Allocator,
    attrCoord: c_uint = 0,
    attrTexCoord: c_uint = 0,
    uniformMVP: c_int = 0,
    
    pub fn init(alloc: std.mem.Allocator, shader: *Shader) !TileMapRenderer {
        var tr = TileMapRenderer{
            .shader = shader,
            .vertices = std.ArrayList(f32).init(alloc),
            .texCoords = std.ArrayList(f32).init(alloc),
            .indices = std.ArrayList(u32).init(alloc),
            .alloc = alloc

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
        self.vertices.deinit();
    }

    fn tileCoords(idx: i32, tileset: *TileSet) RectF {
        const i: i32 = @intCast(idx);
        if(idx < 0) {
            return .{
                .l = 0.0,
                .t = 0.0,
                .r = 0.0,
                .b = 0.0,
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

    pub fn recreateVertices(self: *TileMapRenderer, tileset: *TileSet, tiles: *TileLayer) !void {

        const tw = tileset.tileSize.x;
        const th = tileset.tileSize.y;
        const layerWidth: usize = @intCast(tiles.size.x);
        const layerHeight: usize = @intCast(tiles.size.y);
        const mapSize: i32 = @intCast(layerWidth*layerHeight);
        try self.vertices.resize(@intCast(2*4*layerWidth*layerHeight));
        try self.texCoords.resize(@intCast(2*4*layerWidth*layerHeight));
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
               
                // Coord 1
                self.vertices.items[idx] = @as(f32, @floatFromInt(x*tw)) - 0.01;
                self.vertices.items[idx+1] = @as(f32, @floatFromInt(y*th)) - 0.01;
                self.texCoords.items[idx] = uv.l;
                self.texCoords.items[idx+1] = uv.t;
                idx += 2;

                // Coord 2
                self.vertices.items[idx] = @as(f32, @floatFromInt((x+1)*tw)) + 0.01;
                self.vertices.items[idx+1] = @as(f32, @floatFromInt(y*th)) - 0.01;
                self.texCoords.items[idx] = uv.r;
                self.texCoords.items[idx+1] = uv.t;
                idx += 2;

                // Coord 3
                self.vertices.items[idx] = @as(f32, @floatFromInt((x+1)*tw)) + 0.01;
                self.vertices.items[idx+1] = @as(f32, @floatFromInt((y+1)*th)) + 0.01;
                self.texCoords.items[idx] = uv.r;
                self.texCoords.items[idx+1] = uv.b;
                idx += 2;

                // Coord 4
                self.vertices.items[idx] = @as(f32, @floatFromInt(x*tw)) - 0.01;
                self.vertices.items[idx+1] = @as(f32, @floatFromInt((y+1)*th)) + 0.01;
                self.texCoords.items[idx] = uv.l;
                self.texCoords.items[idx+1] = uv.b;
                idx += 2;

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

        gl.bindVertexArray(self.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboVertices);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * mapSize, &self.vertices, gl.STATIC_DRAW);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vboTexCoords);
        gl.bufferData(gl.ARRAY_BUFFER, 2 * 4 * mapSize, &self.texCoords, gl.STATIC_DRAW);

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, 6 * mapSize, &self.indices, gl.STATIC_DRAW);
        // std.debug.print("{}\n", .{self.vertices[0]});
        // for (self.vertices.items) |vert| {
        //     std.debug.print("{}\n", .{vert});
        // }
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
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * mapSize), &self.vertices, gl.STATIC_DRAW);
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
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(2 * 4 * @sizeOf(f32) * mapSize), &self.texCoords, gl.STATIC_DRAW);
        gl.vertexAttribPointer(
            self.attrTexCoord,
            2, // Num elems per vertex
            gl.FLOAT, 
            gl.FALSE,
            0, // stride
            null
        );

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.vboIndices);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(6 * @sizeOf(u16) * mapSize), &self.indices, gl.STATIC_DRAW);

        gl.drawElements(gl.TRIANGLES, @intCast(6 * mapSize), gl.UNSIGNED_SHORT, null);
        gl.disableVertexAttribArray(self.attrCoord);
        gl.disableVertexAttribArray(self.attrTexCoord);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        //
        // renderer.drawGeometry(texture, self.vertices.items, self.indices.items) catch {};
    }
};
