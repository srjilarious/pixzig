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
pub const console = @import("./console.zig");
pub const console2 = @import("./console2.zig");
pub const imgui = @import("./imgui.zig");
pub const collision = @import("./collision.zig");
pub const a_star = @import("./a_star.zig");
pub const assets = @import("./assets.zig");
pub const AssetManifest = assets.AssetManifest;
pub const AssetKind = assets.AssetKind;
pub const file_watcher = @import("./file_watcher.zig");
pub const FileWatcher = file_watcher.FileWatcher;
pub const GlTestContext = @import("./test_context.zig").GlTestContext;

pub const windowing = @import("./window.zig");
pub const WindowState = windowing.WindowState;
pub const Viewport = windowing.Viewport;
pub const ScalePolicy = windowing.ScalePolicy;

pub const InputOptions = input.InputOptions;

pub const camera = @import("./camera.zig");
pub const Camera2D = camera.Camera2D;

pub const Texture = textures.Texture;
pub const TextureImage = textures.TextureImage;

pub const TextureHandle = resources.TextureHandle;
pub const ShaderHandle = resources.ShaderHandle;
pub const FontAtlasHandle = resources.FontAtlasHandle;
pub const TileMapHandle = resources.TileMapHandle;
pub const ManagedTexture = resources.ManagedTexture;
pub const ManagedShader = resources.ManagedShader;
pub const ManagedFont = resources.ManagedFont;
pub const ManagedTileMap = resources.ManagedTileMap;

const ResourceManager = resources.ResourceManager;

pub const Vec2I = common.Vec2I;
pub const Vec2F = common.Vec2F;
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
    /// Whether the default pixzig icon should be set, can be changed with
    /// PixzigEngine.setIcon
    defaultIcon: bool = true,

    /// Whether vsync should be enabled on init, defaults true.
    vsyncEnabled: bool = true,

    // How much to scale the rendered contents by, defaults to 1.0.
    gameScale: f32 = 1.0,

    /// The update time frequency, defaults to 120 Hz.
    updateStepHz: f64 = 120.0,

    /// Render options
    rendererOpts: renderer.RendererOptions = .{},

    /// Audio options.
    audioOpts: audio.AudioOptions = .{},

    /// Input options.
    inputOpts: input.InputOptions = .{},
};

/// Runtime initialization options for the Pixzig Engine.  These options are
/// provided when initializing the engine and can be used to configure things
/// like fullscreen mode, window size, etc.  These options are separate from
/// the compile-time `PixzigEngineOptions` since they may need to be
/// determined at runtime (e.g. based on user input or platform capabilities)
/// rather than at compile time.
pub const PixzigEngineInitOptions = struct {
    fullscreen: bool = false,
    windowSize: Vec2I = .{ .x = 800, .y = 480 },
    resizable: bool = true,
    /// Logical game resolution. When null, logical size tracks the framebuffer
    /// and projMat preserves the existing gameScale-based behavior.
    logicalSize: ?Vec2I = null,
    scalePolicy: windowing.ScalePolicy = .fit,
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

        engine: *Engine,
        alloc: std.mem.Allocator,
        lag: f64 = 0,
        currTime: f64 = 0,

        const UpdateStepMs = 1000.0 / engOpts.updateStepHz;
        const Self = @This();

        pub fn init(
            title: [:0]const u8,
            alloc: std.mem.Allocator,
            engInitOpts: PixzigEngineInitOptions,
        ) !*Self {
            var appRunner = try alloc.create(Self);
            appRunner.engine = try Engine.init(title, alloc, engInitOpts);
            appRunner.alloc = alloc;
            appRunner.currTime = glfw.getTime() * 1000.0;
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
            self.engine.refreshWindowState();

            while (self.lag > UpdateStepMs) {
                self.lag -= UpdateStepMs;

                self.engine.inputs.update(
                    self.engine.window,
                    self.engine.window_state.scale_factor,
                    &self.engine.viewport,
                );
                self.engine.resources.checkHotReload();
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

/// GLFW framebuffer-size callback. Sets a dirty flag on the WindowState so
/// refreshWindowState() can rebuild the viewport on the main thread.
fn framebufferSizeCallback(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    if (window.getUserPointer(windowing.WindowState)) |ws| {
        ws.framebuffer_size = .{ .x = @intCast(width), .y = @intCast(height) };
        ws.resized = true;
    }
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
        window_state: windowing.WindowState,
        viewport: windowing.Viewport,
        resources: ResourceManager,
        inputs: Inputs,
        renderer: Renderer = undefined,
        audio: audio.AudioEngine = undefined,

        const Self = @This();
        pub const Renderer = renderer.Renderer(engOpts.rendererOpts);
        pub const Inputs = input.InputManager;

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
            glfw.windowHint(.resizable, options.resizable);

            const monitor = blk: {
                if (options.fullscreen) {
                    break :blk glfw.Monitor.getPrimary();
                } else {
                    break :blk null;
                }
            };
            const window = try glfw.createWindow(options.windowSize.x, options.windowSize.y, title, monitor, null);
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
            var ws = windowing.WindowState.init(window);
            const logical_size = options.logicalSize orelse ws.framebuffer_size;

            // For integer_fit and integer_dpi_fit, snap the window size once at
            // startup so the framebuffer is an exact integer multiple of logical_size,
            // eliminating the black border that arises from fractional DPI remainders.
            if (options.logicalSize != null) {
                switch (options.scalePolicy) {
                    .integer_fit => {
                        const fb_w: f32 = @floatFromInt(ws.framebuffer_size.x);
                        const fb_h: f32 = @floatFromInt(ws.framebuffer_size.y);
                        const log_w: f32 = @floatFromInt(logical_size.x);
                        const log_h: f32 = @floatFromInt(logical_size.y);
                        const sx: i32 = @intFromFloat(fb_w / log_w);
                        const sy: i32 = @intFromFloat(fb_h / log_h);
                        const s: f32 = @floatFromInt(@max(1, @min(sx, sy)));
                        const new_w: i32 = @intFromFloat(@round(log_w * s / ws.content_scale.x));
                        const new_h: i32 = @intFromFloat(@round(log_h * s / ws.content_scale.y));
                        window.setSize(new_w, new_h);
                        ws.refresh(window);
                    },
                    else => {},
                }
            }

            const fb_w: f32 = @floatFromInt(ws.framebuffer_size.x);
            const fb_h: f32 = @floatFromInt(ws.framebuffer_size.y);
            const scaleFactor = @max(ws.scale_factor.x, ws.scale_factor.y);

            const vp = windowing.Viewport.init(logical_size, ws.framebuffer_size, options.scalePolicy);

            // Apply GL viewport and build the initial projection matrix.
            vp.apply();

            // projMat: compatibility alias.
            // When logicalSize is null, match the old gameScale-based formula so
            // existing examples that use eng.projMat continue to work unchanged.
            // When logicalSize is set, projMat mirrors viewport.projection().
            const projMat = if (options.logicalSize == null)
                zmath.mul(
                    zmath.scaling(engOpts.gameScale, engOpts.gameScale, 1.0),
                    zmath.orthographicOffCenterLhGl(0, fb_w, 0, fb_h, -0.1, 1000),
                )
            else
                vp.projection();

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
                .window_state = ws,
                .viewport = vp,
                .resources = ResourceManager.init(allocator),
                .inputs = input.InputManager.init(engOpts.inputOpts),
            };

            // Store a pointer to window_state in the GLFW user pointer so the
            // framebuffer-size callback can record resize events without
            // rebuilding GL state from within the callback.
            eng.window.setUserPointer(@ptrCast(&eng.window_state));
            _ = eng.window.setFramebufferSizeCallback(framebufferSizeCallback);

            if (eng.inputs.mouse_enabled) {
                input.mouse.setScrollTarget(&eng.inputs.mouse);
                _ = eng.window.setScrollCallback(input.mouse.scrollCallback);
            }

            // ----------------------------------------------------------------
            std.log.info("Initializing Renderer.", .{});
            eng.renderer = try Renderer.init(allocator, &eng.resources, options.renderInitOpts);
            if (engOpts.defaultIcon) {
                std.log.debug("Setting default window icon.", .{});
                var defaultIcon = std.Io.Reader.fixed(assets.icon48x48);
                try eng.setIcon(&defaultIcon);
            }

            if (engOpts.vsyncEnabled) {
                eng.enableVSync(engOpts.vsyncEnabled);
            }

            // ----------------------------------------------------------------
            if (engOpts.audioOpts.enabled) {
                std.log.info("Initializing Audio Engine.", .{});
                eng.audio = try audio.AudioEngine.init(allocator, engOpts.audioOpts);
            }

            std.log.info("Pixzig Engine Initialized.", .{});

            return eng;
        }

        /// Frees engine resources and deinitializes subsystems.  This includes destroying the
        /// application window.
        pub fn deinit(self: *Self) void {
            if (engOpts.audioOpts.enabled) {
                self.audio.deinit();
            }

            self.renderer.deinit();
            self.resources.deinit();
            stbi.deinit();

            self.window.destroy();
            glfw.terminate();

            self.allocator.destroy(self);
        }

        /// Sets the application window icon. The provided `icon_data` should be a reader for
        /// an image file in a format supported by STBI (e.g. PNG). The image will be loaded
        /// and set as the window icon. This function is a no-op on web builds since setting
        /// the favicon is outside the scope of the engine.
        pub fn setIcon(self: *Self, icon_data: *std.Io.Reader) !void {
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

        /// Sets whether vsync is enabled or not on the graphics context.
        pub fn enableVSync(self: *Self, enabled: bool) void {
            _ = self;
            if (enabled) {
                glfw.swapInterval(1);
            } else {
                glfw.swapInterval(0);
            }
        }

        /// Called each frame (after glfw.pollEvents) to pick up resize events
        /// recorded by the framebuffer-size callback. Rebuilds the viewport and
        /// updates projMat when the framebuffer has changed.
        pub fn refreshWindowState(self: *Self) void {
            if (!self.window_state.resized) return;
            self.window_state.resized = false;
            self.window_state.refresh(self.window);

            if (self.options.logicalSize == null) {
                self.viewport.logical_size = self.window_state.framebuffer_size;
            }
            const fbsz = self.window_state.framebuffer_size;
            self.viewport.updateFramebufferSize(fbsz);

            // Make sure any out-of-viewport portions are cleared black for letterboxing.
            // Clear whole framebuffer first. This creates the bars.
            //gl.scissor(0, 0, fbsz.x, fbsz.y);

            gl.disable(gl.SCISSOR_TEST);
            self.renderer.clear(0, 0, 0, 1);

            self.viewport.apply();

            self.scaleFactor = @max(self.window_state.scale_factor.x, self.window_state.scale_factor.y);

            if (self.options.logicalSize == null) {
                const fw: f32 = @floatFromInt(self.window_state.framebuffer_size.x);
                const fh: f32 = @floatFromInt(self.window_state.framebuffer_size.y);
                self.projMat = zmath.mul(
                    zmath.scaling(engOpts.gameScale, engOpts.gameScale, 1.0),
                    zmath.orthographicOffCenterLhGl(0, fw, 0, fh, -0.1, 1000),
                );
            } else {
                self.projMat = self.viewport.projection();
            }
        }

        /// Projection matrix for the logical game coordinate space.
        /// Maps (0,0)..(logicalW, logicalH) with y=0 at the top-left.
        /// Use this for all game rendering. Equivalent to `viewport.projection()`.
        pub fn projection(self: *const Self) zmath.Mat {
            return self.viewport.projection();
        }

        /// Projection matrix for the full framebuffer in actual pixels.
        /// Maps (0,0)..(framebufferW, framebufferH) with y=0 at the top-left.
        /// Use this for UI or debug overlays that should be positioned in screen
        /// pixels rather than logical game coordinates.
        pub fn screenProjection(self: *const Self) zmath.Mat {
            const fw: f32 = @floatFromInt(self.window_state.framebuffer_size.x);
            const fh: f32 = @floatFromInt(self.window_state.framebuffer_size.y);
            return zmath.orthographicOffCenterLhGl(0, fw, 0, fh, -0.1, 1000);
        }

        /// Deprecated: use `projection()` instead.
        pub fn uiMatrix(self: *const Self) zmath.Mat {
            return self.projection();
        }

        /// Converts a GLFW window-coordinate position to framebuffer pixels,
        /// accounting for DPI scale.
        pub fn windowToFramebuffer(self: *const Self, pos: Vec2F) Vec2F {
            return .{
                .x = pos.x * self.window_state.scale_factor.x,
                .y = pos.y * self.window_state.scale_factor.y,
            };
        }

        /// Converts a GLFW window-coordinate position to logical game coordinates.
        /// Returns null when the pointer is over a letterbox or pillarbox area.
        pub fn windowToLogical(self: *const Self, pos: Vec2F) ?Vec2F {
            return self.viewport.framebufferToLogical(self.windowToFramebuffer(pos));
        }
    };
}
