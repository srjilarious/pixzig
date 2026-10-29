const std = @import("std");
const gl = @import("zopengl").bindings;

const common = @import("../common.zig");
const resources = @import("../resources.zig");

const Vec2U = common.Vec2U;
const RectF = common.RectF;
const TextureHandle = resources.TextureHandle;

/// How a render target's texture is sampled when it is drawn scaled.
pub const TargetFilter = enum {
    /// Hard pixel edges: a low-resolution target scaled up stays blocky.
    nearest,
    /// Smooth: blends neighbouring texels.
    linear,
};

pub const RenderTargetOptions = struct {
    filter: TargetFilter = .nearest,
};

/// An offscreen image the renderer can draw into instead of the screen
/// (see `Renderer.setTarget`), then draw like any other texture, e.g. to
/// scale a low-resolution scene up, run a post-processing shader over the
/// whole frame, or cache something expensive.
///
/// `texture` is a regular `TextureHandle` whose `src` is already flipped
/// (GL stores render targets bottom row first), so `drawTexture(&target.texture,
/// dest, target.texture.val.src)` and `drawFullTexture` draw it upright.
pub const RenderTarget = struct {
    /// The image, drawable with the renderer's texture calls. Owned by the
    /// target; don't add it to a `ResourceManager`.
    texture: TextureHandle,
    fbo: u32,
    filter: TargetFilter,

    pub fn init(sizePx: Vec2U, opts: RenderTargetOptions) !RenderTarget {
        if (sizePx.x == 0 or sizePx.y == 0) return error.InvalidRenderTargetSize;

        var tex: u32 = 0;
        gl.genTextures(1, &tex);
        errdefer gl.deleteTextures(1, &tex);
        allocateStorage(tex, sizePx, opts.filter);

        var fbo: u32 = 0;
        gl.genFramebuffers(1, &fbo);
        errdefer gl.deleteFramebuffers(1, &fbo);

        const previous = boundFramebuffer();
        defer gl.bindFramebuffer(gl.FRAMEBUFFER, previous);
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
        if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
            return error.IncompleteRenderTarget;
        }

        clearTransparent();

        return .{
            .texture = .{ .val = .{ .texture = tex, .size = sizePx, .src = flipped } },
            .fbo = fbo,
            .filter = opts.filter,
        };
    }

    pub fn deinit(self: *RenderTarget) void {
        gl.deleteFramebuffers(1, &self.fbo);
        gl.deleteTextures(1, &self.texture.val.texture);
    }

    /// The target's size in pixels.
    pub fn size(self: *const RenderTarget) Vec2U {
        return self.texture.val.size;
    }

    /// Reallocates the image at `newSize`, discarding its contents (it
    /// starts transparent). The texture handle stays the same, and its
    /// `version` goes up. Call outside a `setTarget` pass for this target.
    pub fn resize(self: *RenderTarget, newSize: Vec2U) !void {
        if (newSize.x == 0 or newSize.y == 0) return error.InvalidRenderTargetSize;
        if (newSize.x == self.size().x and newSize.y == self.size().y) return;
        allocateStorage(self.texture.val.texture, newSize, self.filter);
        self.texture.val.size = newSize;
        const previous = boundFramebuffer();
        defer gl.bindFramebuffer(gl.FRAMEBUFFER, previous);
        gl.bindFramebuffer(gl.FRAMEBUFFER, self.fbo);
        clearTransparent();
        self.texture.version +%= 1;
    }

    /// UVs for the whole image, upside down so it draws upright.
    const flipped: RectF = .{ .l = 0, .t = 1, .r = 1, .b = 0 };

    fn allocateStorage(tex: u32, size_px: Vec2U, filter: TargetFilter) void {
        const f: gl.Int = switch (filter) {
            .nearest => gl.NEAREST,
            .linear => gl.LINEAR,
        };
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @intCast(size_px.x), @intCast(size_px.y), 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    }
};

/// Clears the bound framebuffer to transparent black, whatever the scissor
/// is set to, so a new image doesn't start with whatever the driver left in
/// its storage. `glClear` ignores the viewport, so only the scissor is
/// touched, and it is put back.
fn clearTransparent() void {
    const scissorOn = gl.isEnabled(gl.SCISSOR_TEST) == gl.TRUE;
    gl.disable(gl.SCISSOR_TEST);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    if (scissorOn) gl.enable(gl.SCISSOR_TEST);
}

/// The framebuffer currently bound for drawing. Not always 0: some
/// platforms (iOS, some Android setups) render the window through an FBO
/// of their own, so a target pass restores this rather than 0.
pub fn boundFramebuffer() u32 {
    var current: gl.Int = 0;
    gl.getIntegerv(gl.FRAMEBUFFER_BINDING, &current);
    return @intCast(current);
}
