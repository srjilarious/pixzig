//! Hopper: a one-level platformer. Run, jump, stomp the beetles, grab the
//! coins and reach the flag.
//!
//! Files:
//!   main.zig      the App: engine setup, drawing sprites, switching screens
//!   controls.zig  the named actions and the keys bound to them
//!   play.zig      the rules: stomping, coins, the goal, lives, the camera
//!   player.zig    the frog: running and jumping
//!   walker.zig    the beetles: walking back and forth
//!   coin.zig      the coins
//!   level.zig     the tile map, solid tiles and spawn points
//!   body.zig      falling and bumping into tiles, shared by everything
//!   hud.zig       the coins and lives counter
//!   screens.zig   title, pause and level clear / game over
//!   config.zig    gameplay numbers, loaded from assets/tuning.json
//!   sheet.zig     where each sprite is in assets/hopper.png

const std = @import("std");
const pixzig = @import("pixzig");
const manifest_options = @import("manifest_options");

const config = @import("config.zig");
const controls = @import("controls.zig");
const Body = @import("body.zig").Body;
const PlayState = @import("play.zig").PlayState;
const screens = @import("screens.zig");
const sheet = @import("sheet.zig");
const Flip = pixzig.sprites.Flip;

const engine_options: pixzig.EngineOptions = .{
    // `eng.actions` reports these named controls (see controls.zig).
    .actionOpts = .{ .Action = controls.Action },
    // Loads manifest.json's "boot" asset group before App.init.
    .manifestOpts = manifest_options,
};
pub const Engine = pixzig.Engine(engine_options);
const AppRunner = pixzig.AppRunner(App, engine_options);

pub const GameState = enum { title, play, paused, message };
const StateMgr = pixzig.gamestate.GameStateMgr(Engine, GameState, &[_]type{
    screens.TitleState,
    PlayState,
    screens.PausedState,
    screens.MessageState,
});

pub const App = struct {
    alloc: std.mem.Allocator,
    eng: *Engine,
    tuning: config.Tuning,
    /// One sprite over assets/hopper.png, pointed at a different cell for
    /// each thing drawn (see `drawCell`).
    cell_sprite: pixzig.sprites.Sprite,
    title: screens.TitleState,
    play: PlayState,
    paused: screens.PausedState,
    message: screens.MessageState,
    states: StateMgr,

    pub fn init(alloc: std.mem.Allocator, eng: *Engine) !*App {
        try controls.bind(eng);

        const app = try alloc.create(App);
        errdefer alloc.destroy(app);
        app.* = .{
            .alloc = alloc,
            .eng = eng,
            .tuning = try config.load(alloc, &eng.manifest, "tuning"),
            .cell_sprite = try eng.resources.createSprite("hopper"),
            .title = .{ .app = app },
            .play = undefined,
            .paused = .{ .app = app },
            .message = .{ .app = app },
            .states = undefined,
        };
        app.cell_sprite.setSize(sheet.CellSize, sheet.CellSize);
        app.play = try PlayState.init(alloc, app);
        app.states = StateMgr.init(.{ &app.title, &app.play, &app.paused, &app.message });
        app.states.setCurrState(.title);
        return app;
    }

    pub fn deinit(self: *App) void {
        self.play.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *Engine, delta: f64) void {
        self.states.update(eng, delta);
    }

    pub fn render(self: *App, eng: *Engine, alpha: f32) void {
        self.states.render(eng, alpha);
    }

    /// Draws a sheet cell with its top-left at (x, y), mirrored by `flip`.
    /// The renderer rounds it to whole pixels, so the pixel art doesn't
    /// shimmer between them.
    pub fn drawCell(self: *App, cell: usize, x: f32, y: f32, flip: Flip) void {
        self.cell_sprite.setSrcRect(sheet.rect(cell));
        self.cell_sprite.flip = flip;
        self.cell_sprite.setPosF(x, y);
        self.eng.renderer.drawSprite(&self.cell_sprite);
    }

    /// Draws a sheet cell over `body`, `alpha` of the way between its last
    /// two ticks: centred across it, with the bottoms lined up. Hitboxes are
    /// smaller than the 16x16 cells, so feet touch the ground this way.
    pub fn drawOnBody(self: *App, cell: usize, body: *const Body, alpha: f32, flip: Flip) void {
        const pos = body.drawPos(alpha);
        const x = pos.x + body.rect.width() / 2 - sheet.CellSize / 2;
        const y = pos.y + body.rect.height() - sheet.CellSize;
        self.drawCell(cell, x, y, flip);
    }

    pub fn startGame(self: *App) void {
        self.play.newGame() catch |err| {
            std.log.err("Couldn't start the game: {s}", .{@errorName(err)});
            self.eng.quit();
            return;
        };
        self.states.setCurrState(.play);
    }

    /// Freezes the game under the pause overlay.
    pub fn pause(self: *App) void {
        self.states.push(.paused, .{ .renderBelow = true }) catch {};
    }

    /// Back to the game from the pause overlay. (`resume` is a keyword.)
    pub fn resume_(self: *App) void {
        self.states.pop() catch {};
    }

    /// Freezes the game under `text` (see MessageState).
    pub fn showMessage(self: *App, text: []const u8) void {
        self.message.text = text;
        self.states.push(.message, .{ .renderBelow = true }) catch {};
    }

    pub fn toTitle(self: *App) void {
        self.states.setCurrState(.title);
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Hopper", init.gpa, .{
        .windowSize = .{ .x = 960, .y = 540 },
        // Everything is laid out on a 320x180 screen, scaled up by whole
        // pixels to fit the window.
        .logicalSize = .{ .x = 320, .y = 180 },
        .scalePolicy = .integer_fit,
    });
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
