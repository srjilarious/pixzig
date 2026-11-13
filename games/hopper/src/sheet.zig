//! The cells of assets/hopper.png, which holds the level's tiles and every
//! sprite in an 8-column grid of 16x16 cells (see tools/gen_art.py).

const pixzig = @import("pixzig");
const RectF = pixzig.RectF;

pub const CellSize: f32 = 16;
const Columns = 8;
const Rows = 3;

// Sprite cells. Left-facing frog frames are the right-facing ones plus 4.
pub const FrogIdle = 8;
pub const FrogRun1 = 9;
pub const FrogRun2 = 10;
pub const FrogJump = 11;
pub const FrogFacingLeft = 4;
pub const BeetleWalk1 = 16;
pub const BeetleWalk2 = 17;
pub const BeetleSquashed = 18;
pub const Coin1 = 19;
pub const CoinFrames = 3;

/// The texture coordinates (0..1) of cell `index`, for
/// `renderer.drawTexture`.
pub fn uv(index: usize) RectF {
    const col: f32 = @floatFromInt(index % Columns);
    const row: f32 = @floatFromInt(index / Columns);
    const w = 1.0 / @as(f32, Columns);
    const h = 1.0 / @as(f32, Rows);
    return .{ .l = col * w, .t = row * h, .r = (col + 1) * w, .b = (row + 1) * h };
}
