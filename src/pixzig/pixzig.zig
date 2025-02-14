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
    rendererOpts: renderer.RendererOptions = .{}
};

pub const PixzigEngineInitOptions = struct {
    fullscreen: bool = false,
    windowSize: Vec2I = .{ .x = 800, .y = 600 },
    renderInitOpts: renderer.RendererInitOpts = .{},
};

pub const web = if(builtin.os.tag == .emscripten) @import("./web.zig") else {};

// Globals used by AppRunner main loop in emscripten for web builds.
var g_EmscriptenRunnerRef: ?*anyopaque = null;
var g_EmscriptenAppRef: ?*anyopaque = null;

pub fn PixzigAppRunner(comptime AppData: type, comptime engOpts: PixzigEngineOptions) type {

    const AppStruct = struct {
        pub const Engine = PixzigEngine(engOpts);
        const AppUpdateFunc = fn (*AppData, *PixzigEngine, f64) bool;
        const AppRenderFunc = fn (*AppData, *PixzigEngine) void;
        
        const UpdateStepUs: f64 = 1.0 / 120.0;

        engine: *Engine,
        alloc: std.mem.Allocator,
        lag: f64 = 0,
        currTime: f64 = 0,

        const Self = @This();

        pub fn init(
            title: [:0]const u8, 
            alloc: std.mem.Allocator,
            engInitOpts: PixzigEngineInitOptions,
        ) !*Self {
            var appRunner = try alloc.create(Self);
            appRunner.engine = try Engine.init(title, alloc, engInitOpts);
            appRunner.alloc = alloc;
            appRunner.currTime = glfw.getTime();
            return appRunner;
        }

        pub fn deinit(self: *Self) void {
            self.engine.deinit();
            self.alloc.destroy(self);
        }

        pub fn gameLoopCore(self: *Self, app: *AppData) bool {
            const newCurrTime = glfw.getTime();
            const delta = newCurrTime - self.currTime;
            self.lag += delta;
            self.currTime = newCurrTime;

            glfw.pollEvents();


            while(self.lag > UpdateStepUs) {
                self.lag -= UpdateStepUs;

                if(!app.update(self.engine, UpdateStepUs)) {
                    return false;
                }
            }

            app.render(self.engine);
            self.engine.window.swapBuffers();
            return true;
        }

        pub fn gameLoop(self: *Self, app: *AppData) void {
            // Main loop
            while (!self.engine.window.shouldClose()) {
                if(!self.gameLoopCore(app)) return;
            }
        }

        export fn mainLoop() void {
            const appRunner: *Self = @ptrCast(@alignCast(g_EmscriptenRunnerRef.?));
            const app: *AppData = @ptrCast(@alignCast(g_EmscriptenAppRef.?));
            _ = appRunner.gameLoopCore(app);
        }

        pub fn run(self: *Self, app: *AppData) void {
            std.log.info("Starting main loop...\n", .{});
            if (builtin.target.os.tag == .emscripten) {
                g_EmscriptenRunnerRef = @constCast(self);
                g_EmscriptenAppRef = @constCast(app);
                web.setMainLoop(mainLoop, null, false);
            } else {
                self.gameLoop(app);
                app.deinit();
                self.deinit();
            }
        } 
    };

    return AppStruct;
}

pub fn PixzigEngine(comptime engOpts: PixzigEngineOptions) type {
    return struct {
        window: *glfw.Window,
        options: PixzigEngineInitOptions,
        scaleFactor: f32,
        allocator: std.mem.Allocator,
        textures: TextureManager,
        keyboard: input.Keyboard,
        renderer: EngRenderer,

        const Self = @This();
        const EngRenderer = renderer.Renderer(engOpts.rendererOpts);

        pub fn init(title: [:0]const u8, 
                    allocator: std.mem.Allocator,
                    options: PixzigEngineInitOptions) !*Self {
            try glfw.init();

            std.log.debug("GLFW initialized.\n", .{});

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

            std.log.info("Loading OpenGL profile.", .{});
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

            if(engOpts.withGui) {
                std.log.info("Initializing GUI system.", .{});
                zgui.init(allocator);
                zgui.getStyle().scaleAllSizes(scale_factor);
                zgui.backend.init(window);
            }

            std.log.debug("Initializing STBI.", .{});
            stbi.init(allocator);

            std.log.info("Pixzig Engine Initialized.", .{});

            const eng = try allocator.create(Self);
            eng.* = .{
                .window = window,
                .options = options,
                .scaleFactor = scale_factor,
                .allocator = allocator,
                .textures = TextureManager.init(allocator),
                .keyboard = input.Keyboard.init(window, allocator),
                .renderer = try EngRenderer.init(allocator, options.renderInitOpts),
            };
            return eng;
        }

        pub fn deinit(self: *Self) void {
            stbi.deinit();
            self.textures.destroy();

            if(engOpts.withGui) {
                zgui.backend.deinit();
                zgui.deinit();
            }

            self.window.destroy();
            glfw.terminate();

            self.allocator.destroy(self);
        }
    };
}
