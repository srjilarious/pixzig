const std = @import("std");
const pixzig = @import("pixzig");
const zaudio = pixzig.zaudio;

const FpsCounter = pixzig.utils.FpsCounter;

// Audio and the action map are both engine systems the app opts into.
const Action = enum { shoot, next, show, quit };
const AppRunner = pixzig.AppRunner(App, .{
    .audioOpts = .{ .enabled = true },
    .actionOpts = .{ .Action = Action },
});

pub const App = struct {
    alloc: std.mem.Allocator,
    testVal: i32,
    fps: FpsCounter,

    pub fn init(allocator: std.mem.Allocator, engine: *AppRunner.Engine) !*App {
        engine.audio.loadSound("laserShoot", "assets/laserShoot.wav") catch |err| {
            std.log.err("Error loading sound: {}\n", .{err});
        };

        try engine.actions.bind(.shoot, .{ .key = .left });
        try engine.actions.bind(.next, .{ .key = .right });
        try engine.actions.bind(.show, .{ .key = .space });
        try engine.actions.bind(.quit, .{ .key = .escape });

        const app = try allocator.create(App);
        app.* = .{
            .alloc = allocator,
            .testVal = 123,
            // .audioEngine = engine, .sample = sample,
            .fps = FpsCounter.init(),
        };

        return app; //.{ .testVal = 123, .audioEngine = engine, .sample = sample, .fps = FpsCounter.init() };
    }

    pub fn deinit(self: *App) void {
        // self.sample.destroy();
        // self.audioEngine.destroy();
        // zaudio.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.info("FPS: {}", .{self.fps.fps()});
        }

        if (eng.actions.pressed(.shoot)) {
            std.log.info("Left!\n", .{});
            eng.audio.playSound("laserShoot") catch |err| {
                std.log.err("Error playing sound: {}\n", .{err});
            };

            // self.sample.start() catch |err| {
            //     std.log.info("Error playing sound: {}\n", .{err});
            // };
            self.testVal -= 1;
        }
        if (eng.actions.pressed(.next)) {
            std.log.info("Right!\n", .{});
            self.testVal += 1;
        }
        if (eng.actions.pressed(.show)) {
            std.log.info("Context: {}\n", .{self.testVal});
        }
        if (eng.actions.pressed(.quit)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 255, 255);
        self.fps.renderTick();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Game Loop Example", .{});

    const appRunner = try AppRunner.init("Pixzig Game Loop Example.", init.gpa, .{});
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
