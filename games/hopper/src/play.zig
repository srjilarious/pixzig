//! Playing a level: the frog, the walkers, the coins and the goal flag.

const std = @import("std");
const pixzig = @import("pixzig");
const tile = pixzig.tile;
const RectF = pixzig.RectF;
const Vec2F = pixzig.Vec2F;
const Color = pixzig.Color;
const Flip = pixzig.sprites.Flip;

const App = @import("main.zig").App;
const Engine = @import("main.zig").Engine;
const Tuning = @import("config.zig").Tuning;
const Body = @import("body.zig").Body;
const solidAt = @import("body.zig").solidAt;
const sheet = @import("sheet.zig");

/// The tilemap asset ids, in play order (see manifest.json). Hopper
/// has one; finishing the last one wins the game.
const levels = [_][]const u8{"level1"};

/// The sky. `renderer.clear` takes bytes rather than a Color.
pub const Sky = [3]u8{ 120, 180, 240 };

// Hitbox sizes. Sprites are 16x16 cells drawn centred over the hitbox,
// with their bottoms lined up.
const PlayerW = 12;
const PlayerH = 13;
const WalkerW = 14;
const WalkerH = 11;
const CoinSize = 10;

const Player = struct {
    body: Body,
    facing_left: bool = false,
    /// Time left to jump after leaving the ground (see Tuning.coyote_ms).
    coyote_ms: f64 = 0,
    /// Time left on a jump pressed in the air (see Tuning.jump_buffer_ms).
    jump_buffer_ms: f64 = 0,
    /// Distance run, for picking the run frame.
    run_px: f32 = 0,
};

const Walker = struct {
    body: Body,
    /// -1 walking left, 1 walking right.
    dir: f32 = -1,
    /// Time left on screen once squashed; null while alive.
    squashed_ms: ?f64 = null,
};

const Coin = struct {
    rect: RectF,
    taken: bool = false,
};

pub const PlayState = struct {
    alloc: std.mem.Allocator,
    app: *App,
    level_index: usize = 0,
    map_renderer: tile.TileMapRenderer,
    camera: pixzig.Camera2D = .init(),
    player: Player,
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
            .map_renderer = try tile.TileMapRenderer.init(alloc, &app.eng.resources, levels[0]),
            .player = .{ .body = Body.init(0, 0, PlayerW, PlayerH) },
        };
    }

    pub fn deinit(self: *PlayState) void {
        self.map_renderer.deinit();
        self.walkers.deinit(self.alloc);
        self.coins.deinit(self.alloc);
    }

    fn tun(self: *const PlayState) *const Tuning {
        return &self.app.tuning;
    }

    /// The level's "Main" layer: the one the player stands on and bumps
    /// into. Other layers are only drawn.
    fn mainLayer(self: *PlayState) *tile.TileLayer {
        return self.map_renderer.tileMap().layerByName("Main") orelse &self.map_renderer.tileMap().layers.items[0];
    }

    /// Starts from the first level with full lives and no coins.
    pub fn newGame(self: *PlayState) !void {
        self.lives = self.tun().lives;
        self.coins_collected = 0;
        try self.loadLevel(0);
    }

    fn loadLevel(self: *PlayState, index: usize) !void {
        if (index != self.level_index) {
            const renderer = try tile.TileMapRenderer.init(self.alloc, &self.app.eng.resources, levels[index]);
            self.map_renderer.deinit();
            self.map_renderer = renderer;
            self.level_index = index;
        }
        try self.restartLevel();
    }

    /// Puts everything back where the level's "Spawns" object group says:
    /// the player at "player_start", a walker at each "walker", a coin at
    /// each "coin", and the finish at "goal".
    fn restartLevel(self: *PlayState) !void {
        const map = self.map_renderer.tileMap();
        const layer = self.mainLayer();
        self.walkers.clearRetainingCapacity();
        self.coins.clearRetainingCapacity();
        self.player = .{ .body = Body.init(16, 16, PlayerW, PlayerH) };
        self.dying_ms = 0;

        const spawns = map.objectGroupByName("Spawns") orelse return error.NoSpawns;
        for (spawns.objects.items) |*obj| {
            const class = obj.class orelse continue;
            const x: f32 = @floatFromInt(obj.pos.x);
            const y: f32 = @floatFromInt(obj.pos.y);
            const w: f32 = @floatFromInt(obj.size.x);
            const h: f32 = @floatFromInt(obj.size.y);
            // Spawns are tile-sized boxes; stand each body on the box's
            // bottom edge, centred across it.
            if (std.mem.eql(u8, class, "player_start")) {
                self.player.body.teleport(x + (w - PlayerW) / 2, y + h - PlayerH);
            } else if (std.mem.eql(u8, class, "walker")) {
                try self.walkers.append(self.alloc, .{ .body = Body.init(x + (w - WalkerW) / 2, y + h - WalkerH, WalkerW, WalkerH) });
            } else if (std.mem.eql(u8, class, "coin")) {
                try self.coins.append(self.alloc, .{ .rect = RectF.fromPosSize(x + (w - CoinSize) / 2, y + (h - CoinSize) / 2, CoinSize, CoinSize) });
            } else if (std.mem.eql(u8, class, "goal")) {
                self.goal = RectF.fromPosSize(x, y, w, h);
            }
        }

        const map_w: f32 = @floatFromInt(layer.size.x * layer.tileSize.x);
        const map_h: f32 = @floatFromInt(layer.size.y * layer.tileSize.y);
        self.camera.bounds = .{ .l = 0, .t = 0, .r = map_w, .b = map_h };
        self.camera.pos = self.player.body.rect.centerF();
    }

    pub fn update(self: *PlayState, eng: *Engine, delta: f64) void {
        const actions = eng.actions;
        if (actions.pressed(.pause) or actions.pressed(.back)) {
            self.app.pause();
            return;
        }
        self.elapsed_ms += delta;
        const dt: f32 = @floatCast(delta / 1000.0);
        const layer = self.mainLayer();

        if (self.dying_ms > 0) {
            self.dying_ms -= delta;
            if (self.dying_ms <= 0) self.afterDeath();
            return;
        }

        self.updatePlayer(eng, dt, delta, layer);
        for (self.walkers.items) |*w| updateWalker(w, dt, delta, layer, self.tun());
        // Squashed walkers that have finished showing are gone.
        var i: usize = 0;
        while (i < self.walkers.items.len) {
            const gone = if (self.walkers.items[i].squashed_ms) |ms| ms <= 0 else false;
            if (gone) _ = self.walkers.swapRemove(i) else i += 1;
        }

        self.checkWalkers();
        self.checkCoins();
        if (self.player.body.rect.intersects(&self.goal)) {
            self.finishLevel();
            return;
        }

        // Fell into a pit.
        const map_h: f32 = @floatFromInt(layer.size.y * layer.tileSize.y);
        if (self.player.body.rect.t > map_h) self.die();

        self.camera.follow(self.player.body.rect.centerF(), delta, .{
            .deadzone = .{ .x = self.tun().camera_deadzone_x, .y = 0 },
            .smoothing = self.tun().camera_smoothing,
        });
    }

    fn updatePlayer(self: *PlayState, eng: *Engine, dt: f32, delta: f64, layer: *tile.TileLayer) void {
        const t = self.tun();
        const actions = eng.actions;
        const p = &self.player;

        // Run: speed up toward the held direction, or slow to a stop.
        var dir: f32 = 0;
        if (actions.down(.left)) dir -= 1;
        if (actions.down(.right)) dir += 1;
        if (dir != 0) {
            const accel = if (p.body.on_ground) t.ground_accel else t.air_accel;
            p.body.vel.x = approach(p.body.vel.x, dir * t.run_speed, accel * dt);
            p.facing_left = dir < 0;
        } else if (p.body.on_ground) {
            p.body.vel.x = approach(p.body.vel.x, 0, t.ground_friction * dt);
        }

        // Jump, with a little forgiveness either side of being on the
        // ground (coyote time and the jump buffer).
        p.coyote_ms = if (p.body.on_ground) t.coyote_ms else p.coyote_ms - delta;
        p.jump_buffer_ms = if (actions.pressed(.jump)) t.jump_buffer_ms else p.jump_buffer_ms - delta;
        if (p.jump_buffer_ms > 0 and p.coyote_ms > 0) {
            p.body.vel.y = -t.jump_speed;
            p.jump_buffer_ms = 0;
            p.coyote_ms = 0;
        }
        // Letting go early cuts the jump short.
        if (actions.released(.jump) and p.body.vel.y < 0) p.body.vel.y *= t.jump_release_cut;

        _ = p.body.step(dt, layer, t);

        // Keep inside the level's left and right edges.
        const map_w: f32 = @floatFromInt(layer.size.x * layer.tileSize.x);
        if (p.body.rect.l < 0) p.body.teleport(0, p.body.rect.t);
        if (p.body.rect.r > map_w) p.body.teleport(map_w - PlayerW, p.body.rect.t);

        p.run_px += @abs(p.body.vel.x) * dt;
    }

    /// Walks back and forth, turning at walls (and, by default, at drops).
    fn updateWalker(w: *Walker, dt: f32, delta: f64, layer: *tile.TileLayer, t: *const Tuning) void {
        if (w.squashed_ms) |*ms| {
            ms.* -= delta;
            return;
        }
        w.body.vel.x = w.dir * t.walker_speed;
        const hits = w.body.step(dt, layer, t);
        if (hits.wall) w.dir = -w.dir;

        if (t.walkers_turn_at_ledges and w.body.on_ground) {
            const r = w.body.rect;
            const ahead_x = if (w.dir > 0) r.r + 1 else r.l - 1;
            if (!solidAt(layer, ahead_x, r.b + 1)) w.dir = -w.dir;
        }
    }

    /// Landing on a walker squashes it and bounces the player up; touching
    /// one any other way costs a life.
    fn checkWalkers(self: *PlayState) void {
        const p = &self.player;
        for (self.walkers.items) |*w| {
            if (w.squashed_ms != null) continue;
            if (!p.body.rect.intersects(&w.body.rect)) continue;

            // Falling, and the player's feet were above its top a tick ago.
            const was_above = p.body.prev.y + PlayerH <= w.body.rect.t + 2;
            if (p.body.vel.y > 0 and was_above) {
                w.squashed_ms = self.tun().squash_ms;
                const jump_held = self.app.eng.actions.down(.jump);
                p.body.vel.y = -(if (jump_held) self.tun().jump_speed else self.tun().stomp_bounce);
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
        if (self.level_index + 1 < levels.len) {
            self.loadLevel(self.level_index + 1) catch |err| {
                std.log.err("Couldn't load level '{s}': {s}", .{ levels[self.level_index + 1], @errorName(err) });
                self.app.eng.quit();
            };
            return;
        }
        self.app.showMessage("LEVEL CLEAR!");
    }

    pub fn render(self: *PlayState, eng: *Engine, alpha: f32) void {
        eng.renderer.clear(Sky[0], Sky[1], Sky[2], 255);
        self.map_renderer.render(&self.camera, &eng.viewport);

        const app = self.app;
        eng.renderer.begin(.{ .camera = &self.camera });

        const coin_frame: usize = @intFromFloat(@mod(self.elapsed_ms / 120.0, sheet.CoinFrames));
        for (self.coins.items) |c| {
            if (c.taken) continue;
            app.drawCell(sheet.Coin1 + coin_frame, c.rect.centerF().x - 8, c.rect.centerF().y - 8, .none);
        }

        for (self.walkers.items) |*w| {
            const cell: usize = if (w.squashed_ms != null)
                sheet.BeetleSquashed
            else if (@mod(self.elapsed_ms, 300) < 150) sheet.BeetleWalk1 else sheet.BeetleWalk2;
            drawOnBody(app, cell, &w.body, alpha, .none);
        }

        // Blinks while dying.
        const blink_off = self.dying_ms > 0 and @mod(self.dying_ms, 160) < 80;
        if (!blink_off) {
            const flip: Flip = if (self.player.facing_left) .horz else .none;
            drawOnBody(app, self.playerCell(), &self.player.body, alpha, flip);
        }
        eng.renderer.end();

        // The HUD, in screen space.
        eng.renderer.begin(.logical);
        var buf: [64]u8 = undefined;
        const hud = std.fmt.bufPrint(&buf, "Coins {d}   Lives {d}", .{ self.coins_collected, self.lives }) catch "";
        _ = eng.renderer.drawText(hud, .{ .x = 6, .y = 4 }, .{ .shadow = Color.from(0, 0, 0, 255) });
        eng.renderer.end();
    }

    fn playerCell(self: *const PlayState) usize {
        const p = &self.player;
        const base: usize = if (!p.body.on_ground)
            sheet.FrogJump
        else if (@abs(p.body.vel.x) > 5)
            (if (@mod(p.run_px, 16) < 8) sheet.FrogRun1 else sheet.FrogRun2)
        else
            sheet.FrogIdle;
        return base;
    }
};

/// Draws a 16x16 sheet cell centred across `body` with its bottom on the
/// body's bottom.
fn drawOnBody(app: *App, cell: usize, body: *const Body, alpha: f32, flip: Flip) void {
    const pos = body.drawPos(alpha);
    const x = pos.x + body.rect.width() / 2 - sheet.CellSize / 2;
    const y = pos.y + body.rect.height() - sheet.CellSize;
    app.drawCell(cell, x, y, flip);
}

/// `value` moved toward `target` by at most `step`.
fn approach(value: f32, target: f32, step: f32) f32 {
    if (value < target) return @min(value + step, target);
    return @max(value - step, target);
}
