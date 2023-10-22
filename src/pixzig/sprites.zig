// zig fmt: off

const std = @import("std");
const sdl = @import("zsdl");

pub const Vec2I = struct { x: i32, y: i32 };

pub const Sprite = struct {
    texture: *sdl.Texture,
    src_coords: sdl.Rect,
    dest: sdl.Rect,

    pub fn create(tex: *sdl.Texture, scoords: sdl.Rect) Sprite {
        return Sprite{ 
            .texture = tex, 
            .src_coords = scoords, 
            .dest = .{ .x = 0, .y = 0, .w = scoords.w, .h = scoords.h } 
        };
    }

    pub fn setPos(self: *Sprite, x: i32, y: i32) void {
        self.dest.x = x;
        self.dest.y = y;
    }

    pub fn draw(self: *Sprite, renderer: *sdl.Renderer) !void {
        try renderer.copy(self.texture, &self.src_coords, &self.dest);
    }
};

pub const Flip = enum(u8) { 
    None = 0, 
    Horz = 1, 
    Vert = 2, 
    Both = 3 
};

pub const Frame = struct { 
    coords: sdl.Rect, 
    frameTimeUs: i64, 
    flip: Flip,

    pub fn apply(self: *Frame, spr: *Sprite) void {
        switch(self.flip) {
            Flip.None => spr.src_coords = self.coords,
            Flip.Horz => {
                spr.src_coords = .{
                    .x = self.coords.x + self.coords.w,
                    .y = self.coords.y,
                    .w = -self.coords.w,
                    .h = self.coords.h
                };
            },
            Flip.Vert => {
                spr.src_coords = .{
                    .x = self.coords.x,
                    .y = self.coords.y + self.coords.h,
                    .w = self.coords.w,
                    .h = -self.coords.h
                };
            },
            Flip.Both => {
                spr.src_coords = .{
                    .x = self.coords.x + self.coords.w,
                    .y = self.coords.y + self.coords.h,
                    .w = -self.coords.w,
                    .h = -self.coords.h
                };
            }
        }
    }
};

pub const AnimPlayMode = enum { 
    Loop, 
    Once 
};

pub const SpriteRenderOffset = enum { 
    None, 
    Sequence, 
    HorzCenterBottomAligned 
};

pub const FrameSequence = struct {
    frames: std.ArrayList(Frame),
    mode: AnimPlayMode,
    name: ?[]const u8,
    nextState: ?[]const u8,

    pub fn init(name: ?[]const u8, alloc: std.mem.Allocator) !FrameSequence {
        return .{ 
            .frames = std.ArrayList(Frame).init(alloc), 
            .mode = AnimPlayMode.Loop, 
            .name = name, 
            .nextState = null 
        };
    }
};

pub const Actor = struct {
    states: std.StringHashMap(FrameSequence),
    currState: ?*FrameSequence,
    currFrame: i32,
    currFrameTimeUs: i64,
    actorSize: Vec2I,
    dirtyState: bool,

    pub fn create(alloc: std.mem.Allocator) !Actor {
        return .{ 
            .states = std.StringHashMap(FrameSequence).init(alloc), 
            .currState = null, 
            .currFrame = 0, 
            .currFrameTimeUs = 0, 
            .actorSize = Vec2I{ .x = 0, .y = 0 }, 
            .dirtyState = false 
        };
    }
};
