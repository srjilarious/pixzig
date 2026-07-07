const std = @import("std");
const glfw = @import("zglfw");
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

var g_instance: ?GlTestContext = null;

/// A minimal hidden GLFW/OpenGL 4.5 context for unit tests that need real GL.
/// The window is never shown.
///
/// Use initGlobal/deinitGlobal from the test binary's main(), then call get()
/// from any test module that needs GL access.
pub const GlTestContext = struct {
    window: *glfw.Window,

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
        try glfw.init();
        errdefer glfw.terminate();

        glfw.windowHint(.visible, false);
        glfw.windowHint(.context_version_major, 4);
        glfw.windowHint(.context_version_minor, 5);
        glfw.windowHint(.opengl_profile, .opengl_core_profile);
        glfw.windowHint(.opengl_forward_compat, true);
        glfw.windowHint(.client_api, .opengl_api);

        const window = try glfw.createWindow(64, 64, "pixzig-test", null, null);
        errdefer glfw.destroyWindow(window);

        glfw.makeContextCurrent(window);
        try zopengl.loadCoreProfile(glfw.getProcAddress, 4, 5);

        return .{ .window = window };
    }

    pub fn deinit(self: *Self) void {
        glfw.destroyWindow(self.window);
        glfw.terminate();
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
