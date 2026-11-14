//! A level: its tile map, which of its tiles are solid, and where things
//! start in it.

const std = @import("std");
const pixzig = @import("pixzig");
const tile = pixzig.tile;
const RectF = pixzig.RectF;
const Vec2F = pixzig.Vec2F;

/// The tilemap asset ids, in play order (see manifest.json). Hopper has
/// one; finishing the last one wins the game.
pub const order = [_][]const u8{"level1"};

pub const Level = struct {
    map_renderer: tile.TileMapRenderer,

    /// Loads the tilemap registered under `id` (by the manifest).
    pub fn init(alloc: std.mem.Allocator, res: *pixzig.ResourceManager, id: []const u8) !Level {
        return .{ .map_renderer = try tile.TileMapRenderer.init(alloc, res, id) };
    }

    pub fn deinit(self: *Level) void {
        self.map_renderer.deinit();
    }

    /// The "Main" layer: the one bodies stand on and bump into. Other
    /// layers are only drawn.
    pub fn mainLayer(self: *const Level) *tile.TileLayer {
        const map = self.map_renderer.tileMap();
        return map.layerByName("Main") orelse &map.layers.items[0];
    }

    /// The map's size in pixels.
    pub fn width(self: *const Level) f32 {
        const layer = self.mainLayer();
        return @floatFromInt(layer.size.x * layer.tileSize.x);
    }

    pub fn height(self: *const Level) f32 {
        const layer = self.mainLayer();
        return @floatFromInt(layer.size.y * layer.tileSize.y);
    }

    /// Whether the tile under world pixel (x, y) is solid. Outside the map
    /// is empty.
    pub fn solidAt(self: *const Level, x: f32, y: f32) bool {
        const layer = self.mainLayer();
        const tx: i32 = @intFromFloat(@floor(x / @as(f32, @floatFromInt(layer.tileSize.x))));
        const ty: i32 = @intFromFloat(@floor(y / @as(f32, @floatFromInt(layer.tileSize.y))));
        const t = layer.tile(tx, ty) orelse return false;
        return (t.core & tile.BlocksAll) != 0;
    }

    /// The objects in the "Spawns" object layer. Each one's class says
    /// what starts there (see PlayState.restartLevel).
    pub fn spawns(self: *const Level) ![]tile.Object {
        const group = self.map_renderer.tileMap().objectGroupByName("Spawns") orelse return error.NoSpawns;
        return group.objects.items;
    }

    /// Draws every layer through `camera`.
    pub fn render(self: *Level, camera: *const pixzig.Camera2D, viewport: *const pixzig.Viewport) void {
        self.map_renderer.render(camera, viewport);
    }
};

/// The box a spawn object covers, in world pixels.
pub fn objectRect(obj: *const tile.Object) RectF {
    return RectF.fromPosSize(
        @floatFromInt(obj.pos.x),
        @floatFromInt(obj.pos.y),
        @floatFromInt(obj.size.x),
        @floatFromInt(obj.size.y),
    );
}

/// Where the top-left of a `w` x `h` body goes to stand on the bottom edge
/// of spawn box `obj`, centred across it. Spawns are tile-sized boxes, and
/// most bodies are smaller than a tile.
pub fn standOn(obj: *const tile.Object, w: f32, h: f32) Vec2F {
    const box = objectRect(obj);
    return .{ .x = box.l + (box.width() - w) / 2, .y = box.b - h };
}

/// Where the top-left of a `size` x `size` box goes to sit in the middle of
/// spawn box `obj`.
pub fn centreIn(obj: *const tile.Object, size: f32) Vec2F {
    const c = objectRect(obj).centerF();
    return .{ .x = c.x - size / 2, .y = c.y - size / 2 };
}
