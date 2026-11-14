//! Coins: they spin in place until the player touches them.

const pixzig = @import("pixzig");
const RectF = pixzig.RectF;

const sheet = @import("sheet.zig");

/// Hitbox size. Smaller than the 16x16 sprite, so grabbing one means
/// actually touching it.
pub const Size = 10;

pub const Coin = struct {
    rect: RectF,
    taken: bool = false,

    pub fn init(x: f32, y: f32) Coin {
        return .{ .rect = RectF.fromPosSize(x, y, Size, Size) };
    }
};

/// The sheet cell every coin shows `elapsed_ms` into the level: they all
/// spin together.
pub fn cell(elapsed_ms: f64) usize {
    const frame: usize = @intFromFloat(@mod(elapsed_ms / 120.0, sheet.CoinFrames));
    return sheet.Coin1 + frame;
}
