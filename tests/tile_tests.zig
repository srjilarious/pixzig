const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const tile = pixzig.tile;
const xml = pixzig.xml;

pub fn tiledObjLoadTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const xmlStr =
        \\<object id="662" class="dot" gid="17" x="224" y="24" width="8" height="8"/>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var obj = try tile.TiledMapXmlLoader.initObjectFromElement(alloc, doc.root);
    defer obj.deinit();
    try testz.expectEqual(obj.id, 662);
    try testz.expectEqual(obj.gid, 17);
    try testz.expectEqual(obj.pos.x, 224);
    try testz.expectEqual(obj.pos.y, 24);
    try testz.expectEqual(obj.size.x, 8);
    try testz.expectEqual(obj.size.y, 8);
    try testz.expectEqualStr(obj.class.?, "dot");
    try testz.expectEqual(obj.name, null);
}

pub fn tiledObjWithPropsLoadTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const xmlStr =
        \\  <object id="1567" class="ghost" gid="33" x="30" y="112" width="8" height="8">
        \\   <properties>
        \\    <property name="ghostType" value="red"/>
        \\   </properties>
        \\  </object>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var obj = try tile.TiledMapXmlLoader.initObjectFromElement(alloc, doc.root);
    defer obj.deinit();
    try testz.expectEqual(obj.id, 1567);
    try testz.expectEqual(obj.gid, 33);
    try testz.expectEqual(obj.pos.x, 30);
    try testz.expectEqual(obj.pos.y, 112);
    try testz.expectEqual(obj.size.x, 8);
    try testz.expectEqual(obj.size.y, 8);
    try testz.expectEqualStr(obj.class.?, "ghost");
    try testz.expectEqual(obj.name, null);

    try testz.expectEqual(obj.properties.?.items.len, 1);
    const prop = obj.properties.?.items[0];
    try testz.expectEqualStr(prop.name, "ghostType");
    try testz.expectEqualStr(prop.value, "red");
}

pub fn tiledObjWithFloatsLoadTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const xmlStr =
        \\  <object id="1567" class="ghost" gid="33" x="30.333" y="112.5" width="8" height="8">
        \\  </object>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var obj = try tile.TiledMapXmlLoader.initObjectFromElement(alloc, doc.root);
    defer obj.deinit();
    try testz.expectEqual(obj.id, 1567);
    try testz.expectEqual(obj.gid, 33);
    try testz.expectEqual(obj.pos.x, 30);
    try testz.expectEqual(obj.pos.y, 112);
    try testz.expectEqual(obj.size.x, 8);
    try testz.expectEqual(obj.size.y, 8);
    try testz.expectEqualStr(obj.class.?, "ghost");
    try testz.expectEqual(obj.name, null);
    try testz.expectEqual(obj.name, null);
}

pub fn tiledObjGroupLoadTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const xmlStr =
        \\<objectgroup id="2" name="dots">
        \\  <properties>
        \\    <property name="layer_type" value="entities"/>
        \\  </properties>
        \\  <object id="662" class="dot" gid="17" x="224" y="24" width="8" height="8"/>
        \\  <object id="669" class="dot" gid="17" x="64" y="24" width="8" height="8"/>
        \\  <object id="671" class="dot" gid="17" x="248" y="24" width="8" height="8"/>
        \\</objectgroup>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var objGroup = tile.TiledMapXmlLoader.initObjectGroupFromElement(alloc, doc.root) catch |err| {
        try testz.failWith(err);
        return;
    };
    defer objGroup.deinit();
    try testz.expectEqual(objGroup.id, 2);
    try testz.expectEqualStr(objGroup.name.?, "dots");

    try testz.expectEqual(objGroup.properties.items.len, 1);

    const prop = &objGroup.properties.items[0];
    try testz.expectEqualStr(prop.name, "layer_type");
    try testz.expectEqualStr(prop.value, "entities");

    try testz.expectEqual(objGroup.objects.items.len, 3);

    try testz.expectEqual(objGroup.objects.items[0].id, 662);
    try testz.expectEqualStr(objGroup.objects.items[0].class.?, "dot");

    try testz.expectEqual(objGroup.objects.items[1].id, 669);
    try testz.expectEqualStr(objGroup.objects.items[1].class.?, "dot");

    try testz.expectEqual(objGroup.objects.items[2].id, 671);
    try testz.expectEqualStr(objGroup.objects.items[2].class.?, "dot");
}

pub fn tiledObjGroupIteratorTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const xmlStr =
        \\<objectgroup id="2" name="dots">
        \\  <properties>
        \\    <property name="layer_type" value="entities"/>
        \\  </properties>
        \\  <object id="662" class="dot" gid="17" x="224" y="24" width="8" height="8"/>
        \\  <object id="669" class="power_dot" gid="17" x="64" y="24" width="8" height="8"/>
        \\  <object id="671" class="dot" gid="17" x="248" y="24" width="8" height="8"/>
        \\</objectgroup>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var objGroup = tile.TiledMapXmlLoader.initObjectGroupFromElement(alloc, doc.root) catch |err| {
        try testz.failWith(err);
        return;
    };
    defer objGroup.deinit();

    var it = objGroup.iterator("dot");
    const obj0 = it.next().?;
    try testz.expectEqual(obj0.id, 662);
    try testz.expectEqualStr(obj0.class.?, "dot");

    const obj1 = it.next().?;
    try testz.expectEqual(obj1.id, 671);
    try testz.expectEqualStr(obj1.class.?, "dot");

    try testz.expectEqual(it.next(), null);
}

pub fn csvTooManyEntriesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // 2x2 layer expects 4 tiles; 5 are supplied.
    const xmlStr =
        \\<layer id="1" name="test" width="2" height="2">
        \\  <data encoding="csv">
        \\    1,2,3,4,5
        \\  </data>
        \\</layer>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var no_tilesets: [0]tile.TileSet = .{};
    if (tile.TiledMapXmlLoader.initTileLayerFromElement(alloc, doc.root, &no_tilesets)) |layer| {
        var l = layer;
        l.deinit();
        try testz.failWith(error.ExpectedTooManyTileEntriesError);
    } else |err| {
        try testz.expectEqual(err, error.TooManyTileEntries);
    }
}

pub fn csvTooFewEntriesTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // 2x2 layer expects 4 tiles; only 3 are supplied.
    const xmlStr =
        \\<layer id="1" name="test" width="2" height="2">
        \\  <data encoding="csv">
        \\    1,2,3
        \\  </data>
        \\</layer>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var no_tilesets: [0]tile.TileSet = .{};
    if (tile.TiledMapXmlLoader.initTileLayerFromElement(alloc, doc.root, &no_tilesets)) |layer| {
        var l = layer;
        l.deinit();
        try testz.failWith(error.ExpectedTooFewTileEntriesError);
    } else |err| {
        try testz.expectEqual(err, error.TooFewTileEntries);
    }
}

pub fn csvInvalidGidTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // One entry is not a valid integer.
    const xmlStr =
        \\<layer id="1" name="test" width="2" height="2">
        \\  <data encoding="csv">
        \\    1,abc,3,4
        \\  </data>
        \\</layer>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var no_tilesets: [0]tile.TileSet = .{};
    if (tile.TiledMapXmlLoader.initTileLayerFromElement(alloc, doc.root, &no_tilesets)) |layer| {
        var l = layer;
        l.deinit();
        try testz.failWith(error.ExpectedInvalidTileGidError);
    } else |err| {
        try testz.expectEqual(err, error.InvalidTileGid);
    }
}

pub fn multiTilesetFirstgidTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    // Two tilesets: tiles1 owns GIDs 1-16, tiles2 owns GIDs 17+.
    // The layer uses GIDs from tiles2, so the local indices should be GID - 17.
    const xmlStr =
        \\<map version="1.9" tiledversion="1.9.2" orientation="orthogonal" renderorder="right-down" width="2" height="2" tilewidth="8" tileheight="8">
        \\ <tileset firstgid="1" name="tiles1" tilewidth="8" tileheight="8" tilecount="16" columns="4">
        \\   <image source="sprites1.png" width="32" height="32"/>
        \\ </tileset>
        \\ <tileset firstgid="17" name="tiles2" tilewidth="8" tileheight="8" tilecount="16" columns="4">
        \\   <image source="sprites2.png" width="32" height="32"/>
        \\ </tileset>
        \\ <layer id="1" name="test_layer" width="2" height="2">
        \\   <data encoding="csv">
        \\     17,18,0,0
        \\   </data>
        \\ </layer>
        \\</map>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var map = tile.TiledMapXmlLoader.initFromElement(doc.root, alloc) catch |err| {
        try testz.failWith(err);
        return;
    };
    defer map.deinit();

    try testz.expectEqual(map.tilesets.items.len, 2);

    const layer = map.layerByName("test_layer").?;
    // GID 17 → tiles2, local index 0
    try testz.expectEqual(layer.tiles.items[0], 0);
    // GID 18 → tiles2, local index 1
    try testz.expectEqual(layer.tiles.items[1], 1);
    // GID 0 → empty
    try testz.expectEqual(layer.tiles.items[2], -1);
    try testz.expectEqual(layer.tiles.items[3], -1);
    // Layer's tileset should be tiles2
    try testz.expectEqualStr(layer.tileset.?.name.?, "tiles2");
}

pub fn getLayerAndObjGroupTest(io: std.Io, alloc: std.mem.Allocator) !void {
    _ = io;
    const xmlStr =
        \\<map version="1.9" tiledversion="1.9.2" orientation="orthogonal" renderorder="right-down" width="2" height="2" tilewidth="8" tileheight="8">
        \\ <tileset firstgid="1" name="tiles" tilewidth="8" tileheight="8" tilecount="256" columns="16">
        \\   <image source="sprites.png" width="128" height="128"/>
        \\ </tileset>
        \\ <layer id="1" name="main_layer" width="2" height="2" locked="1">
        \\   <properties>
        \\     <property name="layer_type" value="collide"/>
        \\   </properties>
        \\   <data encoding="csv">
        \\     0,0,0,0
        \\   </data>
        \\ </layer>
        \\ <objectgroup id="2" name="dots">
        \\   <properties>
        \\     <property name="layer_type" value="entities"/>
        \\   </properties>
        \\   <object id="662" class="dot" gid="17" x="224" y="24" width="8" height="8"/>
        \\   <object id="669" class="power_dot" gid="17" x="64" y="24" width="8" height="8"/>
        \\   <object id="671" class="dot" gid="17" x="248" y="24" width="8" height="8"/>
        \\ </objectgroup>
        \\</map>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    defer doc.deinit();
    var map = tile.TiledMapXmlLoader.initFromElement(doc.root, alloc) catch |err| {
        try testz.failWith(err);
        return;
    };
    defer map.deinit();

    try testz.expectNotEqual(map.layerByIndex(0), null);
    try testz.expectEqual(map.layerByIndex(1), null);

    try testz.expectNotEqual(map.objectGroupByIndex(0), null);
    try testz.expectEqual(map.objectGroupByIndex(1), null);

    try testz.expectNotEqual(map.layerByName("main_layer"), null);
    try testz.expectEqual(map.layerByName("dots"), null);

    try testz.expectNotEqual(map.objectGroupByName("dots"), null);
    try testz.expectEqual(map.objectGroupByName("main_layer"), null);
}
