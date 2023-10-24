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
    alloc: std.mem.Allocator,
    mode: AnimPlayMode,
    name: ?[]const u8,
    nextState: ?[]const u8,

    pub fn init(name: ?[]const u8, alloc: std.mem.Allocator, framesArr: []const Frame ) !FrameSequence {
        _ = name;
        // var nameCopy: ?[]const u8 = null;
        // if(name != null) {
        //     nameCopy = try alloc.dupe(u8, name);
        // }

        var frames = std.ArrayList(Frame).init(alloc);
        for(framesArr) |fr| {
            try frames.append(fr);
        }

        return .{ 
            .frames = frames,
            .alloc = alloc,
            .mode = AnimPlayMode.Loop, 
            .name = null,//nameCopy, 
            .nextState = null 
        };
    }

    pub fn deinit(self: *FrameSequence) void {
        self.frames.deinit();
        // if(self.name != null) {
        //     self.alloc.free(self.name);
        // }
    }

};

pub const Actor = struct {
    states: std.StringHashMap(FrameSequence),
    alloc: std.mem.Allocator,
    currState: ?*FrameSequence,
    currFrame: i32,
    currFrameTimeUs: i64,
    actorSize: Vec2I,
    dirtyState: bool,

    pub fn init(alloc: std.mem.Allocator) !Actor {
        return .{ 
            .states = std.StringHashMap(FrameSequence).init(alloc), 
            .alloc = alloc,
            .currState = null, 
            .currFrame = 0, 
            .currFrameTimeUs = 0, 
            .actorSize = Vec2I{ .x = 0, .y = 0 }, 
            .dirtyState = false 
        };
    }

    pub fn deinit(self: *Actor) void {
        self.currState = null;
        
    }

    pub fn addState(self: *Actor, frameSequence: FrameSequence, otherName: ?[]const u8) !*Actor {
        const keyCopy = if(otherName != null) 
            try self.alloc.dupe(u8, otherName.?)
        else 
            try self.alloc.dupe(u8, frameSequence.name.?);

        try self.states.put(keyCopy, frameSequence);
        if(self.currState == null) {
            self.setState(keyCopy);
        }

        return self;
    }

    pub fn setState(self: *Actor, name: []const u8) void {
        if(self.states.getPtr(name)) |state| {
            self.currState = @ptrCast(state);
        }
    }

    pub fn update(self: *Actor, deltaUs: i64, spr: *Sprite) void {
        if(self.currState == null) return;

        const currSeq = self.currState.?;
        // std.debug.print("addr=0x{x}, currFrame={}, currFrameTimeUs={}, numFrames={}\n", .{ @intFromPtr(currSeq), self.currFrame, self.currFrameTimeUs, currSeq.frames.items.len });
        const currFrame = &currSeq.frames.items[@intCast(self.currFrame)];
        self.currFrameTimeUs += deltaUs;
        if(self.currFrameTimeUs > currFrame.frameTimeUs) {
            self.currFrameTimeUs -= currFrame.frameTimeUs;
            self.currFrame += 1;
            if(self.currFrame >= currSeq.frames.items.len) {
                // TODO: Add in once behavior
                self.currFrame = 0;
            }

            // std.debug.print("Applying frame {}\n", .{ self.currFrame });
            currSeq.frames.items[@intCast(self.currFrame)].apply(spr);
        }
    }
};
