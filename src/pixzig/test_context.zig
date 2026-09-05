const std = @import("std");
const sdl = @import("sdl3");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;

const resources = @import("./resources.zig");
const shaders_mod = @import("./renderer/shaders.zig");
const textures_mod = @import("./renderer/textures.zig");
const common = @import("./common.zig");

const ManagedShader = resources.ManagedShader;
const ManagedTexture = resources.ManagedTexture;
const Shader = shaders_mod.Shader;
const ShaderCode = shaders_mod.ShaderCode;
const Texture = textures_mod.Texture;
const RectF = common.RectF;

fn freeShaderImpl(s: Shader) void {
    var copy = s;
    copy.deinit();
}

fn freeTextureNoop(_: Texture) void {}

fn sdlError(err: anyerror) anyerror {
    std.log.err("SDL3: {s}", .{sdl.SDL_GetError()});
    return err;
}

fn glProcAddress(proc_name: [*:0]const u8) callconv(.c) ?*const anyopaque {
    return @ptrCast(sdl.SDL_GL_GetProcAddress(proc_name));
}

var g_instance: ?GlTestContext = null;

/// A minimal hidden SDL3/OpenGL 4.5 context for unit tests that need real GL.
/// The window is never shown.
///
/// Use initGlobal/deinitGlobal from the test binary's main(), then call get()
/// from any test module that needs GL access.
pub const GlTestContext = struct {
    window: *sdl.SDL_Window,
    gl_context: sdl.SDL_GLContext,

    const Self = @This();

    /// Initialize the process-level GL context. Call once from test main().
    pub fn initGlobal() !void {
        g_instance = try GlTestContext.init();
    }

    /// Tear down the process-level GL context. Call from test main() via defer.
    pub fn deinitGlobal() void {
        if (g_instance) |*ctx| ctx.deinit();
        g_instance = null;
    }

    /// Return the process-level GL context. Panics if initGlobal was not called.
    pub fn get() *GlTestContext {
        return &g_instance.?;
    }

    pub fn init() !Self {
        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) return sdlError(error.SdlInitFailed);
        errdefer sdl.SDL_Quit();

        if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 4)) return sdlError(error.SdlGlAttributeFailed);
        if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 5)) return sdlError(error.SdlGlAttributeFailed);
        if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE)) return sdlError(error.SdlGlAttributeFailed);
        if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_FLAGS, sdl.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG)) return sdlError(error.SdlGlAttributeFailed);

        const window = sdl.SDL_CreateWindow("pixzig-test", 64, 64, sdl.SDL_WINDOW_OPENGL | sdl.SDL_WINDOW_HIDDEN) orelse
            return sdlError(error.SdlCreateWindowFailed);
        errdefer sdl.SDL_DestroyWindow(window);

        const gl_context = sdl.SDL_GL_CreateContext(window) orelse return sdlError(error.SdlCreateContextFailed);
        errdefer _ = sdl.SDL_GL_DestroyContext(gl_context);

        if (!sdl.SDL_GL_MakeCurrent(window, gl_context)) return sdlError(error.SdlMakeCurrentFailed);
        try zopengl.loadCoreProfile(glProcAddress, 4, 5);

        return .{ .window = window, .gl_context = gl_context };
    }

    pub fn deinit(self: *Self) void {
        _ = sdl.SDL_GL_MakeCurrent(self.window, null);
        _ = sdl.SDL_GL_DestroyContext(self.gl_context);
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }

    /// Compiles the standard texture shader and wraps it in a ManagedShader.
    /// The caller owns the returned value and must call `managedShader.deinit()`.
    pub fn makeManagedShader(_: *Self, alloc: std.mem.Allocator) !ManagedShader {
        const vs_arr = [_]ShaderCode{shaders_mod.TexVertexShader};
        const fs_arr = [_]ShaderCode{shaders_mod.TexPixelShader};
        const shader = try Shader.init(&vs_arr, &fs_arr);
        var managed = ManagedShader.init(alloc, 1, freeShaderImpl);
        try managed.add(shader);
        return managed;
    }

    /// Returns a ManagedTexture containing a dummy Texture with no real GL object.
    /// Suitable for tile renderer tests where tiles are all empty (no draw calls
    /// actually sample the texture). The caller owns the returned value.
    pub fn makeDummyManagedTexture(_: *Self, alloc: std.mem.Allocator) !ManagedTexture {
        const tex = Texture{
            .texture = 0,
            .size = .{ .x = 128, .y = 128 },
            .src = .{ .l = 0, .t = 0, .r = 1, .b = 1 },
        };
        var managed = ManagedTexture.init(alloc, 1, freeTextureNoop);
        try managed.add(tex);
        return managed;
    }
};
