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
const TextureManager = textures.TextureManager;

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

pub const Flip = enum { 
    none, 
    horz, 
    vert, 
    both 
};

pub const Frame = struct { 
    tex: *Texture,
    frameTimeMs: f64, 
    flip: Flip,

    pub fn apply(self: *Frame, spr: *Sprite, extraFlip: Flip) void {
        const flip = blk: {
            switch(self.flip) {
                .none => break :blk extraFlip,
                .horz => {
                    switch(extraFlip) {
                        .none => break :blk .horz,
                        .horz => break :blk .none,
                        .vert => break :blk .both,
                        .both => break :blk .vert,
                    }
                },
                .vert => {
                    switch(extraFlip) {
                        .none => break :blk .vert,
                        .horz => break :blk .both,
                        .vert => break :blk .none,
                        .both => break :blk .horz,
                    }
                },
                .both => {
                    switch(extraFlip) {
                        .none => break :blk .both,
                        .horz => break :blk .vert,
                        .vert => break :blk .horz,
                        .both => break :blk .none,
                    }
                }
            }
        };

        switch(flip) {
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

    pub fn initEmpty(alloc: std.mem.Allocator) !FrameSequence {
        const frames = std.ArrayList(Frame).init(alloc);

        return .{ 
            .frames = frames,
            .mode = .loop, 
        };
    }

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
    states: []FileActorState,
};

pub const FileFrameSequence = struct {
    mode: AnimPlayMode,
    name: []const u8,
    frames: []FileFrame,
};

pub const FileFrame = struct {
    name: []const u8,
    ms: f64, 
    flip: ?Flip,
};

pub const FileActorState = struct {
    name: []const u8,
    nextStateName: ?[]const u8 = null,

    frameSeqName: []const u8,
    // Flip applied on top of sequence flip.
    flip: Flip,
};


pub const FrameSequenceManager = struct {
    // We expand from the file frame which uses the name of a texture
    // and fill in the coords for the image.
    sequences: std.StringHashMap(*FrameSequence),
    actorStates: std.StringHashMap(*ActorState),

    alloc: std.mem.Allocator,

    const Self = FrameSequenceManager;

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{ 
            .sequences = std.StringHashMap(*FrameSequence).init(alloc),
            .actorStates = std.StringHashMap(*ActorState).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up frame sequences.
        var iterator = self.sequences.iterator();
        while(iterator.next()) |kv| {
            self.alloc.free(kv.key_ptr.*);
            kv.value_ptr.deinit();
            self.alloc.destroy(kv.value_ptr.*);
        }
        self.sequences.deinit();

        // Clean up actor states.
        var stateIt = self.actorStates.iterator();
        while(stateIt.next()) |kv| {
            self.alloc.free(kv.value_ptr.*.name);
            if(kv.value_ptr.*.nextState) |nextState| {
                self.alloc.free(nextState);
            }

            // kv.value_ptr.deinit();
            self.alloc.destroy(kv.value_ptr.*);
        }
        self.actorStates.deinit();
    }

    pub fn loadSequenceFile(self: *Self, filename: []const u8, texMgr: *TextureManager) !void {
        // Load file contents
        const f = try std.fs.cwd().openFile(filename, .{});
        defer f.close();

        var buffered = std.io.bufferedReader(f.reader());
        
        // Load sequence
        try self.loadSequence(buffered.reader(), texMgr);
    }

    pub fn loadSequence(self: *Self, reader: anytype, texMgr: *TextureManager) !void {
        // Parse Json into File structures
        var jsonReader = std.json.reader(self.alloc, reader);
        defer jsonReader.deinit();
        const parsed = try std.json.parseFromTokenSource(
            FrameSequenceFile, 
            self.alloc, 
            &jsonReader, 
            .{}
        );
        defer parsed.deinit();

        // First load the frame sequences, since actor states need those for looking up.
        for(parsed.value.sequences) |fileSeq| {
            var seq = try FrameSequence.initEmpty(self.alloc);
            for(fileSeq.frames) |fileFrame| {
                const flip = blk: { 
                    if(fileFrame.flip) |f| { 
                        break :blk f; 
                    } 
                    else { 
                        break :blk .none;
                    }
                };
                try seq.frames.append(.{
                    .tex = try texMgr.getTexture(fileFrame.name),
                    .frameTimeMs = fileFrame.ms,
                    .flip = flip,
                });
            }

            try self.addSeq(fileSeq.name, seq);
        }

        // Next load the actor states
        for(parsed.value.states) |fileState| {
            var new = try self.alloc.create(ActorState);
            new.name = try self.alloc.dupe(u8, fileState.name);
            if(fileState.nextStateName) |nextState| {
                new.nextState = try self.alloc.dupe(u8, nextState);
            }
            else {
                new.nextState = null;
            }
            new.sequence = self.sequences.get(fileState.frameSeqName).?;
            try self.actorStates.put(new.name, new);
        }
    }

    pub fn addSeq(self: *Self, name: []const u8, seq: FrameSequence) !void {
        const new = try self.alloc.create(FrameSequence);
        new.* = seq;
        const nameCopy = try self.alloc.dupe(u8, name);
        try self.sequences.put(nameCopy, new);
    }

    pub fn addState(self: *Self, state: ActorState) !void {
        const new = try self.alloc.create(ActorState);
        new.* = state;
        new.name = try self.alloc.dupe(u8, state.name);
        if(state.nextState) |nextState| {
            new.nextState = try self.alloc.dupe(u8, nextState);
        }
        else {
            new.nextState = null;
        }

        try self.actorStates.put(new.name, new);
    }

    pub fn getSeq(self: *Self, name: []const u8) ?*const FrameSequence {
        return self.sequences.get(name);
    }

    pub fn getState(self: *Self, name: []const u8) ?*const ActorState {
        return self.actorStates.get(name);
    }
};

pub const Actor = struct {
    states: std.StringHashMap(*ActorState),
    alloc: std.mem.Allocator,
    currState: ?*ActorState,
    currFrame: i32,
    currFrameTimeMs: f64,
    actorSize: Vec2I,
    dirtyState: bool,

    pub fn init(alloc: std.mem.Allocator) !Actor {
        return .{ 
            .states = std.StringHashMap(*ActorState).init(alloc), 
            .alloc = alloc,
            .currState = null, 
            .currFrame = 0, 
            .currFrameTimeMs = 0, 
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

    pub fn addState(self: *Actor, state: *const ActorState) !*Actor {
        const nameCopy = try self.alloc.dupe(u8, state.name);
        var val = try self.alloc.create(ActorState);
        val.* = state.*;
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

    pub fn update(self: *Actor, deltaMs: f64, spr: *Sprite) void {
        if(self.currState == null) return;

        const currSeq = self.currState.?.sequence;
        const currFrame = &currSeq.frames.items[@intCast(self.currFrame)];
        self.currFrameTimeMs += deltaMs;
        if(self.currFrameTimeMs > currFrame.frameTimeMs) {
            self.currFrameTimeMs -= currFrame.frameTimeMs;
            self.currFrame += 1;
            if(self.currFrame >= currSeq.frames.items.len) {
                // TODO: Add in once behavior
                self.currFrame = 0;
            }

            // TODO: Add in flip on sequences.
            currSeq.frames.items[@intCast(self.currFrame)].apply(spr, .none);
        }
    }

    pub fn curr(self: *Actor) ?*Frame {
        if(self.currState == null) return null;

        const currSeq = self.currState.?.sequence;
        return &currSeq.frames.items[@intCast(self.currFrame)];
    }
};
