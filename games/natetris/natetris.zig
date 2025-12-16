// zig fmt: off
// Natetris: A tetris clone for Nate.

const std = @import("std");
const builtin = @import("builtin");

const pixzig = @import("pixzig");
const gl = pixzig.gl;
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
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

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const ShapeWidth = 5;
const ShapeHeight = 5;

const BoardHeight = 16;
const BoardWidth = 18;

const PieceStartX = 8;
const PieceStartY = -1;

const Shapes: []const []const u8 = &.{
      "     " ++
      "  x  " ++
      "  x  " ++
      "  x  " ++
      "  x  ",

      "     " ++
      "  x  " ++
      "  xx " ++
      "  x  " ++
      "     ",

      "     " ++
      "  x  " ++
      "  x  " ++
      "  xx " ++
      "     ",

      "     " ++
      "  x  " ++
      "  x  " ++
      " xx  " ++
      "     ",

      "     " ++
      "     " ++
      "  xx " ++
      " xx  " ++
      "     ",

      "     " ++
      "     " ++
      " xx  " ++
      "  xx " ++
      "     ",

      "     " ++
      "     " ++
      " xx  " ++
      " xx  " ++
      "     ",
};


const SquareIndex = Shapes.len-1;

const BoardSpace = enum {
    Empty,
    Wall,
    Locked,
};

// Base pixel location for board.
const BaseX: i32 = 100;
const BaseY: i32 = 40;


const AppRunner =  pixzig.PixzigAppRunner(Natetris, .{});

pub const Natetris = struct {
    alloc: std.mem.Allocator,
    fps: FpsCounter,
    tex: *pixzig.Texture,
    lockedTex: *pixzig.Texture,
    wallTex: *pixzig.Texture,
    projMat: zmath.Mat,
    currIdx: usize,
    shape: []u8,
    shapePos: Vec2I,
    board: []BoardSpace,
    timeTillDrop: f64,

    // states: AppStateMgr,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*Natetris {

        const app = try alloc.create(Natetris);

        const blockChars =
        \\=------=
        \\-..####-
        \\-.####=-
        \\-#####=-
        \\-#####=-
        \\-#####=-
        \\-##===@-
        \\=------=
        ;

        const tex = try eng.resources.createTextureImageFromChars("test", 8, 8, blockChars, &[_]CharToColor{
            .{ .char = '#', .color = Color8.from(40, 255, 40, 255) },
            .{ .char = '-', .color = Color8.from(100, 100, 200, 255) },
            .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
            .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
            .{ .char = '@', .color = Color8.from(30, 155, 30, 255) },
            .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
        });

        const lockedChars =
        \\=------=
        \\-######-
        \\-#####=-
        \\-#####=-
        \\-#####=-
        \\-#####=-
        \\-##===@-
        \\=------=
        ;

        const wallTex = try eng.resources.createTextureImageFromChars("wall", 8, 8, lockedChars, &[_]CharToColor{
            .{ .char = '#', .color = Color8.from(180, 180, 180, 255) },
            .{ .char = '-', .color = Color8.from(80, 80, 80, 255) },
            .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
            .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
            .{ .char = '@', .color = Color8.from(30, 30, 30, 255) },
            .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
        });

        const lockedTex = try eng.resources.createTextureImageFromChars("locked", 8, 8, lockedChars, &[_]CharToColor{
            .{ .char = '#', .color = Color8.from(150, 150, 210, 255) },
            .{ .char = '-', .color = Color8.from(80, 80, 120, 255) },
            .{ .char = '=', .color = Color8.from(100, 100, 150, 255) },
            .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
            .{ .char = '@', .color = Color8.from(30, 30, 60, 255) },
            .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
        });

        std.log.debug("Created texture from characters.\n", .{});

        const projMat = zmath.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

        var board = try alloc.alloc(BoardSpace, BoardWidth*BoardHeight);
        for(0..BoardHeight) |bh| {
            for(0..BoardWidth) |bw| {
                const bidx = bh*BoardWidth+bw;
                if(bh == BoardHeight - 1) {
                    board[bidx] = .Wall;
                }
                else if(bw == 0 or bw == BoardWidth - 1) {
                    board[bidx] = .Wall;
                }
                else {
                    if(bh >= BoardHeight-6) {
                        board[bidx] = .Locked;
                    }
                    else {
                        board[bidx] = .Empty;
                    }
                }
            }
        }

        
        app.* = .{ 
            .alloc = alloc,
            .fps = FpsCounter.init(),
            // .states = AppStateMgr.init(appStates),
            .tex = tex,
            .lockedTex = lockedTex,
            .wallTex = wallTex,
            .projMat = projMat,
            .currIdx = 0,
            .shape = try alloc.alloc(u8, ShapeWidth*ShapeHeight),
            .shapePos = .{ .x = 1, .y = 0 },
            .board = board,
            .timeTillDrop = 0.0,
        };
        app.currIdx = 0;

        // for(0..15) |idx| {
        //     app.shape[idx] = Shapes[0][idx];
        // }
        @memcpy(app.shape, Shapes[0]);
        return app;
    }

    pub fn deinit(self: *Natetris) void {
        self.alloc.free(self.shape);
        self.alloc.free(self.board);
        self.alloc.destroy(self);
    }

    pub fn update(self: *Natetris, eng: *AppRunner.Engine, delta: f64) bool {
        if(self.fps.update(delta)) {
            std.log.debug("FPS: {}\n", .{self.fps.fps()});
        }

        if (eng.keyboard.pressed(.one)) {
            if(self.currIdx > 0) self.currIdx -= 1;
            @memcpy(self.shape, Shapes[self.currIdx]);
        } 
        if (eng.keyboard.pressed(.two)) {
            if(self.currIdx < (Shapes.len - 1)) self.currIdx += 1;
            @memcpy(self.shape, Shapes[self.currIdx]);
        }
        if (eng.keyboard.pressed(.z)) {
            self.rotateCounterClockwise();
            if(!self.checkShape(self.shapePos)) {
                // Undo our attempt.
                self.rotateClockwise();
            }
        }
        if (eng.keyboard.pressed(.x)) {
            self.rotateClockwise();
            if(!self.checkShape(self.shapePos)) {
                self.rotateCounterClockwise();
            }
        }

        if (eng.keyboard.pressed(.left)) {
            self.shapePos.x -= 1;
            if(!self.checkShape(self.shapePos)) {
                self.shapePos.x += 1;
            }
        }
        else if(eng.keyboard.pressed(.right)) {
            self.shapePos.x += 1;
            if(!self.checkShape(self.shapePos)) {
                self.shapePos.x -= 1;
            }
        }
        else if(eng.keyboard.pressed(.down)) {
            self.shapePos.y += 1;

            if(!self.checkShape(self.shapePos)) {
                self.shapePos.y -= 1;
            } else {
                self.timeTillDrop = 0.0;
            }
        }

        if(eng.keyboard.pressed(.escape)) {
            return false;
        }

        self.timeTillDrop += delta;
        if(self.timeTillDrop > 1.0) {
            self.tryDropAndLock();
            self.timeTillDrop = 0.0;
        }

        return true;
    }

    pub fn render(self: *Natetris, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.1, 1);
        
        // const fb_size = eng.window.getFramebufferSize();
        eng.renderer.begin(self.projMat);
        
        self.drawBoard(eng, .{ .x = 32, .y = 32});
        self.drawShape(eng, self.shapePos, .{ .x = 32, .y = 32}, self.shape);

        eng.renderer.end();
        self.fps.renderTick();
    }

    fn tryDropAndLock(self: *Natetris) void {
        self.shapePos.y += 1;
        if(!self.checkShape(self.shapePos)) {
            // Put it back to the original position.
            self.shapePos.y -= 1;

            // If we tried to move down and couldn't, time to lock the pieces in.
            for(0..ShapeHeight) |h| {
                for(0..ShapeWidth) |w| {
                    const hi: i32 = @intCast(h);
                    const wi: i32 = @intCast(w);

                    const bsx: i32 = self.shapePos.x + wi;
                    const bsy: i32 = self.shapePos.y + hi;
                    if(bsx < 0 or bsx >= BoardWidth) continue;
                    if(bsy < 0 or bsy >= BoardHeight) continue;

                    const bidx = @as(usize, @intCast(bsy))*BoardWidth + @as(usize, @intCast(bsx));
                    if(self.shape[h*ShapeWidth+w] == 'x') 
                        self.board[bidx] = .Locked;
                }
            }

            // try finding finished lines.
            self.checkBoard();
            // Now we need to spawn a new piece.
            self.spawnNewPiece();
        }
    }

    fn spawnNewPiece(self: *Natetris) void {
        self.shapePos = .{ .x = PieceStartX, .y = PieceStartY };
        @memcpy(self.shape, Shapes[2]);
        self.timeTillDrop = 0.0;
    }

    fn rotateClockwise(self: *Natetris) void {
        if(self.currIdx == SquareIndex) return;

        var temp: [ShapeWidth*ShapeHeight]u8 = undefined;
        @memcpy(temp[0..], self.shape);
        for(0..ShapeHeight) |h| {
            for(0..ShapeWidth) |w| {
                const th = w;
                const dest = th*ShapeWidth + ShapeHeight-1-h;
                const src = h*ShapeWidth + w;
                self.shape[dest] = temp[src];
            }
        }
    }

    fn rotateCounterClockwise(self: *Natetris) void {
        if(self.currIdx == SquareIndex) return;

        var temp: [ShapeWidth*ShapeHeight]u8 = undefined;
        @memcpy(temp[0..], self.shape);
        for(0..ShapeHeight) |h| {
            for(0..ShapeWidth) |w| {
                const th = w;
                const dest = h*ShapeWidth + w;
                const src = th*ShapeWidth + ShapeHeight-1-h;
                self.shape[dest] = temp[src];
            }
        }
    }

    // Where pos is the pos offset on the board
    fn checkShape(self: *Natetris, pos: Vec2I) bool {
        for(0..ShapeHeight) |h| {
            for(0..ShapeWidth) |w| {
                const hi: i32 = @intCast(h);
                const wi: i32 = @intCast(w);

                const bsx: i32 = pos.x + wi;
                const bsy: i32 = pos.y + hi;
                if(bsx < 0 or bsx >= BoardWidth) continue;
                if(bsy < 0 or bsy >= BoardHeight) continue;

                const bidx = @as(usize, @intCast(bsy))*BoardWidth + @as(usize, @intCast(bsx));
                if(self.board[bidx] != .Empty and self.shape[h*ShapeWidth+w] == 'x') return false;
            }
        }
        return true;
    }

    fn checkBoard(self: *Natetris) void {
        // Don't check the wall.s
        for(0..BoardHeight-1) |bh| {
            var foundEmpty = false;
            for(1..BoardWidth-1) |bw| {
                const bidx = bh*BoardWidth+bw;
                if(self.board[bidx] == .Empty) {
                    foundEmpty = true;
                    break;
                }
            }

            // We found a completed lines, move the lines above us down.
            if(!foundEmpty) {
                self.moveLinesDown(bh);
            }
        }
    }

    fn moveLinesDown(self: *Natetris, startLine: usize) void {
        // Don't move the walls
        for(0..startLine) |bh_inv| {
            const bh:usize = startLine - bh_inv;
            for(1..BoardWidth-1) |bw| {
                const dest = bh*BoardWidth+bw;
                const source = (bh-1)*BoardWidth+bw;
                self.board[dest] = self.board[source];
            }
        }

        // Make sure the top line is empty
        for(1..BoardWidth-1) |bw| {
            self.board[bw] = .Empty;
        }
    }

    fn drawBoard(self: *Natetris, eng: *AppRunner.Engine, size: Vec2I) void {
        
        const source =  RectF.fromCoords(0, 0, 8, 8, 8, 8);

        for(0..BoardHeight) |bh| {
            for(0..BoardWidth) |bw| {
                const bidx = bh*BoardWidth+bw;
                const w: i32 = @intCast(bw);
                const h: i32 = @intCast(bh);
                if(self.board[bidx] != .Empty) {
                    const dest = RectF.fromPosSize(
                        BaseX+w*size.x, 
                        BaseY+h*size.y, 
                        size.x, size.y);
                    const tex = which: {
                        if(self.board[bidx] == .Wall) {
                            break :which self.wallTex;
                        }
                        else {
                            break :which self.lockedTex;
                        }
                    };

                    // set texture options
                    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
                    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
                    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
                    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
                    gl.enable(gl.BLEND);
                    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
                    eng.renderer.drawTexture(tex, dest, source);

                }
            }
        }
    }

    fn drawShape(
            self: *Natetris,
            eng: *AppRunner.Engine,
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
                        BaseX+(pos.x+w)*size.x, 
                        BaseY+(pos.y+h)*size.y, 
                        size.x, size.y);
                    eng.renderer.drawTexture(self.tex, dest, source);
                    
                }
            }
        }
    }
};

pub fn main() !void {
    std.log.info("Starting Natetris", .{});

    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Natetris", alloc, .{});

    std.log.info("Initializing app.\n", .{});
    const app = try Natetris.init(alloc, appRunner.engine);

    glfw.swapInterval(0);
    appRunner.run(app);
}
