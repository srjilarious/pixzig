//! The cells of assets/hopper.png, which holds the level's tiles and every
//! sprite in an 8-column grid of 16x16 cells (see tools/gen_art.py).

const pixzig = @import("pixzig");
const RectI = pixzig.RectI;
const Color = pixzig.Color;

/// Cells are this many pixels square.
const Size = 16;
pub const CellSize: f32 = Size;
const Columns = 8;

// Tile cells (the level's tileset is this same image).
pub const Grass = 0;
pub const Dirt = 1;

// Sprite cells. Sprites face right; they're flipped to face left.
pub const FrogIdle = 8;
pub const FrogRun1 = 9;
pub const FrogRun2 = 10;
pub const FrogJump = 11;
pub const BeetleWalk1 = 12;
pub const BeetleWalk2 = 13;
pub const BeetleSquashed = 14;
pub const Coin1 = 15;
pub const CoinFrames = 3;

// Colours the art is drawn with.

/// The sky behind everything. `renderer.clear` takes bytes rather than a
/// Color.
pub const Sky = [3]u8{ 120, 180, 240 };
/// The drop shadow under text.
pub const Shadow = Color.from(0, 0, 0, 255);

/// Where cell `index` is in the sheet, in pixels, for `Sprite.setSrcRect`.
pub fn rect(index: usize) RectI {
    const col: i32 = @intCast(index % Columns);
    const row: i32 = @intCast(index / Columns);
    return RectI.init(col * Size, row * Size, Size, Size);
}
