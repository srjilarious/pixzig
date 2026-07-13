/// Demonstrates loading assets via a JSON asset manifest.
///
/// The build wires in `manifest_options` pointing at either the
/// source-tree JSON (dev) or the packaged copy (--package).
///
/// Controls: U = unload / reload the "game" group   ESC = quit
const std = @import("std");
const pixzig = @import("pixzig");
const manifest_options = @import("manifest_options");
const zmath = pixzig.zmath;

const Vec2F = pixzig.common.Vec2F;
const Sprite = pixzig.sprites.Sprite;
const FpsCounter = pixzig.utils.FpsCounter;
const AssetManifest = pixzig.AssetManifest;

pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    alloc: std.mem.Allocator,
    eng: *AppRunner.Engine,
    manifest: AssetManifest,
    group_loaded: bool,
    sprite_tex: ?*pixzig.resources.TextureHandle,
    spr: Sprite,
    /// World position tracked separately from sprite.dest (which is pixels).
    pos: Vec2F,
    vel: Vec2F,
    fps: FpsCounter,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        var manifest = if (manifest_options.manifest_path.len > 0)
            try AssetManifest.loadFromFile(alloc, &eng.resources, manifest_options.manifest_path)
        else
            try AssetManifest.loadFromJson(alloc, &eng.resources, manifest_options.manifest_json, manifest_options.manifest_base_dir);
        errdefer manifest.deinit();

        try manifest.loadGroup("game");

        const sprite_tex = try eng.resources.acquireTexture("player_right_1");

        const init_pos = Vec2F{ .x = 100, .y = 100 };
        var spr = Sprite.create(sprite_tex, .{ .x = 16, .y = 16 });
        spr.setPos(@intFromFloat(init_pos.x), @intFromFloat(init_pos.y));

        const app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .eng = eng,
            .manifest = manifest,
            .group_loaded = true,
            .sprite_tex = sprite_tex,
            .spr = spr,
            .pos = init_pos,
            .vel = .{ .x = 60, .y = 45 },
            .fps = FpsCounter.init(),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        if (self.sprite_tex) |t| t.release();
        self.manifest.deinit();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        if (eng.inputs.keyboard.pressed(.escape)) return false;

        if (eng.inputs.keyboard.pressed(.u)) {
            if (self.group_loaded) {
                std.log.info("Unloading 'game' group", .{});
                if (self.sprite_tex) |t| {
                    t.release();
                    self.sprite_tex = null;
                }
                self.manifest.unloadGroup("game");
                self.group_loaded = false;
            } else {
                std.log.info("Reloading 'game' group", .{});
                self.manifest.loadGroup("game") catch |err| {
                    std.log.err("Failed to reload group: {}", .{err});
                    return true;
                };
                self.group_loaded = true;
                self.sprite_tex = eng.resources.acquireTexture("player_right_1") catch null;
                if (self.sprite_tex) |t| {
                    self.spr = Sprite.create(t, .{ .x = 16, .y = 16 });
                    self.spr.setPos(@intFromFloat(self.pos.x), @intFromFloat(self.pos.y));
                }
            }
        }

        if (!self.group_loaded) return true;

        const dt: f32 = @floatCast(delta / 1000.0);
        self.pos.x += self.vel.x * dt;
        self.pos.y += self.vel.y * dt;

        const fb_w: f32 = @floatFromInt(eng.window_state.framebuffer_size.x);
        const fb_h: f32 = @floatFromInt(eng.window_state.framebuffer_size.y);

        if (self.pos.x < 0) { self.pos.x = 0; self.vel.x = @abs(self.vel.x); }
        if (self.pos.y < 0) { self.pos.y = 0; self.vel.y = @abs(self.vel.y); }
        if (self.pos.x + self.spr.size.x > fb_w) { self.pos.x = fb_w - self.spr.size.x; self.vel.x = -@abs(self.vel.x); }
        if (self.pos.y + self.spr.size.y > fb_h) { self.pos.y = fb_h - self.spr.size.y; self.vel.y = -@abs(self.vel.y); }

        self.spr.setPos(@intFromFloat(self.pos.x), @intFromFloat(self.pos.y));
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.05, 0.05, 0.15, 1.0);
        self.fps.renderTick();

        if (!self.group_loaded) return;

        eng.renderer.begin(eng.projMat);
        eng.renderer.drawSprite(&self.spr);
        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Manifest Example", .{});
    const appRunner = try AppRunner.init("Pixzig Manifest Example", init.gpa, .{});
    const app = try App.init(init.gpa, appRunner.engine);
    appRunner.run(app);
}
