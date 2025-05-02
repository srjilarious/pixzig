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
};

pub const Flip = enum(u8) { 
    none = 0, 
    horz = 1, 
    vert = 2, 
    both = 3 
};

pub const Frame = struct { 
    tex: *Texture,
    frameTimeUs: i64, 
    flip: Flip,

    pub fn apply(self: *Frame, spr: *Sprite, extraFlip: Flip) void {
        _ = extraFlip;

        spr.flip = self.flip;
        switch(self.flip) {
            .none => spr.src_coords = self.tex.src,
            .horz => {
                spr.src_coords = .{
                    .l = self.tex.src.r,
                    .t = self.tex.src.t,
                    .r = self.tex.src.l,
                    .b = self.tex.src.b
                };
            },
            .vert => {
                spr.src_coords = .{
                    .l = self.tex.src.l,
                    .t = self.tex.src.b,
                    .r = self.tex.src.r,
                    .b = self.tex.src.t
                };
            },
            .both => {
                spr.src_coords = .{
                    .l = self.tex.src.r,
                    .t = self.tex.src.b,
                    .r = self.tex.src.l,
                    .b = self.tex.src.t
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

pub const ActorState = struct {
    name: []const u8,
    nextState: ?[]const u8 = null,
    sequence: *const FrameSequence,
    flip: Flip,
};

pub const FrameSequence = struct {
    frames: std.ArrayList(Frame),
    mode: AnimPlayMode,

    pub fn init(alloc: std.mem.Allocator, framesArr: []const Frame ) !FrameSequence {
        var frames = std.ArrayList(Frame).init(alloc);
        for(framesArr) |fr| {
            try frames.append(fr);
        }

        return .{ 
            .frames = frames,
            .mode = .loop, 
        };
    }

    pub fn deinit(self: *FrameSequence) void {
        self.frames.deinit();
    }

};

pub const FrameSequenceFile = struct {
    sequences: []FileFrameSequence,
};

pub const FileFrameSequence = struct {
    mode: AnimPlayMode,
    name: ?[]const u8,
};

pub const FileFrame = struct {
    frameName: []const u8,
    frameTimeUs: i64, 
    flip: Flip,
};

pub const FileActorState = struct {
    name: []const u8,
    nextStateName: []const u8,

    frameSeqName: []const u8,
    // Flip applied on top of sequence flip.
    flip: Flip,
};


pub const FrameSequenceManager = struct {
    // We expand from the file frame which uses the name of a texture
    // and fill in the coords for the image.
    sequences: std.StringHashMap(*FrameSequence),
    actorStates: std.StringHashMap(ActorState),

    alloc: std.mem.Allocator,

    const Self = FrameSequenceManager;

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{ 
            .sequences = std.StringHashMap(*FrameSequence).init(alloc),
            .actorStates = std.StringHashMap(ActorState).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.sequences.iterator();
        while(iterator.next()) |kv| {
            self.alloc.free(kv.key_ptr.*);
            kv.value_ptr.deinit();
            self.alloc.destroy(kv.value_ptr.*);
        }
        self.sequences.deinit();
    }

    pub fn loadSequenceFile(filename: []const u8) !void {
        _ = filename;
    }

    pub fn add(self: *Self, name: []const u8, seq: FrameSequence) !void {
        const new = try self.alloc.create(FrameSequence);
        new.* = seq;
        try self.sequences.put(name, new);
    }

    pub fn get(self: *Self, name: []const u8) ?*const FrameSequence {
        return self.sequences.get(name);
    }
};

pub const Actor = struct {
    states: std.StringHashMap(*ActorState),
    alloc: std.mem.Allocator,
    currState: ?*ActorState,
    currFrame: i32,
    currFrameTimeUs: i64,
    actorSize: Vec2I,
    dirtyState: bool,

    pub fn init(alloc: std.mem.Allocator) !Actor {
        return .{ 
            .states = std.StringHashMap(*ActorState).init(alloc), 
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
            self.alloc.destroy(kv.value_ptr.*);
        }
        self.states.deinit();
    }

    pub fn addState(self: *Actor, state: ActorState) !*Actor {
        const nameCopy = try self.alloc.dupe(u8, state.name);
        var val = try self.alloc.create(ActorState);
        val.* = state;
        val.name = nameCopy;
        if(state.nextState != null) {
            val.nextState = try self.alloc.dupe(u8, state.nextState.?);
        }

        try self.states.put(nameCopy, val);
        if(self.currState == null) {
            self.currState = val;
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

        const currSeq = self.currState.?.sequence;
        const currFrame = &currSeq.frames.items[@intCast(self.currFrame)];
        self.currFrameTimeUs += deltaUs;
        if(self.currFrameTimeUs > currFrame.frameTimeUs) {
            self.currFrameTimeUs -= currFrame.frameTimeUs;
            self.currFrame += 1;
            if(self.currFrame >= currSeq.frames.items.len) {
                // TODO: Add in once behavior
                self.currFrame = 0;
            }

            // TODO: Add in flip on sequences.
            currSeq.frames.items[@intCast(self.currFrame)].apply(spr, .none);
        }
    }
};
