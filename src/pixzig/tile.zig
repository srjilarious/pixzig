const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");
const xml = @import("xml");

const common = @import("./common.zig");
const textures = @import("./renderer/textures.zig");
const shaders = @import("./renderer/shaders.zig");

const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;
const RectF = common.RectF;
const Color = common.Color;
const Texture = textures.Texture;
const Shader = shaders.Shader;

const tilemap = @import("./tile/tilemap.zig");

pub const Tile = tilemap.Tile;
pub const Property = tilemap.Property;
pub const Object = tilemap.Object;
pub const ObjectGroup = tilemap.ObjectGroup;
pub const TileLayer = tilemap.TileLayer;
pub const TileSet = tilemap.TileSet;
pub const TileMap = tilemap.TileMap;

pub const Clear = tilemap.Clear;
pub const BlocksLeft = tilemap.BlocksLeft;
pub const BlocksTop = tilemap.BlocksTop;
pub const BlocksRight = tilemap.BlocksRight;
pub const BlocksBottom = tilemap.BlocksBottom;
pub const BlocksAll = tilemap.BlocksAll;
pub const Kills = tilemap.Kills;
pub const UserPropsStart = tilemap.UserPropsStart;

/// The renderer for a Tiled map: built from a map name, resolves its own
/// shader and tileset textures. See `docs/tile-rendering.md`.
pub const TileMapRenderer = @import("./tile/tilemap_renderer.zig").TileMapRenderer;

/// Debug grid lines over a map area. Not a tile renderer -- it draws cell
/// borders for a given map/tile size and never reads a `TileMap`.
pub const GridRenderer = @import("./tile/grid_renderer.zig").GridRenderer;

/// Renderers on their way out. They still work, but `TileMapRenderer` is the
/// one to build new code against.
pub const deprecated = struct {
    /// One full-map vertex buffer per layer, with `u16` indices, so it
    /// overflows on large maps. Superseded by `TileMapRenderer`, which chunks.
    pub const TiledLayerRenderer = @import("./tile/tiled_layer_renderer.zig").TiledLayerRenderer;
};

pub const Mover = @import("./tile/tile_mover.zig").Mover;

pub const TiledMapXmlLoader = @import("./tile/tiled_loader.zig").TiledMapXmlLoader;
