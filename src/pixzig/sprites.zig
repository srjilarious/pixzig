// zig fmt: off

const std = @import("std");
const common = @import("./common.zig");
const textures = @import("./textures.zig");
const renderer = @import("./renderer.zig");

const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;
const RectF = common.RectF;
const Rotate = common.Rotate;

const Texture = textures.Texture;

// const SpriteBatchQueue = renderer.SpriteBatchQueue;

pub const Sprite = struct {
    texture: *Texture,
    src_coords: RectF,
    dest: RectF,
    size: Vec2F,
    flip: Flip,
    rotate: Rotate,

    pub fn create(tex: *Texture, size: Vec2F) Sprite {
        return Sprite{ 
            .texture = tex, 
            .src_coords = tex.src, 
            .dest = RectF.fromPosSize(0, 0, 
                @as(i32, @intFromFloat(size.x)), 
                @as(i32, @intFromFloat(size.y))),
            .size = size,
            .flip = .none,
            .rotate = .none,
        };
    }

    pub fn setPos(self: *Sprite, x: i32, y: i32) void {
        self.dest = RectF.fromPosSize(
            x, y, 
            @as(i32, @intFromFloat(self.size.x)), 
            @as(i32, @intFromFloat(self.size.y)));
    }

    // pub fn draw(self: *Sprite, batch: *SpriteBatchQueue) !void {
    //     batch.drawSprite(self.texture, self.dest, self.src_coords);
    // }
};

pub const Flip = enum(u8) { 
    none = 0, 
    horz = 1, 
    vert = 2, 
    both = 3 
};

pub const Frame = struct { 
    coords: RectF, 
    frameTimeUs: i64, 
    flip: Flip,

    pub fn apply(self: *Frame, spr: *Sprite) void {
        spr.src_coords = self.coords;
        spr.flip = self.flip;
        switch(self.flip) {
            .none => spr.src_coords = self.coords,
            .horz => {
                spr.src_coords = .{
                    .l = self.coords.r,
                    .t = self.coords.t,
                    .r = self.coords.l,
                    .b = self.coords.b
                };
            },
            .vert => {
                spr.src_coords = .{
                    .l = self.coords.l,
                    .t = self.coords.b,
                    .r = self.coords.r,
                    .b = self.coords.t
                };
            },
            .both => {
                spr.src_coords = .{
                    .l = self.coords.r,
                    .t = self.coords.b,
                    .r = self.coords.l,
                    .b = self.coords.t
                };
            }
        }
    }
};

pub const AnimPlayMode = enum { 
    loop, 
    once 
};

pub const SpriteRenderOffset = enum { 
    none, 
    sequence, 
    horzCenterBottomAligned 
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
            .mode = .loop, 
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
        var iterator = self.states.iterator();
        while(iterator.next()) |kv| {
            self.alloc.free(kv.key_ptr.*);
            kv.value_ptr.deinit();
        }
        self.states.deinit();
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
