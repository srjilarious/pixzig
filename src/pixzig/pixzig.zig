// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("zsdl");
const glfw = @import("zglfw");
const stbi = @import("zstbi");

const zopengl = @import("zopengl");
const gl = zopengl.bindings;

const zgui = @import("zgui");

pub const common = @import("./common.zig");
pub const sprites = @import("./sprites.zig");
pub const input = @import("./input.zig");
pub const tile = @import("./tile.zig");
pub const shaders = @import("./shaders.zig");
pub const textures= @import("./textures.zig");
pub const renderer = @import("./renderer.zig");
pub const utils = @import("./utils.zig");
pub const gamestate = @import("./gamestate.zig");
pub const scripting = @import("./scripting.zig");
pub const console = @import("./console.zig");
pub const collision = @import("./collision.zig");
pub const a_star = @import("./a_star.zig");
pub const system = @import("./system.zig");

pub const Texture = textures.Texture;
const TextureManager = textures.TextureManager;

pub const Vec2I = common.Vec2I;
pub const RectF = common.RectF;
pub const Color = common.Color;
pub const Color8 = common.Color8;


pub const PixzigEngineOptions = struct {
    withGui: bool = false,
    fullscreen: bool = false,
    windowSize: Vec2I = .{ .x = 800, .y = 600 },
};

pub const web = if(builtin.os.tag == .emscripten) @import("./web.zig") else {};

pub fn PixzigApp(comptime T: type) type {
    const AppStruct = struct {
        const AppUpdateFunc = fn (*T, *PixzigEngine, f64) bool;
        const AppRenderFunc = fn (*T, *PixzigEngine) void;
        
        const UpdateStepUs: f64 = 1.0 / 120.0;

        lag: f64 = 0,
        currTime: f64 = 0,

        const Self = @This();

        pub fn begin(self: *Self) void {
            self.currTime = glfw.getTime();
        }

        pub fn gameLoopCore(self: *Self, app: *T, eng: *PixzigEngine) bool {
            const newCurrTime = glfw.getTime();
            const delta = newCurrTime - self.currTime;
            self.lag += delta;
            self.currTime = newCurrTime;

            glfw.pollEvents();


            while(self.lag > UpdateStepUs) {
                self.lag -= UpdateStepUs;

                if(!app.update(eng, UpdateStepUs)) {
                    return false;
                }
            }

            app.render(eng);
            eng.window.swapBuffers();
            return true;
        }

        pub fn gameLoop(self: *Self, app: *T, eng: *PixzigEngine) void {
            // Main loop
            while (!eng.window.shouldClose()) {
                if(!self.gameLoopCore(app, eng)) return;
            }
        }
    };

    return AppStruct;
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

        std.debug.print("GLFW initialized.\n", .{});

        const gl_major, const gl_minor = blk: {
            if(builtin.target.os.tag == .emscripten) {
                break :blk .{2, 0};
            }
            else {
                break :blk .{4, 5};
            }
        };

        glfw.windowHint(.context_version_major, gl_major);
        glfw.windowHint(.context_version_minor, gl_minor);
        
        glfw.windowHint(.opengl_profile, .opengl_core_profile);
        glfw.windowHint(.opengl_forward_compat, true);
        glfw.windowHint(.client_api, .opengl_api);
        glfw.windowHint(.doublebuffer, true);
        glfw.windowHint(.resizable, false);

        const monitor = blk: {
            if(options.fullscreen) {
                break :blk glfw.Monitor.getPrimary();
            }
            else {
                break :blk  null;
            }
        };
        const window = try glfw.Window.create(
                options.windowSize.x,
                options.windowSize.y,
                title,
                monitor
            );
        window.setSizeLimits(400, 400, -1, -1);

        glfw.makeContextCurrent(window);
        glfw.swapInterval(1);

        if(builtin.target.os.tag == .emscripten) {
            try zopengl.loadEsProfile(glfw.getProcAddress, gl_major, gl_minor);
            try zopengl.loadEsExtension(glfw.getProcAddress, .OES_vertex_array_object);
        } else {
            try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);
        }
        
        const glVersion = gl.getString(gl.VERSION);
        const glslVersion = gl.getString(gl.SHADING_LANGUAGE_VERSION);

        std.log.info("GL Version: {s}", .{glVersion});
        std.log.info("GLSL Version: {s}", .{glslVersion});

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
