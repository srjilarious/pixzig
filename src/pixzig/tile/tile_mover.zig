const std = @import("std");
const tilemap = @import("./tilemap.zig");
const TileLayer = tilemap.TileLayer;

const common = @import("../common.zig");

const RectF = common.RectF;

const Clear = tilemap.Clear;

/// Axis-aligned tile collision helpers. Each `moveX` function tries to move
/// `objRect` by `amount` along one axis, checking the row/column of tiles
/// `objRect` would sweep into against `tileMask` (see `tile.Clear`,
/// `tile.BlocksLeft`, etc.). Returns `true` and clamps `objRect` to the
/// blocking tile's edge if a tile matching `tileMask` was hit, or `false`
/// after moving the full `amount` if the path was clear.
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
        const tY_Start = @divTrunc(top, layer.tileSize.y);
        const tY_End = @divTrunc(bottom, layer.tileSize.y);

        var ty = tY_Start;
        while (ty <= tY_End) : (ty += 1) {
            const currTile = layer.tile(leftTileX, ty);
            if (currTile != null and (currTile.?.core & tileMask) > Clear) {
                objRect.l = @floatFromInt((leftTileX + 1) * layer.tileSize.x);
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
        while (ty <= tY_End) : (ty += 1) {
            const currTile = layer.tile(rightTileX, ty);
            if (currTile != null and (currTile.?.core & tileMask) > Clear) {
                objRect.r = @floatFromInt(rightTileX * layer.tileSize.x);
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
        const height = objRect.height();

        const topTileY = @divTrunc(top, layer.tileSize.y);
        const tX_Start = @divTrunc(left, layer.tileSize.x);
        const tX_End = @divTrunc(right, layer.tileSize.x);

        var tx = tX_Start;
        while (tx <= tX_End) : (tx += 1) {
            const currTile = layer.tile(tx, topTileY);
            if (currTile != null and (currTile.?.core & tileMask) > Clear) {
                objRect.t = @floatFromInt((topTileY + 1) * layer.tileSize.y);
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
        const height = objRect.height();

        const bottomTileY = @divTrunc(bottom, layer.tileSize.y);
        const tX_Start = @divTrunc(left, layer.tileSize.x);
        const tX_End = @divTrunc(right, layer.tileSize.x);

        var tx = tX_Start;
        while (tx <= tX_End) : (tx += 1) {
            const currTile = layer.tile(tx, bottomTileY);
            if (currTile != null and (currTile.?.core & tileMask) > Clear) {
                objRect.t = @as(f32, @floatFromInt(bottomTileY * layer.tileSize.y)) - height;
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
