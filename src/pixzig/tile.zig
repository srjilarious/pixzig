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

pub const TiledLayerRenderer = @import("./tile/tilemap_renderer.zig").TiledLayerRenderer;
pub const GridRenderer = @import("./tile/grid_renderer.zig").GridRenderer;

pub const ChunkedTiledLayerRenderer = @import("./tile/chunked_tile_renderer.zig").ChunkedTiledLayerRenderer;
pub const ChunkedTiledRenderer = @import("./tile/chunked_tiled_renderer.zig").ChunkedTiledRenderer;

pub const Mover = @import("./tile/tile_mover.zig").Mover;

pub const TiledMapXmlLoader = @import("./tile/tiled_loader.zig").TiledMapXmlLoader;
