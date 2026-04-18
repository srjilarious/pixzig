//! The top-level Pixzig module.  This is the main entry point for users of
//! the engine, and it re-exports all the main components of the engine, such
//! as the renderer, audio engine, resource manager, etc.  It also defines the
//! main application runner structure `PixzigAppRunner` and the core engine
//! structure `PixzigEngine`.  The `PixzigAppRunner` is the recommended way
//! to set up and run a Pixzig application, as it handles the main loop and
//! resource cleanup for both desktop and web builds properly.  The
//! `PixzigEngine` provides access to the various subsystems of the engine
//! and is passed to the application update and render functions each frame.
//!
//! The `PixzigEngineOptions` and `PixzigEngineInitOptions` structures allow
//! configuring the engine at compile time and runtime, respectively, so that
//! unused features can be stripped out by the compiler and the engine can be
//! tailored to the needs of the application.
const std = @import("std");
const builtin = @import("builtin");
pub const glfw = @import("zglfw");
pub const stbi = @import("zstbi");

pub const zopengl = @import("zopengl");
pub const gl = zopengl.bindings;
pub const zmath = @import("zmath");
pub const zaudio = @import("zaudio");
// pub const zgui = @import("zgui");
pub const ziglua = @import("ziglua");
pub const flecs = @import("zflecs");
pub const xml = @import("xml");
pub const stb_tt = @import("stb_truetype");

pub const common = @import("./common.zig");
pub const comp = @import("./comp.zig");
pub const utils = @import("./utils.zig");
pub const shaders = @import("./renderer/shaders.zig");
pub const textures = @import("./renderer/textures.zig");
pub const input = @import("./input.zig");
pub const events = @import("./events.zig");
pub const resources = @import("./resources.zig");
pub const renderer = @import("./renderer.zig");
pub const sprites = @import("./renderer/sprites.zig");
pub const pixel_buffer = @import("./renderer/pixel_buffer.zig");
pub const audio = @import("./audio.zig");
pub const sequencer = @import("./sequencer.zig");
pub const system = @import("./system.zig");
pub const tile = @import("./tile.zig");
pub const gamestate = @import("./gamestate.zig");
pub const scripting = @import("./scripting.zig");
pub const console2 = @import("./console2.zig");
pub const imgui = @import("./imgui.zig");
pub const collision = @import("./collision.zig");
pub const a_star = @import("./a_star.zig");
pub const assets = @import("./assets.zig");

pub const Texture = textures.Texture;
pub const TextureImage = textures.TextureImage;

const ResourceManager = resources.ResourceManager;

pub const Vec2I = common.Vec2I;
pub const RectI = common.RectI;
pub const RectF = common.RectF;
pub const Color = common.Color;
pub const Color8 = common.Color8;

/// Compile-time options for configuring the Pixzig Engine.  These options
/// allow enabling or disabling features of the engine at compile time, so
/// that unused code can be stripped out by the compiler. For example, if
/// audio is not needed, setting `audioOpts.enabled` to false will prevent
/// the audio engine handling code blocks in the engine from being included
/// in the final binary.
pub const PixzigEngineOptions = struct {
    defaultIcon: bool = true,
    gameScale: f32 = 1.0,
    rendererOpts: renderer.RendererOptions = .{},
    audioOpts: audio.AudioOptions = .{},
};

/// Runtime initialization options for the Pixzig Engine.  These options are
/// provided when initializing the engine and can be used to configure things
/// like fullscreen mode, window size, etc.  These options are separate from
/// the compile-time `PixzigEngineOptions` since they may need to be
/// determined at runtime (e.g. based on user input or platform capabilities)
/// rather than at compile time.
pub const PixzigEngineInitOptions = struct {
    fullscreen: bool = false,
    windowSize: Vec2I = .{ .x = 800, .y = 600 },
    renderInitOpts: renderer.RendererInitOpts = .{},
};

pub const web = if (builtin.os.tag == .emscripten) @import("./web.zig") else {};

// Globals used by AppRunner main loop in emscripten for web builds.
var g_EmscriptenRunnerRef: ?*anyopaque = null;
var g_EmscriptenAppRef: ?*anyopaque = null;

/// The main application looping handling structure.  This is the preferred way of setting up
/// and using Pixzig.  You provide the application data structure and engine initialization
/// options, and the PixzigAppRunner will handle the rest, including setting up the main loop and
/// cleaning up resources on exit.
///
/// The application data structure should contain the game state and implement the update and
/// render functions that will be called each frame.  Those functions should have the signatures:
///
/// ```zig
///     fn update(self: *AppData, eng: *PixzigEngine, deltaTimeMs: f64) bool
///     fn render(self: *AppData, eng: *PixzigEngine) void
/// ```
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

/// The core Pixzig Engine structure.  It provides rendering, audio, input and resource management
/// components.  The `engOpts` allow configuring the engine at comptime so that unused features can
/// be stripped out by the compiler. For example, if audio is not needed, setting `audioOpts.enabled`
/// to false will prevent the audio engine and related code from being included in the final binary.
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
        audio: audio.AudioEngine = undefined,

        const Self = @This();
        pub const Renderer = renderer.Renderer(engOpts.rendererOpts);

        /// Initializes the engine and its components.  In particular it creates the application
        /// window and rendering context, loads the OpenGL profile, and sets up the default
        /// projection matrix. The engine will be configured based on the provided `engInitOpts`
        /// and `engOpts` parameters.
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

            // ----------------------------------------------------------------
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

            // ----------------------------------------------------------------
            // Use framebuffer size (physical pixels) rather than getContentScale(),
            // because getContentScale() can disagree with the actual framebuffer
            // dimensions on Wayland with fractional scaling, causing a viewport gap.
            const fb_size = window.getFramebufferSize();
            const fb_w: f32 = @floatFromInt(fb_size[0]);
            const fb_h: f32 = @floatFromInt(fb_size[1]);
            const win_w: f32 = @floatFromInt(options.windowSize.x);
            const win_h: f32 = @floatFromInt(options.windowSize.y);
            const scaleFactor = @max(fb_w / win_w, fb_h / win_h);

            // Ensure the GL viewport covers the entire framebuffer.
            // Without an explicit call the default may be set to the logical
            // window size on Wayland, leaving a blank strip at the top.
            gl.viewport(0, 0, @intCast(fb_size[0]), @intCast(fb_size[1]));

            // Create a default 2D orthogrpaphic projection matrix fitting the window.
            // Also allow scaling the game content with engOpts.gameScale.
            const projMat = zmath.mul(zmath.scaling(engOpts.gameScale, engOpts.gameScale, 1.0), zmath.orthographicOffCenterLhGl(
                0,
                fb_w,
                0,
                fb_h,
                -0.1,
                1000,
            ));

            // ----------------------------------------------------------------
            std.log.debug("Initializing STBI.", .{});
            stbi.init(allocator);

            // ----------------------------------------------------------------
            const eng = try allocator.create(Self);
            eng.* = .{
                .window = window,
                .options = options,
                .scaleFactor = scaleFactor,
                .allocator = allocator,
                .projMat = projMat,
                .resources = ResourceManager.init(allocator),
                .keyboard = input.Keyboard.init(),
            };

            // ----------------------------------------------------------------
            std.log.info("Initializing Renderer.", .{});
            eng.renderer = try Renderer.init(allocator, &eng.resources, options.renderInitOpts);
            if (engOpts.defaultIcon) {
                std.log.debug("Setting default window icon.", .{});
                var defaultIcon = std.io.Reader.fixed(assets.icon48x48);
                try eng.setIcon(&defaultIcon);
            }

            // ----------------------------------------------------------------
            if (engOpts.audioOpts.enabled) {
                std.log.info("Initializing Audio Engine.", .{});
                eng.audio = try audio.AudioEngine.init(allocator);
            }

            std.log.info("Pixzig Engine Initialized.", .{});

            return eng;
        }

        /// Frees engine resources and deinitializes subsystems.  This includes destroying the
        /// application window.
        pub fn deinit(self: *Self) void {
            self.resources.deinit();
            stbi.deinit();

            self.window.destroy();
            glfw.terminate();

            if (engOpts.audioOpts.enabled) {
                self.audio.deinit();
            }

            self.allocator.destroy(self);
        }

        /// Sets the application window icon. The provided `icon_data` should be a reader for
        /// an image file in a format supported by STBI (e.g. PNG). The image will be loaded
        /// and set as the window icon. This function is a no-op on web builds since setting
        /// the favicon is outside the scope of the engine.
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
