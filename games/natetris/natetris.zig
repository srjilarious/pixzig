// zig fmt: off
// Natetris: A tetris clone for Nate.

const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const stbi = @import ("zstbi");
const zmath = @import("zmath"); 
const flecs = @import("zflecs"); 
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;
const FpsCounter = pixzig.utils.FpsCounter;
const PixzigEngine = pixzig.PixzigEngine;

const Color8 = pixzig.Color8;
const CharToColor = pixzig.textures.CharToColor;
const Vec2I = pixzig.common.Vec2I;

const ShapeWidth = 4;
const ShapeHeight = 4;

const Shapes: []const []const u8 = &.{
      " x  " ++
      " x  " ++
      " x  " ++
      " x  ",

      "    " ++
      " x  " ++
      " xx " ++
      " x  ",

      "    " ++
      " x  " ++
      " x  " ++
      " xx ",

      "    " ++
      " x  " ++
      " x  " ++
      "xx  ",

      "    " ++
      " xx " ++
      "xx  " ++
      "    ",

      "    " ++
      "xx  " ++
      " xx " ++
      "    ",

      "    " ++
      " xx " ++
      " xx " ++
      "    ",
};

pub const Natetris = struct {
    fps: FpsCounter,
    tex: *pixzig.Texture,
    spriteBatch: pixzig.renderer.SpriteBatchQueue,
    projMat: zmath.Mat,
    alloc: std.mem.Allocator,
    currIdx: usize,

    // states: AppStateMgr,

    pub fn init(eng: *PixzigEngine) !Natetris {
        const chars =
        \\=------=
        \\-..####-
        \\-.####=-
        \\-#####=-
        \\-#####=-
        \\-#####=-
        \\-##===@-
        \\=------=
        ;

        const tex = try eng.textures.createTextureFromChars("test", 8, 8, chars, &[_]CharToColor{
            .{ .char = '#', .color = Color8.from(40, 255, 40, 255) },
            .{ .char = '-', .color = Color8.from(100, 100, 200, 255) },
            .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
            .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
            .{ .char = '@', .color = Color8.from(30, 155, 30, 255) },
            .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
        });

        std.debug.print("Created texture from characters.\n", .{});

        const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        var texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader, 
            &pixzig.shaders.TexPixelShader
        );

        const alloc = eng.allocator;

        const spriteBatch = try pixzig.renderer.SpriteBatchQueue.init(alloc, &texShader);
        return .{ 
            .fps = FpsCounter.init(),
            // .states = AppStateMgr.init(appStates),
            .tex = tex,
            .spriteBatch = spriteBatch,
            .projMat = projMat,
            .alloc = alloc,
            .currIdx = 0,
        };
    }

    pub fn deinit(self: *Natetris) void {
        self.spriteBatch.deinit();
    }

    pub fn update(self: *Natetris, eng: *pixzig.PixzigEngine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.debug.print("FPS: {}\n", .{self.fps.fps()});
        }

        eng.keyboard.update();

        if (eng.keyboard.pressed(.one)) {
            if(self.currIdx > 0) self.currIdx -= 1;
        } 
        if (eng.keyboard.pressed(.two)) {
            if(self.currIdx < (Shapes.len - 1)) self.currIdx += 1;
        }

        if(eng.keyboard.pressed(.escape)) {
            return false;
        }

        return true;
    }

    pub fn render(self: *Natetris, eng: *pixzig.PixzigEngine) void {
        _ = eng;
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0.1, 1.0 });

        // const fb_size = eng.window.getFramebufferSize();
        self.spriteBatch.begin(self.projMat);
        // set texture options
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        self.drawShape(.{ .x = 10, .y = 10}, .{ .x = 32, .y = 32}, Shapes[self.currIdx]);
        // spriteBatch.drawSprite(tex, RectF.fromPosSize(32, 32, 32, 32), RectF.fromCoords(0, 0, 8, 8, 8, 8));
        // spriteBatch.drawSprite(tex, RectF.fromPosSize(64, 32, 32, 32), RectF.fromCoords(0, 0, 8, 8, 8, 8));
        // spriteBatch.drawSprite(tex, RectF.fromPosSize(96, 32, 32, 32), RectF.fromCoords(0, 0, 8, 8, 8, 8));
        // spriteBatch.drawSprite(tex, RectF.fromPosSize(64, 64, 32, 32), RectF.fromCoords(0, 0, 8, 8, 8, 8));
        self.spriteBatch.end();
        self.fps.renderTick();
    }

    fn drawShape(
            self: *Natetris,
            pos: Vec2I, 
            size: Vec2I,
            shape: []const u8) void 
    {
        // _ = shape;
        const source =  RectF.fromCoords(0, 0, 8, 8, 8, 8);
        for(0..ShapeHeight) |hu| {
            for(0..ShapeWidth) |wu| {
                const h: i32 = @intCast(hu);
                const w: i32 = @intCast(wu);

                if(shape[hu*ShapeWidth+wu] == 'x') {
                    const dest = RectF.fromPosSize(
                        pos.x+w*size.x, 
                        pos.y+h*size.y, 
                        size.x, size.y);
                    self.spriteBatch.drawSprite(self.tex, dest, source);
                    
                }
            }
        }
    }
};


pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Natetris", gpa, EngOptions{});
    defer eng.deinit();

    var app = try Natetris.init(&eng);
    defer app.deinit();
    std.debug.print("Game initialized.\n", .{});

    const AppRunner = pixzig.PixzigApp(Natetris);
    AppRunner.gameLoop(&app, &eng);
}
