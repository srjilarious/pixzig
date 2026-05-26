const std = @import("std");
const zmath = @import("zmath");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const common = @import("./common.zig");

const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;
const RectI = common.RectI;
const RectF = common.RectF;

pub const ScalePolicy = union(enum) {
    stretch,
    fit,
    fill,
    integer_fit,
    integer_fill,
    fixed: f32,
};

/// Tracks GLFW window and framebuffer dimensions. Resized is set to true by
/// the framebuffer-size callback and cleared by refreshWindowState.
pub const WindowState = struct {
    window_size: Vec2I,
    framebuffer_size: Vec2I,
    content_scale: Vec2F,
    scale_factor: Vec2F,
    resized: bool = false,

    pub fn init(window: *glfw.Window) WindowState {
        var state = WindowState{
            .window_size = .{ .x = 0, .y = 0 },
            .framebuffer_size = .{ .x = 0, .y = 0 },
            .content_scale = .{ .x = 1, .y = 1 },
            .scale_factor = .{ .x = 1, .y = 1 },
        };
        state.refresh(window);
        return state;
    }

    pub fn refresh(self: *WindowState, win: *glfw.Window) void {
        const win_size = win.getSize();
        self.window_size = .{ .x = win_size[0], .y = win_size[1] };

        const fb_size = win.getFramebufferSize();
        self.framebuffer_size = .{ .x = fb_size[0], .y = fb_size[1] };

        const cs = win.getContentScale();
        self.content_scale = .{ .x = cs[0], .y = cs[1] };

        const fb_w: f32 = @floatFromInt(self.framebuffer_size.x);
        const fb_h: f32 = @floatFromInt(self.framebuffer_size.y);
        const win_w: f32 = @floatFromInt(self.window_size.x);
        const win_h: f32 = @floatFromInt(self.window_size.y);
        self.scale_factor = .{
            .x = if (win_w > 0) fb_w / win_w else 1.0,
            .y = if (win_h > 0) fb_h / win_h else 1.0,
        };
    }

    pub fn framebufferRect(self: *const WindowState) RectI {
        return .{ .l = 0, .t = 0, .r = self.framebuffer_size.x, .b = self.framebuffer_size.y };
    }
};

/// Maps a logical game resolution into a physical framebuffer rectangle.
/// viewport_px is stored in raster coordinates (top-left origin, y grows down).
pub const Viewport = struct {
    logical_size: Vec2I,
    framebuffer_size: Vec2I,
    viewport_px: RectI,
    scale: Vec2F,
    policy: ScalePolicy,

    pub fn init(logical_size: Vec2I, framebuffer_size: Vec2I, policy: ScalePolicy) Viewport {
        var vp = Viewport{
            .logical_size = logical_size,
            .framebuffer_size = framebuffer_size,
            .viewport_px = .{ .l = 0, .t = 0, .r = 0, .b = 0 },
            .scale = .{ .x = 1.0, .y = 1.0 },
            .policy = policy,
        };
        vp.compute();
        return vp;
    }

    pub fn updateFramebufferSize(self: *Viewport, new_fb_size: Vec2I) void {
        self.framebuffer_size = new_fb_size;
        self.compute();
    }

    /// Calls gl.viewport with the computed rectangle. viewport_px is in raster
    /// coordinates, so this converts to GL's bottom-left convention first.
    pub fn apply(self: *const Viewport) void {
        const gl_y: i32 = self.framebuffer_size.y - self.viewport_px.b;
        gl.viewport(
            self.viewport_px.l,
            gl_y,
            self.viewport_px.width(),
            self.viewport_px.height(),
        );

        gl.scissor(self.viewport_px.l, gl_y, self.viewport_px.width(), self.viewport_px.height());
        gl.enable(gl.SCISSOR_TEST);
    }

    /// Orthographic projection for the logical coordinate space.
    /// Uses raster convention: (0,0) is top-left, x grows right, y grows down.
    /// zmath signature: orthographicOffCenterLhGl(left, right, top, bottom, near, far)
    pub fn projection(self: *const Viewport) zmath.Mat {
        const lw: f32 = @floatFromInt(self.logical_size.x);
        const lh: f32 = @floatFromInt(self.logical_size.y);
        return zmath.orthographicOffCenterLhGl(0, lw, 0, lh, -0.1, 1000);
    }

    /// Converts a framebuffer-space position to logical coordinates.
    /// Returns null when pos_fb falls in a letterbox or pillarbox region.
    pub fn framebufferToLogical(self: *const Viewport, pos_fb: Vec2F) ?Vec2F {
        const lf: f32 = @floatFromInt(self.viewport_px.l);
        const tf: f32 = @floatFromInt(self.viewport_px.t);
        const rf: f32 = @floatFromInt(self.viewport_px.r);
        const bf: f32 = @floatFromInt(self.viewport_px.b);

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
        const lf: f32 = @floatFromInt(self.viewport_px.l);
        const tf: f32 = @floatFromInt(self.viewport_px.t);
        return .{
            .x = lf + pos_logical.x * self.scale.x,
            .y = tf + pos_logical.y * self.scale.y,
        };
    }

    /// Converts a GLFW window-coordinate mouse position to logical game coordinates.
    /// `window_scale` is the framebuffer-to-window ratio (WindowState.scale_factor).
    /// Returns null when pos_window maps to a letterbox or pillarbox region.
    pub fn windowToLogical(self: *const Viewport, pos_window: Vec2F, window_scale: Vec2F) ?Vec2F {
        const fb = Vec2F{
            .x = pos_window.x * window_scale.x,
            .y = pos_window.y * window_scale.y,
        };
        return self.framebufferToLogical(fb);
    }

    fn compute(self: *Viewport) void {
        const fb_w: f32 = @floatFromInt(self.framebuffer_size.x);
        const fb_h: f32 = @floatFromInt(self.framebuffer_size.y);
        const log_w: f32 = @floatFromInt(self.logical_size.x);
        const log_h: f32 = @floatFromInt(self.logical_size.y);

        if (log_w <= 0 or log_h <= 0) return;

        switch (self.policy) {
            .stretch => {
                self.scale = .{ .x = fb_w / log_w, .y = fb_h / log_h };
                self.viewport_px = .{
                    .l = 0,
                    .t = 0,
                    .r = self.framebuffer_size.x,
                    .b = self.framebuffer_size.y,
                };
            },
            .fit => {
                const s = @min(fb_w / log_w, fb_h / log_h);
                self.scale = .{ .x = s, .y = s };
                const vw: i32 = @intFromFloat(log_w * s);
                const vh: i32 = @intFromFloat(log_h * s);
                const ox: i32 = @intFromFloat((fb_w - log_w * s) * 0.5);
                const oy: i32 = @intFromFloat((fb_h - log_h * s) * 0.5);
                self.viewport_px = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
            },
            .fill => {
                const s = @max(fb_w / log_w, fb_h / log_h);
                self.scale = .{ .x = s, .y = s };
                const vw: i32 = @intFromFloat(log_w * s);
                const vh: i32 = @intFromFloat(log_h * s);
                const ox: i32 = @intFromFloat((fb_w - log_w * s) * 0.5);
                const oy: i32 = @intFromFloat((fb_h - log_h * s) * 0.5);
                self.viewport_px = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
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
                self.viewport_px = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
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
                self.viewport_px = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
            },
            .fixed => |s| {
                self.scale = .{ .x = s, .y = s };
                const vw: i32 = @intFromFloat(log_w * s);
                const vh: i32 = @intFromFloat(log_h * s);
                const ox: i32 = @intFromFloat((fb_w - log_w * s) * 0.5);
                const oy: i32 = @intFromFloat((fb_h - log_h * s) * 0.5);
                self.viewport_px = .{ .l = ox, .t = oy, .r = ox + vw, .b = oy + vh };
            },
        }
    }
};
