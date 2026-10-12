const std = @import("std");
const pixzig = @import("pixzig");

const Color = pixzig.Color;
const manifest_options = @import("manifest_options");

// Audio is on by default; the sounds and the music track come from the
// manifest's boot group (see `audio_ex` in build.zig).
const Action = enum { laser, boom, music, synth, pause, volUp, volDown, quit };
const AppRunner = pixzig.AppRunner(App, .{
    .manifestOpts = manifest_options,
    .actionOpts = .{ .Action = Action },
});

/// A tiny synth for `playStream`: a square-wave arpeggio. Once the stream
/// starts, only the audio thread touches it, so it needs no locking; the
/// game just stops the stream when it's done.
const Synth = struct {
    sampleRate: f32,
    phase: f32 = 0,
    frame: u64 = 0,

    const notes = [_]f32{ 220.0, 277.18, 329.63, 440.0 };
    const noteFrames = 6000;

    fn fill(ctx: ?*anyopaque, out: []f32, channels: u32) usize {
        const self: *Synth = @ptrCast(@alignCast(ctx.?));
        const frames = out.len / channels;
        for (0..frames) |i| {
            const freq = notes[@intCast((self.frame / noteFrames) % notes.len)];
            self.phase = @mod(self.phase + freq / self.sampleRate, 1.0);
            const sample: f32 = if (self.phase < 0.5) 0.08 else -0.08;
            for (0..channels) |c| out[i * channels + c] = sample;
            self.frame += 1;
        }
        return frames;
    }
};

pub const App = struct {
    alloc: std.mem.Allocator,
    synth: Synth,
    synthVoice: ?pixzig.Voice = null,
    paused: bool = false,
    last: []const u8 = "(nothing yet)",

    pub fn init(allocator: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        try eng.actions.bind(.laser, .{ .key = .space });
        try eng.actions.bind(.boom, .{ .key = .b });
        try eng.actions.bind(.music, .{ .key = .m });
        try eng.actions.bind(.synth, .{ .key = .s });
        try eng.actions.bind(.pause, .{ .key = .p });
        try eng.actions.bind(.volUp, .{ .key = .up });
        try eng.actions.bind(.volDown, .{ .key = .down });
        try eng.actions.bind(.quit, .{ .key = .escape });

        const app = try allocator.create(App);
        app.* = .{
            .alloc = allocator,
            .synth = .{ .sampleRate = @floatFromInt(eng.audio.sampleRate()) },
        };
        try eng.audio.playMusic("theme", .{ .fadeMs = 1000 });
        return app;
    }

    pub fn deinit(self: *App) void {
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, _: f64) bool {
        const audio = &eng.audio;

        if (eng.actions.pressed(.laser)) {
            // A little random pan and pitch keeps rapid fire from sounding
            // like one sample on repeat.
            _ = audio.play("laserShoot", .{
                .pan = eng.rng.floatRange(-0.6, 0.6),
                .pitch = eng.rng.floatRange(0.9, 1.1),
            }) catch |err| std.log.err("laser: {}", .{err});
            self.last = "laser";
        }
        if (eng.actions.pressed(.boom)) {
            _ = audio.play("explosion", .{ .volume = 0.8 }) catch |err| std.log.err("boom: {}", .{err});
            self.last = "explosion";
        }
        if (eng.actions.pressed(.music)) {
            if (audio.musicPlaying()) {
                audio.stopMusic(.{ .fadeOutMs = 1000 });
            } else {
                audio.playMusic("theme", .{ .fadeMs = 1000 }) catch |err| std.log.err("music: {}", .{err});
            }
        }
        if (eng.actions.pressed(.synth)) {
            if (self.synthVoice) |v| {
                audio.stop(v, .{ .fadeOutMs = 200 });
                self.synthVoice = null;
            } else {
                // The synth is only touched by the audio thread while it
                // plays; resetting it here is safe because it's stopped.
                self.synth.frame = 0;
                self.synthVoice = audio.playStream(Synth.fill, &self.synth, .{ .channels = 1 }) catch |err| blk: {
                    std.log.err("synth: {}", .{err});
                    break :blk null;
                };
            }
        }
        if (eng.actions.pressed(.pause)) {
            self.paused = !self.paused;
            if (self.paused) audio.pauseAll() else audio.resumeAll();
        }
        if (eng.actions.pressed(.volUp)) {
            audio.setBusVolume(.music, @min(1.0, audio.busVolume(.music) + 0.1));
        }
        if (eng.actions.pressed(.volDown)) {
            audio.setBusVolume(.music, @max(0.0, audio.busVolume(.music) - 0.1));
        }
        return !eng.actions.pressed(.quit);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(20, 20, 60, 255);
        eng.renderer.begin(.logical);

        const white = Color.from(255, 255, 255, 255);
        const dim = Color.from(160, 160, 200, 255);
        var buf: [96]u8 = undefined;
        var y: i32 = 30;
        const lines = [_][]const u8{
            "Space = laser   B = explosion",
            "M = music on/off (1s fades)   S = synth stream",
            "P = pause/resume all   Up/Down = music volume",
            "Esc = quit",
        };
        for (lines) |line| {
            _ = eng.renderer.drawStringColored(line, .{ .x = 30, .y = y }, dim);
            y += 30;
        }

        y += 20;
        const status = std.fmt.bufPrint(&buf, "last: {s}   music: {s}   volume: {d:.1}", .{
            self.last,
            if (eng.audio.musicPlaying()) "playing" else "stopped",
            eng.audio.busVolume(.music),
        }) catch "";
        _ = eng.renderer.drawStringColored(status, .{ .x = 30, .y = y }, white);
        y += 30;
        const state = if (self.paused) "PAUSED" else if (self.synthVoice != null) "synth on" else "";
        _ = eng.renderer.drawStringColored(state, .{ .x = 30, .y = y }, white);

        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("Pixzig Audio Example", init.gpa, .{});
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
