const std = @import("std");
const builtin = @import("builtin");
pub const glfw = @import("zglfw");
pub const stbi = @import("zstbi");

pub const zopengl = @import("zopengl");
pub const gl = zopengl.bindings;
pub const zmath = @import("zmath");
// pub const zgui = @import("zgui");
pub const ziglua = @import("ziglua");
pub const flecs = @import("zflecs");
pub const xml = @import("xml");
pub const stb_tt = @import("stb_truetype");

pub const common = @import("./common.zig");
pub const input = @import("./input.zig");
pub const events = @import("./events.zig");
pub const tile = @import("./tile.zig");
pub const resources = @import("./resources.zig");
pub const sprites = @import("./renderer/sprites.zig");
pub const shaders = @import("./renderer/shaders.zig");
pub const textures = @import("./renderer/textures.zig");
pub const pixel_buffer = @import("./renderer/pixel_buffer.zig");
pub const renderer = @import("./renderer.zig");
pub const utils = @import("./utils.zig");
pub const gamestate = @import("./gamestate.zig");
pub const scripting = @import("./scripting.zig");
// pub const console = @import("./console.zig");
pub const console2 = @import("./console2.zig");
pub const collision = @import("./collision.zig");
pub const a_star = @import("./a_star.zig");
pub const system = @import("./system.zig");
pub const assets = @import("./assets.zig");

pub const Texture = textures.Texture;
pub const TextureImage = textures.TextureImage;

const ResourceManager = resources.ResourceManager;

pub const Vec2I = common.Vec2I;
pub const RectI = common.RectI;
pub const RectF = common.RectF;
pub const Color = common.Color;
pub const Color8 = common.Color8;

pub const PixzigEngineOptions = struct {
    defaultIcon: bool = true,
    gameScale: f32 = 1.0,
    rendererOpts: renderer.RendererOptions = .{},
};

pub const PixzigEngineInitOptions = struct {
    fullscreen: bool = false,
    windowSize: Vec2I = .{ .x = 800, .y = 600 },
    renderInitOpts: renderer.RendererInitOpts = .{},
};

pub const web = if (builtin.os.tag == .emscripten) @import("./web.zig") else {};

// Globals used by AppRunner main loop in emscripten for web builds.
var g_EmscriptenRunnerRef: ?*anyopaque = null;
var g_EmscriptenAppRef: ?*anyopaque = null;

pub fn PixzigAppRunner(comptime AppData: type, comptime engOpts: PixzigEngineOptions) type {
    const AppStruct = struct {
        pub const Engine = PixzigEngine(engOpts);

        const UpdateStepMs: f64 = 1000.0 / 120.0;

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
            const newCurrTime = glfw.getTime() * 1000.0;
            const delta = newCurrTime - self.currTime;
            self.lag += delta;
            self.currTime = newCurrTime;

            glfw.pollEvents();

            while (self.lag > UpdateStepMs) {
                self.lag -= UpdateStepMs;

                self.engine.keyboard.update(self.engine.window);
                if (!app.update(self.engine, UpdateStepMs)) {
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
                if (!self.gameLoopCore(app)) return;
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
        projMat: zmath.Mat,
        resources: ResourceManager,
        keyboard: input.Keyboard,
        renderer: Renderer = undefined,

        const Self = @This();
        pub const Renderer = renderer.Renderer(engOpts.rendererOpts);

        pub fn init(title: [:0]const u8, allocator: std.mem.Allocator, options: PixzigEngineInitOptions) !*Self {
            try glfw.init();

            std.log.debug("GLFW initialized.\n", .{});

            const gl_major, const gl_minor = blk: {
                if (builtin.target.os.tag == .emscripten) {
                    break :blk .{ 2, 0 };
                } else {
                    break :blk .{ 4, 5 };
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
                if (options.fullscreen) {
                    break :blk glfw.Monitor.getPrimary();
                } else {
                    break :blk null;
                }
            };
            const window = try glfw.Window.create(options.windowSize.x, options.windowSize.y, title, monitor);
            window.setSizeLimits(400, 400, -1, -1);

            glfw.makeContextCurrent(window);
            glfw.swapInterval(1);

            std.log.info("Loading OpenGL profile.", .{});
            if (builtin.target.os.tag == .emscripten) {
                try zopengl.loadEsProfile(glfw.getProcAddress, gl_major, gl_minor);
                try zopengl.loadEsExtension(glfw.getProcAddress, .OES_vertex_array_object);
            } else {
                try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);
            }

            const glVersion = gl.getString(gl.VERSION);
            const glslVersion = gl.getString(gl.SHADING_LANGUAGE_VERSION);

            std.log.info("GL Version: {s}", .{glVersion});
            std.log.info("GLSL Version: {s}", .{glslVersion});

            const scaleFactor = scaleFactor: {
                const scale = window.getContentScale();
                break :scaleFactor @max(scale[0], scale[1]);
            };

            // if (engOpts.withGui) {
            //     std.log.info("Initializing GUI system.", .{});
            //     zgui.init(allocator);
            //     zgui.getStyle().scaleAllSizes(scaleFactor);
            //     zgui.backend.initWithGlSlVersion(window, "#version 300 es");
            //     // zgui.backend.initOpenGL(window);
            // }

            std.log.debug("Initializing STBI.", .{});
            stbi.init(allocator);

            std.log.info("Pixzig Engine Initialized.", .{});

            // Create a default 2D orthogrpaphic projection matrix fitting the window.
            // Also allow scaling the game content with engOpts.gameScale.
            const projMat = zmath.mul(zmath.scaling(engOpts.gameScale, engOpts.gameScale, 1.0), zmath.orthographicOffCenterLhGl(
                0,
                @as(f32, @floatFromInt(options.windowSize.x)) * scaleFactor,
                0,
                @as(f32, @floatFromInt(options.windowSize.y)) * scaleFactor,
                -0.1,
                1000,
            ));

            const eng = try allocator.create(Self);
            eng.* = .{
                .window = window,
                .options = options,
                .scaleFactor = scaleFactor,
                .allocator = allocator,
                .projMat = projMat,
                .resources = ResourceManager.init(allocator),
                .keyboard = input.Keyboard.init(),
                .renderer = undefined,
            };

            eng.renderer = try Renderer.init(allocator, &eng.resources, options.renderInitOpts);
            if (engOpts.defaultIcon) {
                std.log.debug("Setting default window icon.", .{});
                var defaultIcon = std.io.Reader.fixed(assets.icon48x48);
                try eng.setIcon(&defaultIcon);
            }

            return eng;
        }

        pub fn deinit(self: *Self) void {
            stbi.deinit();
            self.resources.deinit();

            // if (engOpts.withGui) {
            //     zgui.backend.deinit();
            //     zgui.deinit();
            // }

            self.window.destroy();
            glfw.terminate();

            self.allocator.destroy(self);
        }

        pub fn setIcon(self: *Self, icon_data: *std.io.Reader) !void {
            if (builtin.os.tag != .emscripten) {
                const data_buffer = try icon_data.readAlloc(self.allocator, icon_data.end);
                defer self.allocator.free(data_buffer);

                var icon_image = try stbi.Image.loadFromMemory(data_buffer, 4);
                defer icon_image.deinit();

                const icon = glfw.Image{
                    .width = @intCast(icon_image.width),
                    .height = @intCast(icon_image.height),
                    .pixels = icon_image.data.ptr,
                };

                self.window.setIcon(&.{icon});
            }
        }
    };
}
