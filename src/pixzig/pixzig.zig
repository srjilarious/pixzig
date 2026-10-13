//! The top-level Pixzig module.  This is the main entry point for users of
//! the engine, and it re-exports all the main components of the engine, such
//! as the renderer, audio engine, resource manager, etc.  It also defines the
//! main application runner structure `AppRunner` and the core engine structure
//! `Engine`.  The `AppRunner` is the recommended way to set up and run a Pixzig
//! application, as it handles the main loop and resource cleanup for both
//! desktop and web builds properly.  The `Engine` provides access to the
//! various subsystems of the engine and is passed to the application update
//! and render functions each frame.
//!
//! The `EngineOptions` and `EngineInitOptions` structures allow configuring
//! the engine at compile time and runtime, respectively, so that unused engine
//! *code paths* (e.g. the audio update loop, gamepad polling) can be stripped
//! out by the compiler and the engine can be tailored to the needs of the
//! application. This does not change which native dependencies get linked:
//! `build.zig` always links SDL3, OpenGL, flecs, zaudio/miniaudio, Lua, XML,
//! and STB TrueType into every engine build regardless of `EngineOptions`.
const std = @import("std");
const builtin = @import("builtin");
pub const stbi = @import("zstbi");
const sdl = @import("sdl3");

pub const zopengl = @import("zopengl");
pub const gl = zopengl.bindings;
pub const zmath = @import("zmath");
pub const zaudio = @import("zaudio");
pub const ziglua = @import("ziglua");
pub const flecs = @import("zflecs");
pub const xml = @import("xml");
pub const stb_tt = @import("stb_truetype");

pub const common = @import("./common.zig");
pub const utils = @import("./utils.zig");
pub const random = @import("./random.zig");
pub const Rng = random.Rng;
pub const easing = @import("./easing.zig");
pub const Ease = easing.Ease;
pub const platform = @import("./platform.zig");
/// An engine-level OS event, handed to the app's optional `onEvent`. See
/// `platform/event.zig`.
pub const Event = platform.event.Event;
pub const shaders = @import("./renderer/shaders.zig");
pub const textures = @import("./renderer/textures.zig");
pub const input = @import("./input.zig");
pub const events = @import("./events.zig");
pub const resources = @import("./resources.zig");
pub const renderer = @import("./renderer.zig");
pub const sprites = @import("./renderer/sprites.zig");
pub const pixel_buffer = @import("./renderer/pixel_buffer.zig");
pub const quad3d = @import("./renderer/quad3d_batch.zig");
pub const audio = @import("./audio.zig");
pub const sequencer = @import("./sequencer.zig");
pub const tile = @import("./tile.zig");
pub const gamestate = @import("./gamestate.zig");
pub const scripting = @import("./scripting.zig");
pub const console = @import("./console.zig");
pub const imgui = @import("./imgui.zig");
pub const collision = @import("./collision.zig");
pub const a_star = @import("./a_star.zig");
pub const assets = @import("./assets.zig");
pub const screenshot = @import("./screenshot.zig");
pub const AssetManifest = assets.AssetManifest;
pub const AssetKind = assets.AssetKind;
pub const ManifestSource = assets.ManifestSource;
pub const file_watcher = @import("./file_watcher.zig");
pub const FileWatcher = file_watcher.FileWatcher;

/// Build and test plumbing, not game API: the root wrapper `buildGame`
/// generates uses `system.panic`/`system.std_options` (a game with
/// `wrap_root = false` re-exports them itself), and the unit tests use
/// `GlTestContext` for a hidden GL window.
pub const internal = struct {
    pub const system = @import("./system.zig");
    pub const comp = @import("./comp.zig");
    pub const GlTestContext = @import("./test_context.zig").GlTestContext;
};

pub const windowing = @import("./window.zig");
pub const WindowState = windowing.WindowState;
pub const Viewport = windowing.Viewport;
pub const ScalePolicy = windowing.ScalePolicy;

pub const InputOptions = input.InputOptions;
pub const Key = input.Key;
pub const MouseButton = input.MouseButton;
pub const GamepadButton = input.GamepadButton;
pub const GamepadAxis = input.GamepadAxis;
pub const Window = platform.Window;

pub const camera = @import("./camera.zig");
pub const Camera2D = camera.Camera2D;

pub const camera3d = @import("./camera3d.zig");
pub const Camera3D = camera3d.Camera3D;

// Sprites and the frame-animation types that go with them. `pixzig.sprites`
// still holds the full module; these are the nouns a game names directly.
pub const Sprite = sprites.Sprite;
pub const Flip = sprites.Flip;
pub const Frame = sprites.Frame;
pub const FrameSequence = sprites.FrameSequence;
pub const FrameSequenceManager = sprites.FrameSequenceManager;
pub const AnimPlayMode = sprites.AnimPlayMode;
pub const Actor = sprites.Actor;
pub const ActorState = sprites.ActorState;

pub const Texture = textures.Texture;
pub const TextureImage = textures.TextureImage;

pub const ResourceManager = resources.ResourceManager;
pub const TextureHandle = resources.TextureHandle;
pub const ShaderHandle = resources.ShaderHandle;
pub const FontAtlasHandle = resources.FontAtlasHandle;
pub const TileMapHandle = resources.TileMapHandle;
pub const SoundHandle = resources.SoundHandle;
pub const MusicHandle = resources.MusicHandle;

// `Renderer` itself is reached as `AppRunner.Engine.Renderer` (it is
// generic over `RendererOptions`), so only its plain option/value types are
// re-exported here.
pub const RendererOptions = renderer.RendererOptions;
pub const RendererInitOpts = renderer.RendererInitOpts;
pub const Projection = renderer.Projection;
pub const FontSource = renderer.FontSource;
pub const FontAtlas = renderer.FontAtlas;

pub const TileMap = tile.TileMap;
pub const TileLayer = tile.TileLayer;
pub const TileMapRenderer = tile.TileMapRenderer;

pub const ActionMap = input.ActionMap;
pub const ActionOptions = input.ActionOptions;
pub const ScriptEngine = scripting.ScriptEngine;
pub const AudioOptions = audio.AudioOptions;
pub const Voice = audio.Voice;

pub const Vec2I = common.Vec2I;
pub const Vec2F = common.Vec2F;
pub const RectI = common.RectI;
pub const RectF = common.RectF;
pub const Color = common.Color;
pub const Color8 = common.Color8;

/// Compile-time options for configuring the Pixzig Engine.  These options
/// allow enabling or disabling engine code paths at compile time. For
/// example, if audio is not needed, setting `audioOpts.enabled` to false will
/// prevent the audio engine handling code blocks in the engine from being
/// included in the final binary. This only strips *engine* code; the native
/// dependencies themselves (SDL3, OpenGL, flecs, zaudio/miniaudio, Lua, XML,
/// STB TrueType) are always linked in by `build.zig`, so disabling a feature
/// here does not shrink the set of linked libraries.
pub const EngineOptions = struct {
    /// Whether the default pixzig icon should be set, can be changed with
    /// Engine.setIcon
    defaultIcon: bool = true,

    /// The update time frequency, defaults to 120 Hz.
    updateStepHz: f64 = 120.0,

    /// The most time the fixed-step loop will try to catch up on in a single
    /// frame, in milliseconds. Any backlog beyond this (a long hitch, a
    /// debugger pause, a slow asset load) is dropped, so the game briefly
    /// slows down instead of running hundreds of updates back to back.
    maxLagMs: f64 = 250.0,

    /// Render options
    rendererOpts: renderer.RendererOptions = .{},

    /// Audio options.
    audioOpts: audio.AudioOptions = .{},

    /// Input options.
    inputOpts: input.InputOptions = .{},

    /// Create an action map the engine owns, reached as `eng.actions`, for
    /// the given `Action` and `Axes` enums. `AppRunner` updates it each tick
    /// before `App.update`, and suppresses it while the engine console is
    /// open. Bind it in `App.init`.
    actionOpts: ?input.ActionOptions = null,

    /// Optional manifest module to load automatically during engine init.
    /// Set to `@import("manifest_options")` to wire in the build-generated
    /// manifest. The manifest is loaded before the renderer so that any fonts
    /// in the boot group are available for `renderInitOpts.font = .{ .id = ... }`.
    /// The engine owns the manifest and deinits it on shutdown.
    manifestOpts: ?type = null,

    /// Create a Lua `ScriptEngine` the engine owns, reached as `eng.scripts`.
    /// It is created after the renderer and closed before it on shutdown.
    scripting: bool = false,

    /// Create a script console the engine owns, reached as `eng.console`
    /// (draw it with `eng.console.draw(&ui)`). Requires `scripting`. A null
    /// `displaySize` sizes it to the logical resolution.
    console: ?console.ConsoleOpts = null,

    /// Compile in `AppRunner`'s screenshot hook, which captures a frame to
    /// a PNG and exits when `PIXZIG_SCREENSHOT` is set (see
    /// `screenshot.zig`). Off by default so a shipped game can't be driven
    /// by environment variables; the examples turn it on for the doc
    /// screenshots. Ignored on the web.
    screenshotHook: bool = false,
};

/// Runtime initialization options for the Pixzig Engine.  These options are
/// provided when initializing the engine and can be used to configure things
/// like fullscreen mode, window size, etc.  These options are separate from
/// the compile-time `EngineOptions` since they may need to be
/// determined at runtime (e.g. based on user input or platform capabilities)
/// rather than at compile time.
pub const EngineInitOptions = struct {
    fullscreen: bool = false,
    windowSize: Vec2I = .{ .x = 800, .y = 480 },
    resizable: bool = true,
    /// Smallest size the user can shrink the window to, in screen
    /// coordinates. Null leaves it unconstrained, so a 320x180 game can be
    /// sized down to 1x.
    minWindowSize: ?Vec2I = null,
    /// Logical game resolution. When null, logical size tracks the framebuffer,
    /// so `Engine.projection()` maps one unit to one framebuffer pixel.
    logicalSize: ?Vec2I = null,
    scalePolicy: windowing.ScalePolicy = .fit,
    /// Whether vsync is enabled on init. Change it later with
    /// `Engine.enableVSync`, e.g. from a settings menu.
    vsync: bool = true,
    /// Seed for `Engine.rng`. Null seeds it from the clock, so each run
    /// differs; set it for reproducible runs (replays, tests, lockstep).
    rngSeed: ?u64 = null,
    renderInitOpts: renderer.RendererInitOpts = .{},
};

pub const web = if (builtin.os.tag == .emscripten) @import("./web.zig") else {};

/// A seed for `Engine.rng` when `EngineInitOptions.rngSeed` is null: the
/// wall clock in nanoseconds, so each run differs.
fn clockSeed() u64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ns = std.Io.Timestamp.now(io, .real).toNanoseconds();
    return @truncate(@as(u128, @bitCast(@as(i128, ns))));
}

// Globals used by AppRunner main loop in emscripten for web builds.
var g_EmscriptenRunnerRef: ?*anyopaque = null;
var g_EmscriptenAppRef: ?*anyopaque = null;

/// The main application looping handling structure. This is the preferred way
/// of setting up and using Pixzig. You provide the application data structure
/// and engine initialization options, and the `AppRunner` handles window and
/// engine setup, the fixed-step main loop, and the desktop/web loop boundary.
/// Call `deinit` from your `main` after `run` returns to release engine-owned
/// resources; your app remains responsible for its own `deinit`.
///
/// The application data structure should contain the game state and implement the update and
/// render functions that will be called each frame.  Those functions should have the signatures:
///
/// ```zig
///     fn update(self: *AppData, eng: *Engine, deltaTimeMs: f64) bool
///     fn render(self: *AppData, eng: *Engine) void
/// ```
///
/// An app may also declare an `onEvent` to hear about window, drag-and-drop,
/// gamepad hot-plug and lifecycle events. It's called during the event
/// pump, before the frame's updates:
///
/// ```zig
///     fn onEvent(self: *AppData, eng: *Engine, event: pixzig.Event) void
/// ```
pub fn AppRunner(comptime AppData: type, comptime engOpts: EngineOptions) type {
    // Bound outside the struct below so the struct's own `Engine` decl can
    // carry the engine type without shadowing the `Engine` function itself.
    const EngineType = Engine(engOpts);
    const AppStruct = struct {
        pub const Engine = EngineType;

        engine: *EngineType,
        alloc: std.mem.Allocator,
        lag: f64 = 0,
        currTime: f64 = 0,
        /// The screenshot hook, when compiled in and `PIXZIG_SCREENSHOT` is set.
        shot: if (HasScreenshotHook) ?screenshot.ScreenshotHook else void,
        /// Ticks run under the screenshot hook, which is its game clock.
        shotTicks: u64 = 0,

        const UpdateStepMs = 1000.0 / engOpts.updateStepHz;
        const HasOnEvent = @hasDecl(AppData, "onEvent");
        const HasScreenshotHook = engOpts.screenshotHook and builtin.target.os.tag != .emscripten;
        const Self = @This();

        pub fn init(
            title: [:0]const u8,
            alloc: std.mem.Allocator,
            engInitOpts: EngineInitOptions,
        ) !*Self {
            var appRunner = try alloc.create(Self);
            errdefer alloc.destroy(appRunner);

            var initOpts = engInitOpts;
            if (HasScreenshotHook) {
                appRunner.shot = try screenshot.ScreenshotHook.fromEnv(alloc, UpdateStepMs);
                appRunner.shotTicks = 0;
                if (appRunner.shot) |shot| {
                    if (shot.windowSize) |size| initOpts.windowSize = size;
                    initOpts.rngSeed = shot.seed;
                    // Frames are paced by ticks, not the display, so there
                    // is nothing to wait for.
                    initOpts.vsync = false;
                }
            } else {
                appRunner.shot = {};
            }
            errdefer if (HasScreenshotHook) {
                if (appRunner.shot) |*shot| shot.deinit();
            };

            appRunner.engine = try EngineType.init(title, alloc, initOpts);
            appRunner.alloc = alloc;
            appRunner.currTime = platform.timeMs();
            return appRunner;
        }

        pub fn deinit(self: *Self) void {
            if (HasScreenshotHook) {
                if (self.shot) |*shot| shot.deinit();
            }
            self.engine.deinit();
            self.alloc.destroy(self);
        }

        /// Restarts the fixed-step clock and drops any accumulated lag. Call
        /// this after a long pause outside the loop that shouldn't be caught up.
        pub fn resetClock(self: *Self) void {
            self.currTime = platform.timeMs();
            self.lag = 0;
        }

        /// Drains the OS event queue, handing engine-level events to the
        /// app's `onEvent` when it has one.
        fn pumpEvents(self: *Self, app: *AppData) void {
            if (HasOnEvent) {
                self.engine.pollEventsWith(app);
            } else {
                self.engine.pollEvents();
            }
            self.engine.refreshWindowState();
        }

        /// Runs one fixed update step. Returns false when the app asks to quit.
        fn updateTick(self: *Self, app: *AppData) bool {
            self.engine.inputs.update(
                self.engine.windowState.scaleFactor,
                &self.engine.viewport,
            );
            self.engine.updateActions(UpdateStepMs);
            self.engine.resources.checkHotReload();
            const keepRunning = app.update(self.engine, UpdateStepMs);
            // Roll this tick's input into the previous-tick buffers only
            // after the app has read it, so a press that lands between
            // two ticks is still an edge for exactly one of them.
            self.engine.inputs.finishTick();
            return keepRunning;
        }

        pub fn gameLoopCore(self: *Self, app: *AppData) bool {
            if (HasScreenshotHook) {
                if (self.shot) |*shot| return self.screenshotLoopCore(app, shot);
            }

            const newCurrTime = platform.timeMs();
            const delta = newCurrTime - self.currTime;
            self.lag = @min(self.lag + delta, engOpts.maxLagMs);
            self.currTime = newCurrTime;

            self.pumpEvents(app);

            while (self.lag > UpdateStepMs) {
                self.lag -= UpdateStepMs;
                if (!self.updateTick(app)) return false;
            }
            self.engine.updateAudio();

            app.render(self.engine);
            self.engine.window.swapBuffers();
            return true;
        }

        /// The loop under the screenshot hook: exactly one tick per frame,
        /// with scripted input fed in first, until the capture time is
        /// reached. The captured frame is read back before the swap and the
        /// loop then stops as if the app had quit.
        fn screenshotLoopCore(self: *Self, app: *AppData, shot: *screenshot.ScreenshotHook) bool {
            self.pumpEvents(app);

            const tickStartMs = @as(f64, @floatFromInt(self.shotTicks)) * UpdateStepMs;
            shot.applyInput(&self.engine.inputs, tickStartMs);
            if (!self.updateTick(app)) return false;
            self.shotTicks += 1;
            self.engine.updateAudio();

            app.render(self.engine);
            if (shot.due(tickStartMs + UpdateStepMs)) {
                if (self.engine.captureScreenshot(self.alloc, shot.path)) {
                    std.log.info("Screenshot written to {s}", .{shot.path});
                } else |err| {
                    std.log.err("Screenshot to {s} failed: {}", .{ shot.path, err });
                }
                return false;
            }
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
            // Time spent between `init` and here (typically `App.init`
            // loading assets) is not game time, so start the clock fresh.
            self.resetClock();
            if (builtin.target.os.tag == .emscripten) {
                g_EmscriptenRunnerRef = @constCast(self);
                g_EmscriptenAppRef = @constCast(app);
                web.setMainLoop(mainLoop, null, false);
            } else {
                self.gameLoop(app);
            }
        }
    };

    return AppStruct;
}

/// The core Pixzig Engine structure.  It provides rendering, audio, input and resource management
/// components.  The `engOpts` allow configuring the engine at comptime so that unused features can
/// be stripped out by the compiler. For example, if audio is not needed, setting `audioOpts.enabled`
/// to false will prevent the audio engine and related code from being included in the final binary.
pub fn Engine(comptime engOpts: EngineOptions) type {
    return struct {
        window: *platform.Window,
        options: EngineInitOptions,
        allocator: std.mem.Allocator,
        windowState: windowing.WindowState,
        viewport: windowing.Viewport,
        resources: ResourceManager,
        inputs: Inputs,
        /// The engine's random source, seeded from
        /// `EngineInitOptions.rngSeed`. Draw gameplay randomness from here
        /// so a fixed seed reproduces a run.
        rng: random.Rng,
        renderer: Renderer = undefined,
        /// The audio engine. When `audioOpts.enabled` is false this is a
        /// `DisabledAudioEngine`, whose methods are compile errors naming the flag.
        audio: if (engOpts.audioOpts.enabled) audio.AudioEngine else audio.DisabledAudioEngine = undefined,
        /// Set while the engine has audio paused because the app went to
        /// the background, so coming back only resumes what it paused.
        audioPausedForBackground: bool = false,
        manifest: if (engOpts.manifestOpts != null) assets.AssetManifest else void,
        /// The engine's Lua state when `scripting` is set.
        scripts: if (engOpts.scripting) ScriptEngine else void,
        /// The engine's script console when `console` is set. Bound to `scripts`.
        console: if (engOpts.console != null) *console.Console else void,
        /// The engine's action map when `actionOpts` is set.
        actions: if (engOpts.actionOpts != null) *Actions else void,

        const Self = @This();

        comptime {
            if (engOpts.console != null and !engOpts.scripting) {
                @compileError("EngineOptions.console requires EngineOptions.scripting = true");
            }
        }
        pub const Renderer = renderer.Renderer(engOpts.rendererOpts);
        pub const Inputs = input.InputManager;
        /// The `ActionMap` type behind `eng.actions`, or void when
        /// `actionOpts` is null.
        pub const Actions = if (engOpts.actionOpts) |ao| input.ActionMap(ao.Action, ao.Axes) else void;

        /// Initializes the engine and its components.  In particular it creates the application
        /// window and rendering context, loads the OpenGL profile, and sets up the default
        /// projection matrix. The engine will be configured based on the provided `engInitOpts`
        /// and `engOpts` parameters.
        pub fn init(title: [:0]const u8, allocator: std.mem.Allocator, options: EngineInitOptions) !*Self {
            const gl_major, const gl_minor = try platform.initVideo();
            errdefer platform.quit();

            std.log.debug("SDL3 initialized.", .{});

            const window = try platform.Window.create(allocator, title, .{
                .size = options.windowSize,
                .resizable = options.resizable,
                .fullscreen = options.fullscreen,
                .minSize = options.minWindowSize,
                .textInput = engOpts.inputOpts.textInput,
            });
            errdefer window.destroy();

            // ----------------------------------------------------------------
            std.log.info("Loading OpenGL profile.", .{});
            if (builtin.target.os.tag == .emscripten) {
                try zopengl.loadEsProfile(platform.glProcAddress, @intCast(gl_major), @intCast(gl_minor));
                try zopengl.loadEsExtension(platform.glProcAddress, .OES_vertex_array_object);
            } else {
                try zopengl.loadCoreProfile(platform.glProcAddress, @intCast(gl_major), @intCast(gl_minor));
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
            const logicalSize = options.logicalSize orelse ws.framebufferSize;

            // For integer_fit and integer_dpi_fit, snap the window size once at
            // startup so the framebuffer is an exact integer multiple of logicalSize,
            // eliminating the black border that arises from fractional DPI remainders.
            if (options.logicalSize != null) {
                switch (options.scalePolicy) {
                    .integer_fit => {
                        const fb_w: f32 = @floatFromInt(ws.framebufferSize.x);
                        const fb_h: f32 = @floatFromInt(ws.framebufferSize.y);
                        const log_w: f32 = @floatFromInt(logicalSize.x);
                        const log_h: f32 = @floatFromInt(logicalSize.y);
                        const sx: i32 = @intFromFloat(fb_w / log_w);
                        const sy: i32 = @intFromFloat(fb_h / log_h);
                        const s: f32 = @floatFromInt(@max(1, @min(sx, sy)));
                        const new_w: i32 = @intFromFloat(@round(log_w * s / ws.contentScale.x));
                        const new_h: i32 = @intFromFloat(@round(log_h * s / ws.contentScale.y));
                        window.setSize(new_w, new_h);
                        ws.refresh(window);
                    },
                    else => {},
                }
            }

            const vp = windowing.Viewport.init(logicalSize, ws.framebufferSize, options.scalePolicy);

            // Apply the GL viewport; `projection()` derives its matrix from it.
            vp.apply();

            // ----------------------------------------------------------------
            std.log.debug("Initializing STBI.", .{});
            stbi.init(std.Io.Threaded.global_single_threaded.io(), allocator);
            errdefer stbi.deinit();

            // ----------------------------------------------------------------
            const eng = try allocator.create(Self);
            eng.* = .{
                .window = window,
                .options = options,
                .allocator = allocator,
                .windowState = ws,
                .viewport = vp,
                .resources = ResourceManager.init(allocator),
                .inputs = input.InputManager.init(engOpts.inputOpts),
                .rng = random.Rng.init(options.rngSeed orelse clockSeed()),
                .manifest = if (engOpts.manifestOpts != null) undefined else {},
                .scripts = if (engOpts.scripting) undefined else {},
                .console = if (engOpts.console != null) undefined else {},
                .actions = if (engOpts.actionOpts != null) undefined else {},
            };
            errdefer {
                eng.resources.deinit();
                allocator.destroy(eng);
            }

            if (engOpts.actionOpts != null) eng.actions = try Actions.init(allocator);
            errdefer if (engOpts.actionOpts != null) eng.actions.deinit();

            // ----------------------------------------------------------------
            // Before the manifest, so its sound and music assets can load.
            if (engOpts.audioOpts.enabled) {
                std.log.info("Initializing Audio Engine.", .{});
                eng.audio = try audio.AudioEngine.init(allocator, engOpts.audioOpts, &eng.resources);
            }
            errdefer if (engOpts.audioOpts.enabled) eng.audio.deinit();

            // ----------------------------------------------------------------
            if (engOpts.manifestOpts) |ManifestMod| {
                std.log.info("Loading asset manifest.", .{});
                eng.manifest = try assets.ManifestSource.fromOptions(ManifestMod).load(allocator, &eng.resources);
            }
            errdefer if (comptime engOpts.manifestOpts != null) eng.manifest.deinit();

            // ----------------------------------------------------------------
            std.log.info("Initializing Renderer.", .{});
            eng.renderer = try Renderer.init(allocator, &eng.resources, &eng.viewport, options.renderInitOpts);
            errdefer eng.renderer.deinit();
            if (engOpts.defaultIcon) {
                std.log.debug("Setting default window icon.", .{});
                var defaultIcon = std.Io.Reader.fixed(assets.icon48x48);
                try eng.setIcon(&defaultIcon);
            }

            eng.enableVSync(options.vsync);

            // ----------------------------------------------------------------
            if (engOpts.scripting) {
                std.log.info("Initializing Script Engine.", .{});
                eng.scripts = try ScriptEngine.init(allocator);
            }
            errdefer if (engOpts.scripting) eng.scripts.deinit();

            if (engOpts.console) |consoleOpts| {
                var opts = consoleOpts;
                if (opts.displaySize == null) opts.displaySize = eng.viewport.logicalSize.asVec2U();
                eng.console = try console.Console.init(allocator, &eng.scripts, opts);
            }
            errdefer if (engOpts.console != null) eng.console.deinit();

            if (engOpts.scripting and engOpts.audioOpts.enabled) {
                try eng.audio.bindToLua(&eng.scripts);
            }

            std.log.info("Pixzig Engine Initialized.", .{});

            return eng;
        }

        /// Frees engine resources and deinitializes subsystems.  This includes destroying the
        /// application window.
        pub fn deinit(self: *Self) void {
            // Also frees the sounds and music in `resources`, which point
            // into the audio engine.
            if (engOpts.audioOpts.enabled) {
                self.audio.deinit();
            }

            // The console holds a pointer to the script engine, so it goes first.
            if (engOpts.console != null) self.console.deinit();
            if (engOpts.scripting) self.scripts.deinit();

            self.renderer.deinit();
            if (comptime engOpts.manifestOpts != null) self.manifest.deinit();
            self.resources.deinit();
            stbi.deinit();

            if (engOpts.actionOpts != null) self.actions.deinit();
            self.inputs.deinit();
            self.window.destroy();
            platform.quit();

            self.allocator.destroy(self);
        }

        /// Advances `eng.actions` one tick from `eng.inputs`. `AppRunner`
        /// calls this after updating the inputs; call it yourself only when
        /// driving the engine without a runner. While the engine console is
        /// open every action reads as up, so typing doesn't trigger them.
        pub fn updateActions(self: *Self, deltaMs: f64) void {
            if (engOpts.actionOpts == null) return;
            if (engOpts.console != null and self.console.enabled) {
                self.actions.updateSuppressed();
            } else {
                self.actions.update(&self.inputs, deltaMs);
            }
        }

        /// Per-frame audio housekeeping (music hot reload, finished
        /// streams). `AppRunner` calls this once a frame; call it yourself
        /// only when driving the engine without a runner. A no-op with
        /// audio off.
        pub fn updateAudio(self: *Self) void {
            if (engOpts.audioOpts.enabled) self.audio.update();
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

                self.window.setIcon(&icon_image);
            }
        }

        /// Sets whether vsync is enabled or not on the graphics context.
        pub fn enableVSync(self: *Self, enabled: bool) void {
            _ = self;
            platform.setSwapInterval(if (enabled) 1 else 0);
        }

        /// Shows or hides the system mouse cursor. SDL3 applies this
        /// process-wide.
        pub fn showCursor(self: *Self, visible: bool) void {
            _ = self;
            platform.showCursor(visible);
        }

        /// Captures or releases the system mouse cursor for mouse-look.
        /// Capture uses SDL's window-relative mouse mode: the cursor is
        /// hidden and motion stays unbounded instead of clamping at the
        /// window edge.
        pub fn setCursorCapture(self: *Self, enabled: bool) !void {
            try self.window.setCursorCapture(enabled);
        }

        pub fn cursorCaptured(self: *const Self) bool {
            return self.window.cursorCaptured();
        }

        /// Drains the OS event queue, handling window-level events here and
        /// routing everything else to the input manager. Engine-level
        /// events are dropped; use `pollEventsWith` to receive them.
        pub fn pollEvents(self: *Self) void {
            self.pollEventsWith({});
        }

        /// `pollEvents`, plus each engine-level `Event` handed to
        /// `handler.onEvent(self, event)` as it is drained. `handler` is a
        /// pointer to anything with that method (the `AppRunner` passes
        /// the app), or `{}` for none.
        ///
        /// The engine's own handling of an event (closing, clearing input
        /// on focus loss, rebuilding the viewport on resize) is done before
        /// the handler sees it, so the handler can observe or undo it.
        pub fn pollEventsWith(self: *Self, handler: anytype) void {
            const HasHandler = @TypeOf(handler) != void;
            // SDL reports closing the last window twice, as a window close
            // and then a quit. Treat them as one request per pump, so an app
            // that cancels the first isn't closed by the second.
            var closeSeen = false;
            var event: sdl.SDL_Event = undefined;
            while (sdl.SDL_PollEvent(&event)) {
                switch (event.type) {
                    sdl.SDL_EVENT_QUIT,
                    sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
                    => {
                        if (closeSeen) continue;
                        closeSeen = true;
                        self.window.closeRequested = true;
                    },
                    sdl.SDL_EVENT_WINDOW_RESIZED,
                    sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
                    sdl.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
                    => self.windowState.resized = true,
                    // Event-driven key state latches, so anything held when
                    // the window loses focus would otherwise stay down.
                    sdl.SDL_EVENT_WINDOW_FOCUS_LOST => self.inputs.clear(),
                    // A backgrounded app shouldn't keep playing. Pausing on
                    // `will` gives the best chance of stopping before the
                    // OS suspends us; resuming waits for `did`, once the
                    // app is actually back.
                    sdl.SDL_EVENT_WILL_ENTER_BACKGROUND => {
                        if (engOpts.audioOpts.enabled and !self.audioPausedForBackground) {
                            self.audio.pauseAll();
                            self.audioPausedForBackground = true;
                        }
                    },
                    sdl.SDL_EVENT_DID_ENTER_FOREGROUND => {
                        if (engOpts.audioOpts.enabled and self.audioPausedForBackground) {
                            self.audio.resumeAll();
                            self.audioPausedForBackground = false;
                        }
                    },
                    else => self.inputs.handleEvent(event),
                }

                if (!HasHandler) continue;
                const engEvent = platform.event.fromSdl(&event) orelse continue;
                // Bring the window state and viewport up to date first, so
                // a handler that re-lays out its UI reads the new size.
                if (engEvent == .window_resized) self.refreshWindowState();
                handler.onEvent(self, engEvent);
            }
        }

        /// Keeps the window open after a close request. Call it from
        /// `onEvent` while handling `.close_requested`, e.g. to ask about
        /// unsaved changes first; close later with `window.requestClose()`.
        pub fn cancelClose(self: *Self) void {
            self.window.closeRequested = false;
        }

        /// The engine's live default font atlas, or null when text rendering
        /// is compiled out or no default font is set. See
        /// `Renderer.defaultFontAtlas`. Repack it at a new size at runtime
        /// with, e.g.:
        /// `if (eng.defaultFontAtlas()) |fa| try fa.setFontSize(24.0);`
        pub fn defaultFontAtlas(self: *Self) ?*renderer.FontAtlas {
            return self.renderer.defaultFontAtlas();
        }

        /// Called each frame (after `pollEvents`) to pick up resize events
        /// recorded by the event pump. Rebuilds the viewport and updates
        /// the viewport when the framebuffer has changed.
        pub fn refreshWindowState(self: *Self) void {
            if (!self.windowState.resized) return;
            self.windowState.resized = false;
            self.windowState.refresh(self.window);

            if (self.options.logicalSize == null) {
                self.viewport.logicalSize = self.windowState.framebufferSize;
            }
            const fbsz = self.windowState.framebufferSize;
            self.viewport.updateFramebufferSize(fbsz);

            // Clear the whole framebuffer, letterbox bars included, before
            // restoring the viewport's own scissor rect. The game's clear
            // color is put back afterwards, so a game that set it once with
            // gl.clearColor keeps it across resizes.
            var gameClearColor: [4]f32 = undefined;
            gl.getFloatv(gl.COLOR_CLEAR_VALUE, &gameClearColor);
            gl.disable(gl.SCISSOR_TEST);
            self.renderer.clear(0, 0, 0, 255);
            gl.clearColor(gameClearColor[0], gameClearColor[1], gameClearColor[2], gameClearColor[3]);

            self.viewport.apply();
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
        /// Equivalent to `viewport.screenProjection()`.
        pub fn screenProjection(self: *const Self) zmath.Mat {
            return self.viewport.screenProjection();
        }

        /// Converts a window-coordinate position to framebuffer pixels,
        /// accounting for DPI scale.
        pub fn windowToFramebuffer(self: *const Self, pos: Vec2F) Vec2F {
            return Viewport.windowToFramebuffer(pos, self.windowState.scaleFactor);
        }

        /// Converts a window-coordinate position to logical game coordinates.
        /// Returns null when the pointer is over a letterbox or pillarbox area.
        pub fn windowToLogical(self: *const Self, pos: Vec2F) ?Vec2F {
            return self.viewport.windowToLogical(pos, self.windowState.scaleFactor);
        }

        /// Captures the whole framebuffer, letterbox bars included, and
        /// writes it to a PNG file at `path`. The image is the window's
        /// size: on HiDPI the framebuffer is scaled down to it, otherwise
        /// it is written pixel for pixel.
        pub fn captureScreenshot(self: *const Self, alloc: std.mem.Allocator, path: []const u8) !void {
            const fb_w: usize = @intCast(self.windowState.framebufferSize.x);
            const fb_h: usize = @intCast(self.windowState.framebufferSize.y);
            const fb_row = fb_w * 4;

            const pixels = try alloc.alloc(u8, fb_h * fb_row);
            defer alloc.free(pixels);

            gl.readPixels(0, 0, @intCast(fb_w), @intCast(fb_h), gl.RGBA, gl.UNSIGNED_BYTE, pixels.ptr);

            // OpenGL reads bottom-to-top; flip vertically so the PNG is top-to-bottom.
            const tmp = try alloc.alloc(u8, fb_row);
            defer alloc.free(tmp);
            var top: usize = 0;
            var bot: usize = fb_h - 1;
            while (top < bot) : ({
                top += 1;
                bot -= 1;
            }) {
                @memcpy(tmp, pixels[top * fb_row ..][0..fb_row]);
                @memcpy(pixels[top * fb_row ..][0..fb_row], pixels[bot * fb_row ..][0..fb_row]);
                @memcpy(pixels[bot * fb_row ..][0..fb_row], tmp);
            }

            const fb_img = stbi.Image{
                .data = pixels,
                .width = @intCast(fb_w),
                .height = @intCast(fb_h),
                .num_components = 4,
                .bytes_per_component = 1,
                .bytes_per_row = @intCast(fb_row),
                .is_hdr = false,
            };

            const win_w: u32 = @intCast(self.windowState.windowSize.x);
            const win_h: u32 = @intCast(self.windowState.windowSize.y);

            // Only resize on HiDPI, where the framebuffer is larger than the
            // window. Both share an aspect ratio, so this never distorts.
            const out_img = if (win_w != fb_img.width or win_h != fb_img.height)
                fb_img.resize(win_w, win_h)
            else
                fb_img;
            // fb_img.data is owned by `pixels` (our allocator); only call deinit on a resized copy.
            defer if (out_img.data.ptr != fb_img.data.ptr) {
                var m = out_img;
                m.deinit();
            };

            const path_z = try std.mem.concatWithSentinel(alloc, u8, &.{path}, 0);
            defer alloc.free(path_z);

            try stbi.Image.writeToFile(out_img, path_z, .png);
        }
    };
}
