const std = @import("std");
const gl = @import("zopengl").bindings;
const zmath = @import("zmath");

const common = @import("../common.zig");

const textures = @import("./textures.zig");
const shaders = @import("./shaders.zig");
const resources = @import("../resources.zig");
const quad_batch = @import("./quad_batch.zig");

const Vec3F = common.Vec3F;
const RectF = common.RectF;
const Texture = textures.Texture;
const ResourceManager = resources.ResourceManager;

const MaxQuads = 4096;

const Layout = quad_batch.BatchLayout{ .posDim = 3, .texDim = 2 };
const Dynamic = quad_batch.QuadBatch(Layout);
const Static = quad_batch.StaticQuadBatch(Layout);

fn toPositions(corners: [4]Vec3F) [4][3]f32 {
    return .{
        .{ corners[0].x, corners[0].y, corners[0].z },
        .{ corners[1].x, corners[1].y, corners[1].z },
        .{ corners[2].x, corners[2].y, corners[2].z },
        .{ corners[3].x, corners[3].y, corners[3].z },
    };
}

fn toTexCoords(srcCoords: RectF) [4][2]f32 {
    return .{
        .{ srcCoords.l, srcCoords.b },
        .{ srcCoords.l, srcCoords.t },
        .{ srcCoords.r, srcCoords.t },
        .{ srcCoords.r, srcCoords.b },
    };
}

/// A batch queue for drawing arbitrary world-space textured quads (walls,
/// floors, ceilings) with a full perspective view*projection matrix. Thin
/// wrapper over `QuadBatch`, translating 3d corners + a texture-space rect
/// into the raw per-vertex data the generic batch expects, plus the
/// GL_DEPTH_TEST toggling this renderer needs (so overlapping wall/floor/
/// ceiling quads occlude correctly regardless of submission order) without
/// leaking depth testing into any 2d rendering that runs later in the frame.
pub const Quad3DBatchQueue = struct {
    inner: Dynamic,

    /// Initializes the Quad3DBatchQueue, creating the buffers and OpenGL
    /// objects needed, and loading (or reusing) the quad3d shader via the
    /// resource manager.
    pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager) !Quad3DBatchQueue {
        const shader_managed = try resMgr.loadShader(
            shaders.Quad3DShader,
            &shaders.Quad3DVertexShader,
            &shaders.TexPixelShader,
        );
        return .{ .inner = try Dynamic.init(alloc, shader_managed, MaxQuads) };
    }

    /// Cleans up the OpenGL objects associated with the Quad3DBatchQueue and
    /// frees the buffer memory.
    pub fn deinit(self: *Quad3DBatchQueue) void {
        self.inner.deinit();
    }

    /// Begins a new 3d render pass, setting the view*projection matrix to
    /// use and enabling depth testing so quads submitted in any order
    /// occlude correctly. Pass `clearDepth = false` to keep whatever depth
    /// values are already in the buffer -- e.g. when drawing on top of a
    /// Quad3DBatch that was rendered earlier in the same frame and should
    /// still occlude these quads.
    pub fn begin(self: *Quad3DBatchQueue, viewProj: zmath.Mat, clearDepth: bool) void {
        self.inner.begin(viewProj);

        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LESS);
        if (clearDepth) {
            gl.clear(gl.DEPTH_BUFFER_BIT);
        }
    }

    /// Enqueues drawing a textured quad given its 4 world-space corners, in
    /// the same winding order RectF-based draws use elsewhere in pixzig:
    /// bottom-left, top-left, top-right, bottom-right (relative to
    /// `srcCoords`, which maps corner 0 to (l,b), 1 to (l,t), 2 to (r,t)
    /// and 3 to (r,b)).
    pub fn drawQuad(self: *Quad3DBatchQueue, texture: *const Texture, corners: [4]Vec3F, srcCoords: RectF) void {
        self.inner.addQuad(texture, toPositions(corners), toTexCoords(srcCoords), {});
    }

    /// Ends the current batch, flushing any queued quads and disabling
    /// depth testing so it doesn't affect subsequent 2d rendering.
    pub fn end(self: *Quad3DBatchQueue) void {
        self.inner.end();
        gl.disable(gl.DEPTH_TEST);
    }

    /// Draws the current contents of the queue to the screen. Assumes
    /// `begin` has already been called. Flushes queued quads while keeping
    /// the batch open for further draws.
    pub fn flush(self: *Quad3DBatchQueue) void {
        self.inner.flush();
    }
};

/// A pre-built, static batch of world-space textured quads sharing a single
/// texture: build it once (or whenever the source data changes) via
/// beginBuild/addQuad/endBuild, then call draw() every frame for a single
/// draw call. Use this instead of Quad3DBatchQueue for geometry that doesn't
/// change often, e.g. a level's wall/floor/ceiling quads. Callers needing
/// multiple textures should keep one Quad3DBatch per texture and draw each
/// in turn.
pub const Quad3DBatch = struct {
    inner: Static,

    /// Initializes the Quad3DBatch, creating its GL objects and loading (or
    /// reusing) the quad3d shader via the resource manager. No quad data is
    /// uploaded yet; call beginBuild/addQuad/endBuild before drawing.
    pub fn init(alloc: std.mem.Allocator, resMgr: *ResourceManager) !Quad3DBatch {
        const shader_managed = try resMgr.loadShader(
            shaders.Quad3DShader,
            &shaders.Quad3DVertexShader,
            &shaders.TexPixelShader,
        );
        return .{ .inner = try Static.init(alloc, shader_managed) };
    }

    /// Cleans up the OpenGL objects and any CPU-side scratch buffers.
    pub fn deinit(self: *Quad3DBatch) void {
        self.inner.deinit();
    }

    /// Starts (re)building the batch's quad list from scratch. Every quad
    /// added before the matching endBuild() shares `texture`. Safe to call
    /// again later (e.g. after the underlying map data changes) to fully
    /// rebuild the batch; the previous GPU contents keep drawing correctly
    /// until endBuild() uploads the new ones.
    pub fn beginBuild(self: *Quad3DBatch, texture: *const Texture) void {
        self.inner.beginBuild(texture);
    }

    /// Adds a quad's 4 world-space corners to the batch, in the same winding
    /// order as Quad3DBatchQueue.drawQuad: bottom-left, top-left, top-right,
    /// bottom-right (relative to srcCoords).
    pub fn addQuad(self: *Quad3DBatch, corners: [4]Vec3F, srcCoords: RectF) !void {
        try self.inner.addQuad(toPositions(corners), toTexCoords(srcCoords), {});
    }

    /// Uploads the accumulated quad data to the GPU. After this call the
    /// batch can be drawn any number of times via draw() until the next
    /// beginBuild/endBuild cycle.
    pub fn endBuild(self: *Quad3DBatch) void {
        self.inner.endBuild();
    }

    /// Draws the batch's current GPU contents with the given view*projection
    /// matrix. Enables depth testing for the duration of the call so
    /// overlapping wall/floor/ceiling quads occlude correctly, then disables
    /// it again so it doesn't leak into any 2d rendering that runs after.
    pub fn draw(self: *Quad3DBatch, viewProj: zmath.Mat) void {
        if (self.inner.isEmpty()) return;

        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LESS);
        gl.clear(gl.DEPTH_BUFFER_BIT);

        self.inner.draw(viewProj);

        gl.disable(gl.DEPTH_TEST);
    }
};
