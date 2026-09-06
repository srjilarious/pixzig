//! The SDL3 window and OpenGL context, wrapped so nothing above this file
//! needs to know which windowing library is underneath.
//!
//! `PixzigEngine` owns one of these as `eng.window`. Callers use the
//! `*platform.Window` API (`swapBuffers`, `shouldClose`, `getSize`, ...)
//! instead of naming SDL directly.

const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const stbi = @import("zstbi");
const common = @import("../common.zig");

const Vec2I = common.Vec2I;

/// Logs SDL's error string alongside the Zig error being returned. SDL
/// reports failures through a thread-local string rather than a code, so
/// without this the error is just `error.SdlCreateWindowFailed` with no
/// hint as to why.
pub fn sdlError(err: anyerror) anyerror {
    std.log.err("SDL3: {s}", .{sdl.SDL_GetError()});
    return err;
}

/// Options that must be known before the window exists. A subset of
/// `PixzigEngineInitOptions`; passed separately so this file does not have
/// to import the engine and create an import cycle.
pub const WindowCreateOptions = struct {
    size: Vec2I,
    resizable: bool,
    fullscreen: bool,
    /// Arms SDL's text-input machinery on the window, which is what makes
    /// `SDL_EVENT_TEXT_INPUT` (and the IME composition events) arrive at
    /// all. See `InputOptions.textInput`.
    text_input: bool,
};

pub const Window = struct {
    allocator: std.mem.Allocator,
    handle: *sdl.SDL_Window,
    gl_context: sdl.SDL_GLContext,
    /// SDL has no `shouldClose()`; the quit and window-close events set
    /// this instead, and `shouldClose()` reads it.
    close_requested: bool = false,
    /// Backing store for `getClipboardString`. SDL hands back a buffer the
    /// caller must free; copying into a window-owned buffer keeps the
    /// borrowed-slice signature callers expect.
    clipboard_buf: std.ArrayList(u8) = .empty,
    /// Whether `SDL_StartTextInput` succeeded, so `deinit` knows whether
    /// there is anything to stop.
    text_input_active: bool = false,

    pub fn create(
        allocator: std.mem.Allocator,
        title: [:0]const u8,
        options: WindowCreateOptions,
    ) !*Window {
        // HIGH_PIXEL_DENSITY is what makes the framebuffer genuinely
        // larger than the window on a HiDPI display, which is what
        // WindowState.scale_factor and all the mouse coordinate math
        // assume. Without it SDL silently hands back a 1x framebuffer.
        var flags: sdl.SDL_WindowFlags = sdl.SDL_WINDOW_OPENGL | sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY;
        if (options.resizable) flags |= sdl.SDL_WINDOW_RESIZABLE;
        if (options.fullscreen) flags |= sdl.SDL_WINDOW_FULLSCREEN;

        const handle = sdl.SDL_CreateWindow(title.ptr, options.size.x, options.size.y, flags) orelse
            return sdlError(error.SdlCreateWindowFailed);
        errdefer sdl.SDL_DestroyWindow(handle);

        _ = sdl.SDL_SetWindowMinimumSize(handle, 400, 400);

        const gl_context = sdl.SDL_GL_CreateContext(handle) orelse
            return sdlError(error.SdlCreateContextFailed);
        errdefer _ = sdl.SDL_GL_DestroyContext(gl_context);

        if (!sdl.SDL_GL_MakeCurrent(handle, gl_context)) return sdlError(error.SdlMakeCurrentFailed);

        const window = try allocator.create(Window);
        window.* = .{
            .allocator = allocator,
            .handle = handle,
            .gl_context = gl_context,
        };

        if (options.text_input) {
            // A failure here costs typed text and IME support but leaves a
            // perfectly usable window, so warn rather than abort startup.
            if (sdl.SDL_StartTextInput(handle)) {
                window.text_input_active = true;
            } else {
                std.log.warn("SDL_StartTextInput failed, typed text will be unavailable: {s}", .{sdl.SDL_GetError()});
            }
        }

        return window;
    }

    pub fn destroy(self: *Window) void {
        self.clipboard_buf.deinit(self.allocator);
        if (self.text_input_active) _ = sdl.SDL_StopTextInput(self.handle);
        _ = sdl.SDL_GL_MakeCurrent(self.handle, null);
        _ = sdl.SDL_GL_DestroyContext(self.gl_context);
        sdl.SDL_DestroyWindow(self.handle);
        self.allocator.destroy(self);
    }

    pub fn swapBuffers(self: *Window) void {
        _ = sdl.SDL_GL_SwapWindow(self.handle);
    }

    pub fn shouldClose(self: *const Window) bool {
        return self.close_requested;
    }

    /// Asks the main loop to exit, as if the user had closed the window.
    pub fn requestClose(self: *Window) void {
        self.close_requested = true;
    }

    /// Window size in screen coordinates, not pixels. On HiDPI this is
    /// smaller than `getFramebufferSize`.
    pub fn getSize(self: *const Window) Vec2I {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = sdl.SDL_GetWindowSize(self.handle, &w, &h);
        return .{ .x = @intCast(w), .y = @intCast(h) };
    }

    /// Sets the window size. In screen coordinates, so a caller working in
    /// framebuffer pixels has to divide by the scale factor first.
    pub fn setSize(self: *Window, width: i32, height: i32) void {
        _ = sdl.SDL_SetWindowSize(self.handle, width, height);
    }

    pub fn setSizeLimits(self: *Window, min_w: i32, min_h: i32) void {
        _ = sdl.SDL_SetWindowMinimumSize(self.handle, min_w, min_h);
    }

    /// Framebuffer size in actual pixels: what OpenGL draws into.
    pub fn getFramebufferSize(self: *const Window) Vec2I {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = sdl.SDL_GetWindowSizeInPixels(self.handle, &w, &h);
        return .{ .x = @intCast(w), .y = @intCast(h) };
    }

    /// The display's content scale. SDL reports one value, and
    /// `WindowState` stores it for both axes.
    pub fn getDisplayScale(self: *const Window) f32 {
        const scale = sdl.SDL_GetWindowDisplayScale(self.handle);
        return if (scale > 0) scale else 1.0;
    }

    /// Sets the window icon from decoded RGBA8 pixels.
    pub fn setIcon(self: *Window, image: *const stbi.Image) void {
        const surface = sdl.SDL_CreateSurfaceFrom(
            @intCast(image.width),
            @intCast(image.height),
            sdl.SDL_PIXELFORMAT_RGBA32,
            image.data.ptr,
            @intCast(image.bytes_per_row),
        ) orelse {
            std.log.warn("SDL_CreateSurfaceFrom failed: {s}", .{sdl.SDL_GetError()});
            return;
        };
        // The surface borrows `image.data`; SDL copies what it needs out
        // of it during SetWindowIcon, so destroying it here is safe.
        defer sdl.SDL_DestroySurface(surface);

        if (!sdl.SDL_SetWindowIcon(self.handle, surface)) {
            std.log.warn("SDL_SetWindowIcon failed: {s}", .{sdl.SDL_GetError()});
        }
    }

    pub fn setClipboardString(self: *Window, text: [:0]const u8) void {
        _ = self;
        if (!sdl.SDL_SetClipboardText(text.ptr)) {
            std.log.warn("SDL_SetClipboardText failed: {s}", .{sdl.SDL_GetError()});
        }
    }

    /// The clipboard contents, borrowed from this window and valid until
    /// the next call. Null when the clipboard is empty or unreadable.
    pub fn getClipboardString(self: *Window) ?[]const u8 {
        const text = sdl.SDL_GetClipboardText() orelse return null;
        defer sdl.SDL_free(text);

        const slice = std.mem.span(text);
        self.clipboard_buf.clearRetainingCapacity();
        self.clipboard_buf.appendSlice(self.allocator, slice) catch return null;
        return self.clipboard_buf.items;
    }

    /// Tells the OS where the text caret is so an IME puts its candidate
    /// window next to it rather than at the window origin. The rect is in
    /// *window* coordinates, so a caller holding a framebuffer-pixel rect
    /// must divide it by `WindowState.scale_factor` first.
    pub fn setTextInputArea(self: *Window, x: i32, y: i32, width: i32, height: i32, cursor: i32) void {
        var rect = sdl.SDL_Rect{ .x = x, .y = y, .w = width, .h = height };
        if (!sdl.SDL_SetTextInputArea(self.handle, &rect, cursor)) {
            std.log.warn("SDL_SetTextInputArea failed: {s}", .{sdl.SDL_GetError()});
        }
    }
};

/// Shows or hides the system cursor. SDL3 applies this process-wide.
pub fn showCursor(visible: bool) void {
    _ = if (visible) sdl.SDL_ShowCursor() else sdl.SDL_HideCursor();
}

/// Milliseconds since SDL was initialised, as a float.
pub fn timeMs() f64 {
    return @as(f64, @floatFromInt(sdl.SDL_GetTicksNS())) / 1_000_000.0;
}

/// Sets the swap interval. Fails harmlessly on drivers that refuse it.
pub fn setSwapInterval(interval: i32) void {
    if (!sdl.SDL_GL_SetSwapInterval(interval)) {
        std.log.warn("SDL_GL_SetSwapInterval failed: {s}", .{sdl.SDL_GetError()});
    }
}

/// `zopengl`'s loader wants a plain C function pointer; SDL's own getter
/// has a different signature, so this adapts it.
pub fn glProcAddress(proc_name: [*:0]const u8) callconv(.c) ?*const anyopaque {
    return @ptrCast(sdl.SDL_GL_GetProcAddress(proc_name));
}

/// Brings up SDL's video subsystem and requests the GL context version the
/// target needs (ES 2.0 under Emscripten, core 4.5 on desktop). Must run
/// before any window is created. Returns the requested (major, minor).
pub fn initVideo() !struct { c_int, c_int } {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) return sdlError(error.SdlInitFailed);
    errdefer sdl.SDL_Quit();

    const gl_major: c_int, const gl_minor: c_int = if (builtin.target.os.tag == .emscripten)
        .{ 2, 0 }
    else
        .{ 4, 5 };

    if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, gl_major)) return sdlError(error.SdlGlAttributeFailed);
    if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, gl_minor)) return sdlError(error.SdlGlAttributeFailed);
    if (builtin.target.os.tag == .emscripten) {
        // WebGL comes through SDL's GLES profile; the core/forward-compat
        // flags the desktop path sets are not valid there.
        if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_ES)) return sdlError(error.SdlGlAttributeFailed);
    } else {
        if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE)) return sdlError(error.SdlGlAttributeFailed);
        if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_FLAGS, sdl.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG)) return sdlError(error.SdlGlAttributeFailed);
    }
    if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DOUBLEBUFFER, 1)) return sdlError(error.SdlGlAttributeFailed);

    return .{ gl_major, gl_minor };
}

/// Tears down every SDL subsystem. Pairs with `initVideo`.
pub fn quit() void {
    sdl.SDL_Quit();
}
