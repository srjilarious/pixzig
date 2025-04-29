const std = @import("std");
const testz = @import("testz");
const pixzig = @import("pixzig");
const tile = pixzig.tile;
const xml = pixzig.xml;

pub fn tiledObjLoadTest() !void {
    const alloc = std.heap.page_allocator;
    const xmlStr =
        \\<object id="662" class="dot" gid="17" x="224" y="24" width="8" height="8"/>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    const obj = try tile.Object.initFromElement(alloc, doc.root);
    try testz.expectEqual(obj.id, 662);
    try testz.expectEqual(obj.gid, 17);
    try testz.expectEqual(obj.pos.x, 224);
    try testz.expectEqual(obj.pos.y, 24);
    try testz.expectEqual(obj.size.x, 8);
    try testz.expectEqual(obj.size.y, 8);
    try testz.expectEqualStr(obj.class.?, "dot");
    try testz.expectEqual(obj.name, null);
}

pub fn tiledObjWithPropsLoadTest() !void {
    const alloc = std.heap.page_allocator;
    const xmlStr =
        \\  <object id="1567" class="ghost" gid="33" x="30" y="112" width="8" height="8">
        \\   <properties>
        \\    <property name="ghostType" value="red"/>
        \\   </properties>
        \\  </object>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    const obj = try tile.Object.initFromElement(alloc, doc.root);
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

pub fn tiledObjWithFloatsLoadTest() !void {
    const alloc = std.heap.page_allocator;
    const xmlStr =
        \\  <object id="1567" class="ghost" gid="33" x="30.333" y="112.5" width="8" height="8">
        \\  </object>
    ;
    const doc = try xml.parse(alloc, xmlStr);
    const obj = try tile.Object.initFromElement(alloc, doc.root);
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

pub fn tiledObjGroupLoadTest() !void {
    const alloc = std.heap.page_allocator;
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
    const objGroup = tile.ObjectGroup.initFromElement(alloc, doc.root) catch |err| {
        try testz.failWith(err);
        return;
    };
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

pub fn tiledObjGroupIteratorTest() !void {
    const alloc = std.heap.page_allocator;
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
    const objGroup = tile.ObjectGroup.initFromElement(alloc, doc.root) catch |err| {
        try testz.failWith(err);
        return;
    };

    var it = objGroup.iterator("dot");
    const obj0 = it.next().?;
    try testz.expectEqual(obj0.id, 662);
    try testz.expectEqualStr(obj0.class.?, "dot");

    const obj1 = it.next().?;
    try testz.expectEqual(obj1.id, 671);
    try testz.expectEqualStr(obj1.class.?, "dot");

    try testz.expectEqual(it.next(), null);
}

pub fn getLayerAndObjGroupTest() !void {
    const alloc = std.heap.page_allocator;
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
    const map = tile.TileMap.initFromElement(doc.root, alloc) catch |err| {
        try testz.failWith(err);
        return;
    };

    try testz.expectNotEqual(map.layerByIndex(0), null);
    try testz.expectEqual(map.layerByIndex(1), null);

    try testz.expectNotEqual(map.objectGroupByIndex(0), null);
    try testz.expectEqual(map.objectGroupByIndex(1), null);

    try testz.expectNotEqual(map.layerByName("main_layer"), null);
    try testz.expectEqual(map.layerByName("dots"), null);

    try testz.expectNotEqual(map.objectGroupByName("dots"), null);
    try testz.expectEqual(map.objectGroupByName("main_layer"), null);
}
