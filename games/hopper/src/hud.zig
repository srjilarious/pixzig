//! The coins and lives counter in the top-left corner.

const std = @import("std");

const Engine = @import("main.zig").Engine;
const sheet = @import("sheet.zig");

/// Draws the HUD in screen space, so it stays put while the camera moves.
pub fn draw(eng: *Engine, coins: u32, lives: u8) void {
    eng.renderer.begin(.logical);
    defer eng.renderer.end();

    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Coins {d}   Lives {d}", .{ coins, lives }) catch "";
    _ = eng.renderer.drawText(text, .{ .x = 6, .y = 4 }, .{ .shadow = sheet.Shadow });
}
