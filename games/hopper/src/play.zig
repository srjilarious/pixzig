//! Playing a level: the rules that tie the player, walkers, coins and goal
//! together (stomp or get hurt, collect, finish), lives, and the camera.
//! How each thing moves lives in its own file.

const std = @import("std");
const pixzig = @import("pixzig");
const RectF = pixzig.RectF;
const Flip = pixzig.sprites.Flip;

const App = @import("main.zig").App;
const Engine = @import("main.zig").Engine;
const Tuning = @import("config.zig").Tuning;
const levels = @import("level.zig");
const Level = levels.Level;
const player_mod = @import("player.zig");
const Player = player_mod.Player;
const walker_mod = @import("walker.zig");
const Walker = walker_mod.Walker;
const coin_mod = @import("coin.zig");
const Coin = coin_mod.Coin;
const hud = @import("hud.zig");
const sheet = @import("sheet.zig");

pub const PlayState = struct {
    alloc: std.mem.Allocator,
    app: *App,
    level_index: usize = 0,
    level: Level,
    camera: pixzig.Camera2D = .init(),
    player: Player = .init(0, 0),
    walkers: std.ArrayList(Walker) = .empty,
    coins: std.ArrayList(Coin) = .empty,
    /// Touching this finishes the level.
    goal: RectF = RectF.fromPosSize(0, 0, 0, 0),
    lives: u8 = 0,
    coins_collected: u32 = 0,
    /// Counts up while playing, for animations.
    elapsed_ms: f64 = 0,
    /// Counts down after the player dies; the level restarts at zero.
    dying_ms: f64 = 0,

    pub fn init(alloc: std.mem.Allocator, app: *App) !PlayState {
        return .{
            .alloc = alloc,
            .app = app,
            .level = try Level.init(alloc, &app.eng.resources, levels.order[0]),
        };
    }

    pub fn deinit(self: *PlayState) void {
        self.level.deinit();
        self.walkers.deinit(self.alloc);
        self.coins.deinit(self.alloc);
    }

    fn tun(self: *const PlayState) *const Tuning {
        return &self.app.tuning;
    }

    /// Starts from the first level with full lives and no coins.
    pub fn newGame(self: *PlayState) !void {
        self.lives = self.tun().lives;
        self.coins_collected = 0;
        try self.loadLevel(0);
    }

    fn loadLevel(self: *PlayState, index: usize) !void {
        if (index != self.level_index) {
            const next = try Level.init(self.alloc, &self.app.eng.resources, levels.order[index]);
            self.level.deinit();
            self.level = next;
            self.level_index = index;
        }
        try self.restartLevel();
    }

    /// Puts everything back where the level's "Spawns" layer says: the
    /// player at "player_start", a walker at each "walker", a coin at each
    /// "coin", and the finish at "goal".
    fn restartLevel(self: *PlayState) !void {
        self.walkers.clearRetainingCapacity();
        self.coins.clearRetainingCapacity();
        self.player = .init(16, 16);
        self.dying_ms = 0;

        for (try self.level.spawns()) |*obj| {
            const class = obj.class orelse continue;
            if (std.mem.eql(u8, class, "player_start")) {
                const pos = levels.standOn(obj, player_mod.Width, player_mod.Height);
                self.player.body.teleport(pos.x, pos.y);
            } else if (std.mem.eql(u8, class, "walker")) {
                const pos = levels.standOn(obj, walker_mod.Width, walker_mod.Height);
                try self.walkers.append(self.alloc, .init(pos.x, pos.y));
            } else if (std.mem.eql(u8, class, "coin")) {
                const pos = levels.centreIn(obj, coin_mod.Size);
                try self.coins.append(self.alloc, .init(pos.x, pos.y));
            } else if (std.mem.eql(u8, class, "goal")) {
                self.goal = levels.objectRect(obj);
            }
        }

        self.camera.bounds = .{ .l = 0, .t = 0, .r = self.level.width(), .b = self.level.height() };
        self.camera.pos = self.player.body.rect.centerF();
    }

    pub fn update(self: *PlayState, eng: *Engine, delta: f64) void {
        if (eng.actions.pressed(.pause) or eng.actions.pressed(.back)) {
            self.app.pause();
            return;
        }
        self.elapsed_ms += delta;

        if (self.dying_ms > 0) {
            self.dying_ms -= delta;
            if (self.dying_ms <= 0) self.afterDeath();
            return;
        }

        self.player.update(eng, self.tun(), &self.level, delta);
        for (self.walkers.items) |*w| w.update(self.tun(), &self.level, delta);
        // Squashed walkers that have finished showing are gone.
        var i: usize = 0;
        while (i < self.walkers.items.len) {
            if (self.walkers.items[i].isGone()) _ = self.walkers.swapRemove(i) else i += 1;
        }

        self.checkWalkers();
        self.checkCoins();
        if (self.player.body.rect.intersects(&self.goal)) {
            self.finishLevel();
            return;
        }

        // Fell into a pit.
        if (self.player.body.rect.t > self.level.height()) self.die();

        self.camera.follow(self.player.body.rect.centerF(), delta, .{
            .deadzone = .{ .x = self.tun().camera_deadzone_x, .y = 0 },
            .smoothing = self.tun().camera_smoothing,
        });
    }

    /// Landing on a walker squashes it and bounces the player up; touching
    /// one any other way costs a life.
    fn checkWalkers(self: *PlayState) void {
        const p = &self.player;
        for (self.walkers.items) |*w| {
            if (w.isSquashed()) continue;
            if (!p.body.rect.intersects(&w.body.rect)) continue;

            if (p.landedOn(&w.body.rect)) {
                w.squash(self.tun());
                p.bounce(self.app.eng.actions.down(.jump), self.tun());
            } else {
                self.die();
                return;
            }
        }
    }

    fn checkCoins(self: *PlayState) void {
        for (self.coins.items) |*c| {
            if (c.taken or !self.player.body.rect.intersects(&c.rect)) continue;
            c.taken = true;
            self.coins_collected += 1;
        }
    }

    fn die(self: *PlayState) void {
        if (self.dying_ms > 0) return;
        self.dying_ms = self.tun().death_pause_ms;
    }

    /// The death pause is over: try again, or it's game over.
    fn afterDeath(self: *PlayState) void {
        self.lives -|= 1;
        if (self.lives == 0) {
            self.app.showMessage("GAME OVER");
            return;
        }
        self.restartLevel() catch |err| {
            std.log.err("Couldn't restart the level: {s}", .{@errorName(err)});
            self.app.eng.quit();
        };
    }

    fn finishLevel(self: *PlayState) void {
        if (self.level_index + 1 < levels.order.len) {
            self.loadLevel(self.level_index + 1) catch |err| {
                std.log.err("Couldn't load level '{s}': {s}", .{ levels.order[self.level_index + 1], @errorName(err) });
                self.app.eng.quit();
            };
            return;
        }
        self.app.showMessage("LEVEL CLEAR!");
    }

    pub fn render(self: *PlayState, eng: *Engine, alpha: f32) void {
        eng.renderer.clear(sheet.Sky[0], sheet.Sky[1], sheet.Sky[2], 255);
        self.level.render(&self.camera, &eng.viewport);

        // The world, through the camera.
        const app = self.app;
        eng.renderer.begin(.{ .camera = &self.camera });
        const coin_cell = coin_mod.cell(self.elapsed_ms);
        for (self.coins.items) |c| {
            if (c.taken) continue;
            const centre = c.rect.centerF();
            app.drawCell(coin_cell, centre.x - sheet.CellSize / 2, centre.y - sheet.CellSize / 2, .none);
        }
        for (self.walkers.items) |*w| {
            app.drawOnBody(w.cell(self.elapsed_ms), &w.body, alpha, .none);
        }
        // Blinks while dying.
        const blink_off = self.dying_ms > 0 and @mod(self.dying_ms, 160) < 80;
        if (!blink_off) {
            const flip: Flip = if (self.player.facing_left) .horz else .none;
            app.drawOnBody(self.player.cell(), &self.player.body, alpha, flip);
        }
        eng.renderer.end();

        hud.draw(eng, self.coins_collected, self.lives);
    }
};
