//! The screens around play: the title, the pause overlay, and the "level
//! clear" / "game over" message.

const std = @import("std");
const pixzig = @import("pixzig");
const RectF = pixzig.RectF;
const Color = pixzig.Color;

const App = @import("main.zig").App;
const Engine = @import("main.zig").Engine;
const sheet = @import("sheet.zig");

const Shadow = sheet.Shadow;

pub const TitleState = struct {
    app: *App,
    elapsed_ms: f64 = 0,

    pub fn update(self: *TitleState, eng: *Engine, delta: f64) void {
        self.elapsed_ms += delta;
        if (eng.actions.pressed(.back)) {
            eng.quit();
            return;
        }
        if (eng.actions.pressed(.confirm) or eng.actions.pressed(.jump)) self.app.startGame();
    }

    /// The name over a strip of ground with the frog hopping on it.
    pub fn render(self: *TitleState, eng: *Engine, alpha: f32) void {
        _ = alpha;
        const size = logicalSize(eng);
        eng.renderer.clear(sheet.Sky[0], sheet.Sky[1], sheet.Sky[2], 255);
        eng.renderer.begin(.logical);

        // Ground along the bottom, two tiles deep.
        const ground_y = size.y - 2 * sheet.CellSize;
        var x: f32 = 0;
        while (x < size.x) : (x += sheet.CellSize) {
            self.app.drawCell(sheet.Grass, x, ground_y, .none);
            self.app.drawCell(sheet.Dirt, x, ground_y + sheet.CellSize, .none);
        }

        // A little hop every second.
        const t: f32 = @floatCast(@mod(self.elapsed_ms, 1000) / 1000);
        const hop = @max(0, @sin(t * std.math.pi * 2)) * 14;
        const frame: usize = if (hop > 0.5) sheet.FrogJump else sheet.FrogIdle;
        self.app.drawCell(frame, size.x / 2 - 8, ground_y - sheet.CellSize - hop, .none);

        _ = eng.renderer.drawText("HOPPER", .{ .x = size.x / 2, .y = size.y * 0.2 }, .{
            .scale = 3,
            .color = Color.from(255, 230, 90, 255),
            .@"align" = .center,
            .shadow = Shadow,
            .shadowOffset = .{ .x = 2, .y = 2 },
        });
        _ = eng.renderer.drawText("Press Space or Enter", .{ .x = size.x / 2, .y = size.y * 0.5 }, centered());
        _ = eng.renderer.drawText("Arrows move, Space jumps, P pauses", .{ .x = size.x / 2, .y = size.y * 0.5 + 14 }, centered());
        eng.renderer.end();
    }
};

/// Drawn over the frozen game.
pub const PausedState = struct {
    app: *App,

    pub fn update(self: *PausedState, eng: *Engine, delta: f64) void {
        _ = delta;
        if (eng.actions.pressed(.pause)) {
            self.app.resume_();
        } else if (eng.actions.pressed(.back)) {
            self.app.toTitle();
        }
    }

    pub fn render(self: *PausedState, eng: *Engine, alpha: f32) void {
        _ = self;
        _ = alpha;
        drawBanner(eng, "PAUSED", "P to resume, Esc for the title");
    }
};

/// "LEVEL CLEAR!" or "GAME OVER" over the frozen game, until the player
/// presses on to the title.
pub const MessageState = struct {
    app: *App,
    text: []const u8 = "",

    pub fn update(self: *MessageState, eng: *Engine, delta: f64) void {
        _ = delta;
        if (eng.actions.pressed(.confirm) or eng.actions.pressed(.jump) or eng.actions.pressed(.back)) {
            self.app.toTitle();
        }
    }

    pub fn render(self: *MessageState, eng: *Engine, alpha: f32) void {
        _ = alpha;
        var buf: [64]u8 = undefined;
        const coins = std.fmt.bufPrint(&buf, "{d} coins. Press Enter", .{self.app.play.coins_collected}) catch "";
        drawBanner(eng, self.text, coins);
    }
};

/// Dims the screen and shows `title` with `hint` under it.
fn drawBanner(eng: *Engine, title: []const u8, hint: []const u8) void {
    const size = logicalSize(eng);
    eng.renderer.begin(.logical);
    eng.renderer.drawFilledRect(RectF.fromPosSize(0, 0, size.x, size.y), Color.from(0, 0, 0, 140));
    _ = eng.renderer.drawText(title, .{ .x = size.x / 2, .y = size.y * 0.35 }, .{
        .scale = 2,
        .@"align" = .center,
        .shadow = Shadow,
    });
    _ = eng.renderer.drawText(hint, .{ .x = size.x / 2, .y = size.y * 0.55 }, centered());
    eng.renderer.end();
}

fn centered() pixzig.TextStyle {
    return .{ .@"align" = .center, .shadow = Shadow };
}

fn logicalSize(eng: *Engine) pixzig.Vec2F {
    return .{
        .x = @floatFromInt(eng.viewport.logicalSize.x),
        .y = @floatFromInt(eng.viewport.logicalSize.y),
    };
}
