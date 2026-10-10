const std = @import("std");
const pixzig = @import("pixzig");

const AppRunner = pixzig.AppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    /// Where the bouncing square is, in logical pixels.
    pos: pixzig.Vec2F,
    vel: pixzig.Vec2F,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        _ = eng;
        const app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .pos = .{ .x = 40, .y = 40 },
            .vel = .{ .x = 0.08, .y = 0.06 },
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.alloc.destroy(self);
    }

    /// Runs at a fixed 120 Hz; `deltaMs` is the step length in milliseconds.
    /// Return false to quit.
    pub fn update(self: *App, eng: *AppRunner.Engine, deltaMs: f64) bool {
        if (eng.inputs.keyboard.pressed(.escape)) return false;

        const dt: f32 = @floatCast(deltaMs);
        self.pos.x += self.vel.x * dt;
        self.pos.y += self.vel.y * dt;

        const size = eng.viewport.logicalSize;
        if (self.pos.x < 0 or self.pos.x + 16 > @as(f32, @floatFromInt(size.x))) self.vel.x = -self.vel.x;
        if (self.pos.y < 0 or self.pos.y + 16 > @as(f32, @floatFromInt(size.y))) self.vel.y = -self.vel.y;
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(26, 26, 51, 255);

        eng.renderer.begin(.logical);
        eng.renderer.drawFilledRect(
            pixzig.RectF.fromPosSize(@intFromFloat(self.pos.x), @intFromFloat(self.pos.y), 16, 16),
            pixzig.Color.from(255, 200, 60, 255),
        );
        _ = eng.renderer.drawString("Hello from pixzig! Esc quits.", .{ .x = 8, .y = 8 });
        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("my_game", init.gpa, .{
        .windowSize = .{ .x = 960, .y = 540 },
        .logicalSize = .{ .x = 320, .y = 180 },
        .scalePolicy = .integer_fit,
    });
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
