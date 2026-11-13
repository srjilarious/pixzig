//! Hopper: a one-level platformer. Run, jump, stomp the beetles, grab the
//! coins and reach the flag.
//!
//! Files:
//!   main.zig     the App: engine setup, controls, and switching screens
//!   play.zig     the level, the player, walkers, coins and the HUD
//!   screens.zig  title, pause and level clear / game over
//!   body.zig     falling and bumping into tiles, shared by everything
//!   config.zig   gameplay numbers, loaded from assets/tuning.json
//!   sheet.zig    where each sprite is in assets/hopper.png

const std = @import("std");
const pixzig = @import("pixzig");
const manifest_options = @import("manifest_options");

const config = @import("config.zig");
const PlayState = @import("play.zig").PlayState;
const screens = @import("screens.zig");

/// Named controls. Bound to keys and gamepad buttons in `bindControls`.
pub const Action = enum { left, right, jump, confirm, pause, back };

const engine_options: pixzig.EngineOptions = .{
    .actionOpts = .{ .Action = Action },
    // Loads build.zig's "boot" asset group before App.init.
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
    sheet_tex: *pixzig.TextureHandle,
    title: screens.TitleState,
    play: PlayState,
    paused: screens.PausedState,
    message: screens.MessageState,
    states: StateMgr,

    pub fn init(alloc: std.mem.Allocator, eng: *Engine) !*App {
        try bindControls(eng);

        const app = try alloc.create(App);
        errdefer alloc.destroy(app);
        app.* = .{
            .alloc = alloc,
            .eng = eng,
            .tuning = try config.load(alloc, &eng.manifest, "tuning"),
            .sheet_tex = try eng.resources.getTexture("hopper"),
            .title = .{ .app = app },
            .play = undefined,
            .paused = .{ .app = app },
            .message = .{ .app = app },
            .states = undefined,
        };
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

/// Keyboard and gamepad controls for every action.
fn bindControls(eng: *Engine) !void {
    const a = eng.actions;
    try a.bind(.left, .{ .key = .left });
    try a.bind(.left, .{ .key = .a });
    try a.bind(.left, .{ .gamepad_button = .dpad_left });
    try a.bind(.right, .{ .key = .right });
    try a.bind(.right, .{ .key = .d });
    try a.bind(.right, .{ .gamepad_button = .dpad_right });
    try a.bind(.jump, .{ .key = .space });
    try a.bind(.jump, .{ .key = .up });
    try a.bind(.jump, .{ .key = .w });
    try a.bind(.jump, .{ .key = .z });
    try a.bind(.jump, .{ .gamepad_button = .a });
    try a.bind(.confirm, .{ .key = .enter });
    try a.bind(.confirm, .{ .gamepad_button = .start });
    try a.bind(.pause, .{ .key = .p });
    try a.bind(.pause, .{ .gamepad_button = .start });
    try a.bind(.back, .{ .key = .escape });
    try a.bind(.back, .{ .gamepad_button = .back });
}

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
