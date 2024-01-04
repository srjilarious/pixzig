// zig fmt: off
const std = @import("std");
const sdl = @import("zsdl");
const glfw = @import("zglfw");
const stbi = @import("zstbi");

const gl = @import("zopengl");

const zgui = @import("zgui");

pub const common = @import("./common.zig");
pub const sprites = @import("./sprites.zig");
pub const input = @import("./input.zig");
pub const tile = @import("./tile.zig");
pub const shaders = @import("./shaders.zig");
pub const textures= @import("./textures.zig");
pub const renderer = @import("./renderer.zig");

pub const Texture = textures.Texture;
const TextureManager = textures.TextureManager;

pub const Vec2I = common.Vec2I;

pub const PixzigEngineOptions = struct {
    withGui: bool = true,
    windowSize: Vec2I = .{ .x = 800, .y = 600 },
};


pub fn PixzigApp(comptime T: type) type {
    return struct {
        const AppUpdateFunc = fn (*T, *PixzigEngine, f64) bool;
        const AppRenderFunc = fn (*T, *PixzigEngine) void;
        
        pub fn gameLoop(self: *T, eng: *PixzigEngine) void {
            // Main loop
            while (!eng.window.shouldClose()) {
                glfw.pollEvents();

                _ = self.update(eng, 1);
                self.render(eng);

                eng.window.swapBuffers();
            }
        }
    };
}

pub const PixzigEngine = struct {
    window: *glfw.Window,
    options: PixzigEngineOptions,
    scaleFactor: f32,
    allocator: std.mem.Allocator,
    textures: TextureManager,
    keyboard: input.Keyboard,

    pub fn init(title: [:0]const u8, 
                allocator: std.mem.Allocator,
                options: PixzigEngineOptions) !PixzigEngine {
        try glfw.init();

        // // Change current working directory to where the executable is located.
        // {
        //     var buffer: [1024]u8 = undefined;
        //     const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        //     std.os.chdir(path) catch {};
        // }

        const gl_major = 4;
        const gl_minor = 0;
        glfw.windowHintTyped(.context_version_major, gl_major);
        glfw.windowHintTyped(.context_version_minor, gl_minor);
        glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
        glfw.windowHintTyped(.opengl_forward_compat, true);
        glfw.windowHintTyped(.client_api, .opengl_api);
        glfw.windowHintTyped(.doublebuffer, true);

        const window = try glfw.Window.create(
                options.windowSize.x, 
                options.windowSize.y, 
                title, 
                null
            );
        window.setSizeLimits(400, 400, -1, -1);

        glfw.makeContextCurrent(window);
        glfw.swapInterval(1);

        try gl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);
        
        const scale_factor = scale_factor: {
            const scale = window.getContentScale();
            break :scale_factor @max(scale[0], scale[1]);
        };

        if(options.withGui) {
            zgui.init(allocator);
            zgui.getStyle().scaleAllSizes(scale_factor);
            zgui.backend.init(window);
        }

        stbi.init(allocator);
        return .{
            .window = window,
            .options = options,
            .scaleFactor = scale_factor,
            .allocator = allocator,
            .textures = TextureManager.init(allocator),
            .keyboard = input.Keyboard.init(window, allocator),
        };
    }

    pub fn deinit(self: *PixzigEngine) void {
        stbi.deinit();
        self.textures.destroy();

        if(self.options.withGui) {
            zgui.backend.deinit();
            zgui.deinit();
        }

        self.window.destroy();
        glfw.terminate();
        
    }
};
