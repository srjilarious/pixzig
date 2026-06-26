const std = @import("std");

const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const GameStateMgr = pixzig.gamestate.GameStateMgr;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;
const PixzigEngine = pixzig.PixzigEngine;

pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{ .inputOpts = .{ .mouse = true } });

pub const App = struct {
    fps: FpsCounter,
    alloc: std.mem.Allocator,
    eng: *AppRunner.Engine,
    tex: *pixzig.resources.TextureHandle,
    pointer: pixzig.sprites.Sprite,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !App {
        const bigtex = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
        _ = try eng.resources.addSubTexture(bigtex, "guy", RectF.fromCoords(32, 32, 32, 32, 512, 512));

        const tex = try eng.resources.acquireTexture("guy");

        return .{
            .fps = FpsCounter.init(),
            .alloc = alloc,
            .eng = eng,
            .tex = tex,
            .pointer = pixzig.sprites.Sprite.create(tex, .{ .x = 32, .y = 32 }),
        };
    }

    pub fn deinit(self: *App) void {
        self.eng.resources.releaseTexture(self.tex);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (self.fps.update(delta)) {
            std.log.debug("FPS: {}", .{self.fps.fps()});
        }

        const mousePos = eng.inputs.mouse.pos().asVec2I();
        self.pointer.setPos(mousePos.x, mousePos.y);

        if (eng.inputs.mouse.pressed(.left)) {
            std.log.info("left mouse!\n", .{});
        }
        if (eng.inputs.mouse.pressed(.right)) {
            std.log.info("right mouse!\n", .{});
        }

        if (eng.inputs.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);
        self.fps.renderTick();

        eng.renderer.begin(eng.projMat);
        eng.renderer.drawSprite(&self.pointer);
        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Mouse Example", .{});

    const appRunner = try AppRunner.init("Pixzig Mouse Example.", init.gpa, .{});
    var app = try App.init(init.gpa, appRunner.engine);

    appRunner.run(&app);
}
