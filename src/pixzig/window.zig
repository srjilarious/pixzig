const std = @import("std");
const zmath = @import("zmath");
const platform = @import("./platform.zig");
const gl = @import("zopengl").bindings;
const common = @import("./common.zig");

const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;
const RectI = common.RectI;
const RectF = common.RectF;

/// Controls how the logical resolution maps onto the framebuffer.
pub const ScalePolicy = union(enum) {
    /// Fills the framebuffer, ignoring aspect ratio.
    stretch,
    /// Scales uniformly so the logical area fits entirely, letterboxing or pillarboxing the remainder.
    fit,
    /// Scales uniformly so the logical area covers the framebuffer, cropping the overflow.
    fill,
    /// Like `fit` but scale is rounded down to the nearest integer; avoids sub-pixel blurring.
    integer_fit,
    /// Like `fill` but scale is rounded up to the nearest integer.
    integer_fill,
    /// A caller-supplied constant scale factor.
    fixed: f32,
};

/// Tracks window and framebuffer dimensions. `resized` is set by the
/// engine's event pump on a resize and cleared by `refreshWindowState`.
pub const WindowState = struct {
    /// OS window size in screen coordinates. On non-HiDPI displays this equals
    /// `framebufferSize`. On HiDPI it is smaller because the OS uses logical
    /// coordinates for window placement and cursor reporting.
    windowSize: Vec2I,
    /// Actual framebuffer dimensions in pixels. This is what OpenGL sees and
    /// what you should use for GL viewport calls and projection matrices.
    framebufferSize: Vec2I,
    /// Display scale reported by `SDL_GetWindowDisplayScale`. This is the OS's
    /// hint for how much to scale UI content to look correct at the display's
    /// DPI. It is 2.0 on a typical 2x HiDPI display. Note: on Wayland with
    /// fractional scaling, this value can disagree with the actual
    /// framebuffer/window ratio, so prefer `scaleFactor` for coordinate math.
    contentScale: Vec2F,
    /// Ratio of framebuffer pixels to OS window screen coordinates
    /// (`framebufferSize / windowSize`). Use this to convert cursor
    /// positions (which are in window screen coordinates) to framebuffer
    /// pixels for correct mouse-to-game coordinate mapping on HiDPI displays.
    scaleFactor: Vec2F,
    /// Set to true by the engine's event pump when the window is resized.
    /// Cleared by `refreshWindowState` after it rebuilds the viewport.
    resized: bool = false,

    /// Initialises state from the current window metrics.
    pub fn init(window: *const platform.Window) WindowState {
        var state = WindowState{
            .windowSize = .{ .x = 0, .y = 0 },
            .framebufferSize = .{ .x = 0, .y = 0 },
            .contentScale = .{ .x = 1, .y = 1 },
            .scaleFactor = .{ .x = 1, .y = 1 },
        };
        state.refresh(window);
        return state;
    }

    /// Re-queries window size, pixel size and display scale from the
    /// platform layer and recomputes `scaleFactor`.
    pub fn refresh(self: *WindowState, win: *const platform.Window) void {
        self.windowSize = win.getSize();
        self.framebufferSize = win.getFramebufferSize();

        // SDL reports one display scale for both axes; store it twice to
        // match the shape of `contentScale`.
        const cs = win.getDisplayScale();
        self.contentScale = .{ .x = cs, .y = cs };

        const fb_w: f32 = @floatFromInt(self.framebufferSize.x);
        const fb_h: f32 = @floatFromInt(self.framebufferSize.y);
        const win_w: f32 = @floatFromInt(self.windowSize.x);
        const win_h: f32 = @floatFromInt(self.windowSize.y);
        self.scaleFactor = .{
            .x = if (win_w > 0) fb_w / win_w else 1.0,
            .y = if (win_h > 0) fb_h / win_h else 1.0,
        };
    }

    /// Returns a `RectI` covering the entire framebuffer (origin at 0,0).
    pub fn framebufferRect(self: *const WindowState) RectI {
        return .{ .l = 0, .t = 0, .r = self.framebufferSize.x, .b = self.framebufferSize.y };
    }
};

/// Maps a logical game resolution into a physical framebuffer rectangle.
/// viewportPx is stored in raster coordinates (top-left origin, y grows down).
pub const Viewport = struct {
    logicalSize: Vec2I,
    framebufferSize: Vec2I,
    viewportPx: RectI,
    scale: Vec2F,
    policy: ScalePolicy,

    /// Computes the initial viewport rectangle from `logicalSize`, `framebufferSize`, and `policy`.
    pub fn init(logicalSize: Vec2I, framebufferSize: Vec2I, policy: ScalePolicy) Viewport {
        var vp = Viewport{
            .logicalSize = logicalSize,
            .framebufferSize = framebufferSize,
            .viewportPx = .{ .l = 0, .t = 0, .r = 0, .b = 0 },
            .scale = .{ .x = 1.0, .y = 1.0 },
            .policy = policy,
        };
        vp.compute();
        return vp;
    }

    /// Updates the framebuffer size and recomputes the viewport rectangle.
    /// Call this when the event pump reports a window resize.
    pub fn updateFramebufferSize(self: *Viewport, new_fb_size: Vec2I) void {
        self.framebufferSize = new_fb_size;
        self.compute();
    }

    /// Calls gl.viewport with the computed rectangle. viewportPx is in raster
    /// coordinates, so this converts to GL's bottom-left convention first.
    pub fn apply(self: *const Viewport) void {
        const gl_y: i32 = self.framebufferSize.y - self.viewportPx.b;
        gl.viewport(
            self.viewportPx.l,
            gl_y,
            self.viewportPx.width(),
            self.viewportPx.height(),
        );

        gl.scissor(self.viewportPx.l, gl_y, self.viewportPx.width(), self.viewportPx.height());
        gl.enable(gl.SCISSOR_TEST);
    }

    /// Orthographic projection for the logical coordinate space.
    /// Uses raster convention: (0,0) is top-left, x grows right, y grows down.
    /// zmath signature: orthographicOffCenterLhGl(left, right, top, bottom, near, far)
    pub fn projection(self: *const Viewport) zmath.Mat {
        const lw: f32 = @floatFromInt(self.logicalSize.x);
        const lh: f32 = @floatFromInt(self.logicalSize.y);
        return zmath.orthographicOffCenterLhGl(0, lw, 0, lh, -0.1, 1000);
    }

    /// Sets the GL viewport to the full framebuffer and disables scissor testing,
    /// then returns a projection matrix whose coordinate space matches the
    /// framebuffer dimensions in pixels.  Use this for overlay UI passes that
    /// should span the entire window including any letterbox / pillarbox bars.
    /// Call eng.viewport.apply() at the start of the next game render pass to
    /// restore the clipped game viewport.
    pub fn applyFullscreen(self: *const Viewport) zmath.Mat {
        gl.disable(gl.SCISSOR_TEST);
        gl.viewport(0, 0, self.framebufferSize.x, self.framebufferSize.y);
        const fw: f32 = @floatFromInt(self.framebufferSize.x);
        const fh: f32 = @floatFromInt(self.framebufferSize.y);
        return zmath.orthographicOffCenterLhGl(0, fw, 0, fh, -0.1, 1000);
    }

    /// Converts a framebuffer-space position to logical coordinates.
    /// Returns null when pos_fb falls in a letterbox or pillarbox region.
    pub fn framebufferToLogical(self: *const Viewport, pos_fb: Vec2F) ?Vec2F {
        const lf: f32 = @floatFromInt(self.viewportPx.l);
        const tf: f32 = @floatFromInt(self.viewportPx.t);
        const rf: f32 = @floatFromInt(self.viewportPx.r);
        const bf: f32 = @floatFromInt(self.viewportPx.b);

        if (pos_fb.x < lf or pos_fb.x >= rf or pos_fb.y < tf or pos_fb.y >= bf) {
            return null;
        }

        return .{
            .x = (pos_fb.x - lf) / self.scale.x,
            .y = (pos_fb.y - tf) / self.scale.y,
        };
    }

    /// Converts a logical coordinate to a framebuffer-space position.
    pub fn logicalToFramebuffer(self: *const Viewport, pos_logical: Vec2F) Vec2F {
        const lf: f32 = @floatFromInt(self.viewportPx.l);
        const tf: f32 = @floatFromInt(self.viewportPx.t);
        return .{
            .x = lf + pos_logical.x * self.scale.x,
            .y = tf + pos_logical.y * self.scale.y,
        };
    }

    /// Converts a window-coordinate mouse position to logical game coordinates.
    /// `window_scale` is the framebuffer-to-window ratio (WindowState.scaleFactor).
    /// Returns null when pos_window maps to a letterbox or pillarbox region.
    pub fn windowToLogical(self: *const Viewport, pos_window: Vec2F, window_scale: Vec2F) ?Vec2F {
        const fb = Vec2F{
            .x = pos_window.x * window_scale.x,
            .y = pos_window.y * window_scale.y,
        };
        return self.framebufferToLogical(fb);
    }

    fn compute(self: *Viewport) void {
        const fb_w: f32 = @floatFromInt(self.framebufferSize.x);
        const fb_h: f32 = @floatFromInt(self.framebufferSize.y);
        const log_w: f32 = @floatFromInt(self.logicalSize.x);
        const log_h: f32 = @floatFromInt(self.logicalSize.y);

        if (log_w <= 0 or log_h <= 0) return;

        switch (self.policy) {
            .stretch => {
                self.scale = .{ .x = fb_w / log_w, .y = fb_h / log_h };
                self.viewportPx = .{
                    .l = 0,
                    .t = 0,
                    .r = self.framebufferSize.x,
                    .b = self.framebufferSize.y,
                };
            },
            .fit => {
                const s = @min(fb_w / log_w, fb_h / log_h);
                self.scale = .{ .x = s, .y = s };
                const vw: i32 = @intFromFloat(log_w * s);
                const vh: i32 = @intFromFloat(log_h * s);
                const ox: i32 = @intFromFloat((fb_w - log_w * s) * 0.5);
                const oy: i32 = @intFromFloat((fb_h - log_h * s) * 0.5);
                self.viewportPx = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
            },
            .fill => {
                const s = @max(fb_w / log_w, fb_h / log_h);
                self.scale = .{ .x = s, .y = s };
                const vw: i32 = @intFromFloat(log_w * s);
                const vh: i32 = @intFromFloat(log_h * s);
                const ox: i32 = @intFromFloat((fb_w - log_w * s) * 0.5);
                const oy: i32 = @intFromFloat((fb_h - log_h * s) * 0.5);
                self.viewportPx = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
            },
            .integer_fit => {
                const sx: i32 = @intFromFloat(fb_w / log_w);
                const sy: i32 = @intFromFloat(fb_h / log_h);
                const s: i32 = @max(1, @min(sx, sy));
                const sf: f32 = @floatFromInt(s);
                self.scale = .{ .x = sf, .y = sf };
                const vw: i32 = @intFromFloat(log_w * sf);
                const vh: i32 = @intFromFloat(log_h * sf);
                const ox: i32 = @intFromFloat((fb_w - log_w * sf) * 0.5);
                const oy: i32 = @intFromFloat((fb_h - log_h * sf) * 0.5);
                self.viewportPx = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
            },
            .integer_fill => {
                const sx: i32 = @intFromFloat(@ceil(fb_w / log_w));
                const sy: i32 = @intFromFloat(@ceil(fb_h / log_h));
                const s: i32 = @max(1, @max(sx, sy));
                const sf: f32 = @floatFromInt(s);
                self.scale = .{ .x = sf, .y = sf };
                const vw: i32 = @intFromFloat(log_w * sf);
                const vh: i32 = @intFromFloat(log_h * sf);
                const ox: i32 = @intFromFloat((fb_w - log_w * sf) * 0.5);
                const oy: i32 = @intFromFloat((fb_h - log_h * sf) * 0.5);
                self.viewportPx = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
            },
            .fixed => |s| {
                self.scale = .{ .x = s, .y = s };
                const vw: i32 = @intFromFloat(log_w * s);
                const vh: i32 = @intFromFloat(log_h * s);
                const ox: i32 = @intFromFloat((fb_w - log_w * s) * 0.5);
                const oy: i32 = @intFromFloat((fb_h - log_h * s) * 0.5);
                self.viewportPx = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
            },
        }
    }
};
