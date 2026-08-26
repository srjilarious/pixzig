const std = @import("std");
const zmath = @import("zmath");

const common = @import("../common.zig");
const resources = @import("../resources.zig");
const quad_batch = @import("../renderer/quad_batch.zig");

const Vec2I = common.Vec2I;
const RectF = common.RectF;
const Color = common.Color;
const ManagedShader = resources.ManagedShader;

const Inner = quad_batch.StaticQuadBatch(.{ .posDim = 2, .colorDim = 4 });

/// Draws a static grid of thin filled rects (as border lines) over a tile
/// map. This is a thin wrapper over `StaticQuadBatch`: the grid mesh is
/// built once (or whenever `recreateVertices` is called after a map/tile
/// size change) and drawn every frame with a single draw call, no per-frame
/// re-upload.
pub const GridRenderer = struct {
    inner: Inner,

    pub fn init(
        alloc: std.mem.Allocator,
        shader: *ManagedShader,
        mapSize: Vec2I,
        tileSize: Vec2I,
        borderSize: usize,
        color: Color,
    ) !GridRenderer {
        var inner = try Inner.init(alloc, shader);
        errdefer inner.deinit();

        try buildGrid(&inner, mapSize, tileSize, borderSize, color);

        return .{ .inner = inner };
    }

    pub fn deinit(self: *GridRenderer) void {
        self.inner.deinit();
    }

    /// (Re)builds the grid mesh for the given map/tile size, border
    /// thickness, and color. Safe to call again later (e.g. after the map
    /// size changes) to fully rebuild the grid; the previous GPU contents
    /// keep drawing correctly until the rebuild finishes uploading.
    pub fn recreateVertices(self: *GridRenderer, mapSize: Vec2I, tileSize: Vec2I, borderSize: usize, color: Color) !void {
        try buildGrid(&self.inner, mapSize, tileSize, borderSize, color);
    }

    pub fn draw(self: *GridRenderer, mvp: zmath.Mat) !void {
        self.inner.draw(mvp);
    }

    fn drawFilledRect(inner: *Inner, dest: RectF, color: Color) !void {
        const positions: [4][2]f32 = .{
            .{ dest.l, dest.b },
            .{ dest.l, dest.t },
            .{ dest.r, dest.t },
            .{ dest.r, dest.b },
        };

        const colors: [4][4]f32 = .{
            .{ color.r, color.g, color.b, color.a },
            .{ color.r, color.g, color.b, color.a },
            .{ color.r, color.g, color.b, color.a },
            .{ color.r, color.g, color.b, color.a },
        };

        try inner.addQuad(positions, {}, colors);
    }

    fn drawVertLine(inner: *Inner, x: i32, w: i32, h: i32, color: Color) !void {
        try drawFilledRect(inner, RectF.fromPosSize(x, 0, w, h), color);
    }

    fn drawHorzLine(inner: *Inner, y: i32, w: i32, h: i32, color: Color) !void {
        try drawFilledRect(inner, RectF.fromPosSize(0, y, w, h), color);
    }

    fn buildGrid(inner: *Inner, mapSize: Vec2I, tileSize: Vec2I, borderSize: usize, color: Color) !void {
        const tw: usize = @intCast(tileSize.x);
        const th: usize = @intCast(tileSize.y);
        const numHorz: usize = @as(usize, @intCast(mapSize.x)) + 1;
        const numVert: usize = @as(usize, @intCast(mapSize.y)) + 1;

        const gridWidth: i32 = @intCast((numHorz - 1) * tw);
        const gridHeight: i32 = @intCast((numVert - 1) * th);

        inner.beginBuild({});
        for (0..numVert) |yy| {
            for (0..numHorz) |xx| {
                try drawHorzLine(inner, @intCast(yy * th), gridWidth, @intCast(borderSize), color);
                try drawVertLine(inner, @intCast(xx * tw), @intCast(borderSize), gridHeight, color);
            }
        }
        inner.endBuild();
    }
};
