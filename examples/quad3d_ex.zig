//* -- collapsed: Imports --
const std = @import("std");
const pixzig = @import("pixzig");
const zmath = pixzig.zmath;
const RectF = pixzig.common.RectF;
const Vec3F = pixzig.common.Vec3F;

const EngOptions = pixzig.PixzigEngineOptions;
const Quad3DBatchQueue = pixzig.quad3d.Quad3DBatchQueue;
const Quad3DBatch = pixzig.quad3d.Quad3DBatch;
const Camera3D = pixzig.Camera3D;
//* ---

//* -- collapsed: Panic, logging and AppRunner definition--
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});
//* ---

//* Torus mesh parameters, shared between init() (mesh generation) and
//* render() (placement in the scene).
const MajorSegments = 24;
const MinorSegments = 12;
const MajorRadius: f32 = 1.6;
const MinorRadius: f32 = 0.5;
const TorusPos = Vec3F{ .x = 2.0, .y = 0, .z = 0 };

//* The single rotating quad's local half-size and world position.
const QuadHalfSize: f32 = 0.9;
const QuadPos = Vec3F{ .x = -3.0, .y = 0, .z = 0 };

//* Both quad renderers sample the gray stone tile from the "tiles" atlas
//* (col 2, row 6 of the 32x32 grid) rather than the whole texture.
const TileSize = 32;
const TileCol = 2;
const TileRow = 6;

//* Returns a point on a torus surface (major ring in the xz plane, minor
//* ring perpendicular to it), given angles around each ring in radians.
fn torusPoint(u: f32, v: f32) Vec3F {
    const ringRadius = MajorRadius + MinorRadius * @cos(v);
    return .{
        .x = ringRadius * @cos(u),
        .y = MinorRadius * @sin(v),
        .z = ringRadius * @sin(u),
    };
}

//* This example exercises both quad renderers built on the generic
//* `QuadBatch`: `Quad3DBatchQueue` (the per-frame dynamic queue) draws a
//* single quad whose spin comes entirely from the matrix passed to
//* `begin()`, not from recomputing its corners every frame. `Quad3DBatch`
//* (the build-once static batch) is used to upload a torus mesh a single
//* time; it then spins at a different rate purely via the matrix passed to
//* `draw()` each frame.
pub const App = struct {
    alloc: std.mem.Allocator,
    stoneTex: *pixzig.TextureHandle,

    dynamicQuad: Quad3DBatchQueue,
    torus: Quad3DBatch,
    camera: Camera3D,

    timeMs: f64 = 0,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        //* Register a named sub-texture for the stone tile's region of the
        //* atlas (same underlying GL texture, just a different UV rect and
        //* size), then acquire it like any other managed texture -- draw
        //* calls need no explicit tile math from here on.
        const texManaged = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
        _ = try eng.resources.addSubTexture(texManaged, "quad3d_stone", RectF.fromCoords(
            TileCol * TileSize,
            TileRow * TileSize,
            TileSize,
            TileSize,
            512,
            512,
        ));
        const stoneTex = try eng.resources.acquireTexture("quad3d_stone");

        var dynamicQuad = try Quad3DBatchQueue.init(alloc, &eng.resources);
        errdefer dynamicQuad.deinit();

        var torus = try Quad3DBatch.init(alloc, &eng.resources);
        errdefer torus.deinit();

        //* Build the torus mesh once: each grid cell of the (u, v) surface
        //* parametrization becomes one quad, mapping the stone tile onto
        //* every quad.
        torus.beginBuild(&stoneTex.val);
        for (0..MajorSegments) |ui| {
            const ua = @as(f32, @floatFromInt(ui)) / MajorSegments * std.math.tau;
            const ub = @as(f32, @floatFromInt(ui + 1)) / MajorSegments * std.math.tau;
            for (0..MinorSegments) |vi| {
                const va = @as(f32, @floatFromInt(vi)) / MinorSegments * std.math.tau;
                const vb = @as(f32, @floatFromInt(vi + 1)) / MinorSegments * std.math.tau;

                const corners = [4]Vec3F{
                    torusPoint(ua, va),
                    torusPoint(ua, vb),
                    torusPoint(ub, vb),
                    torusPoint(ub, va),
                };
                try torus.addQuad(corners, stoneTex.val.src);
            }
        }
        torus.endBuild();

        app.* = .{
            .alloc = alloc,
            .stoneTex = stoneTex,
            .dynamicQuad = dynamicQuad,
            .torus = torus,
            .camera = .{ .pos = .{ .x = 0, .y = 1.2, .z = -9 }, .yaw = 0 },
        };

        return app;
    }

    pub fn deinit(self: *App) void {
        self.torus.deinit();
        self.dynamicQuad.deinit();
        self.stoneTex.release();
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        self.timeMs += delta;

        if (eng.inputs.keyboard.pressed(.escape)) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.05, 1);

        const fbSize = eng.window_state.framebuffer_size;
        const aspect = @as(f32, @floatFromInt(fbSize.x)) / @as(f32, @floatFromInt(fbSize.y));
        const viewProj = self.camera.viewProjMatrix(aspect);

        const timeSec: f32 = @floatCast(self.timeMs / 1000.0);

        //* The torus spins slowly; draw it first so its depth values are in
        //* the buffer for the dynamic quad to test against below.
        const torusAngle = timeSec * 0.4;
        const torusModel = zmath.mul(zmath.rotationY(torusAngle), zmath.translation(TorusPos.x, TorusPos.y, TorusPos.z));
        self.torus.draw(zmath.mul(torusModel, viewProj));

        //* The dynamic quad spins faster, in the opposite direction. Its
        //* corners never change -- only the matrix passed to begin() does --
        //* and clearDepth is false so it occludes correctly against the
        //* torus drawn just above instead of wiping its depth values.
        const quadAngle = timeSec * -1.3;
        const quadModel = zmath.mul(zmath.rotationY(quadAngle), zmath.translation(QuadPos.x, QuadPos.y, QuadPos.z));
        self.dynamicQuad.begin(zmath.mul(quadModel, viewProj), false);
        self.dynamicQuad.drawQuad(&self.stoneTex.val, .{
            .{ .x = -QuadHalfSize, .y = -QuadHalfSize, .z = 0 },
            .{ .x = -QuadHalfSize, .y = QuadHalfSize, .z = 0 },
            .{ .x = QuadHalfSize, .y = QuadHalfSize, .z = 0 },
            .{ .x = QuadHalfSize, .y = -QuadHalfSize, .z = 0 },
        }, self.stoneTex.val.src);
        self.dynamicQuad.end();
    }
};

//* -- collapsed: Main function --
pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig Quad3D Example", .{});

    const appRunner = try AppRunner.init("Pixzig Quad3D Example.", init.gpa, .{});
    const app = try App.init(init.gpa, appRunner.engine);

    appRunner.run(app);
}
//* ---
