# App Runner Model

[](sym:PixzigAppRunner) owns the engine lifecycle and calls an application's `update` and `render` methods on desktop and web builds.

## Creating the AppRunner
 
```zig
const AppRunner = pixzig.PixzigAppRunner(App, .{
    .rendererOpts = .{
        .shapeRendering = true,
        .textRendering = false,
    },
    .audioOpts = .{ .enabled = false },
    .inputOpts = .{ .numGamepads = 1 },
});
```

[](sym:PixzigEngineOptions) is evaluated at compile time. Use it to enable rendering, audio, and input features required by the application.

## Initialising

```zig
pub fn main() !void {
    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Window Title", alloc, .{
        .windowSize = .{ .x = 800, .y = 600 },
        .logicalSize = .{ .x = 320, .y = 180 },
        .scalePolicy = .integer_fit,
        .fullscreen = false,
    });
    const app = try App.init(alloc, appRunner.engine);
    glfw.swapInterval(0);
    appRunner.run(app);
}
```

[](sym:AppRunner.init) creates the GLFW window, loads OpenGL, and initializes engine systems. If audio is enabled it also initializes [](sym:AudioEngine). `appRunner.run(app)` calls `app.deinit()` and releases engine resources when the loop exits.

## The App Interface

An app provides these public methods:

```zig
pub const App = struct {
    // Called at a fixed rate of 120 Hz. Return false to exit.
    // delta is the step size in milliseconds (about 8.33 ms by default).
    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool { ... }

    // Called once per rendered frame (uncapped, or capped by vsync).
    pub fn render(self: *App, eng: *AppRunner.Engine) void { ... }
};
```


The engine reference `eng` gives you access to:

| Member | Type / Return | Description |
|---|---|---|
| `eng.inputs` | `input.InputManager` | Keyboard, mouse, and configured gamepads |
| `eng.renderer` | `Renderer` | Sprite, shape, and text drawing |
| `eng.resources` | `ResourceManager` | Texture and atlas loading |
| `eng.viewport` | `Viewport` | Logical size, scaling, and projection |
| `eng.audio` | `AudioEngine` | Sound playback (if enabled) |
| `eng.window` | `*glfw.Window` | Raw GLFW window handle |
| `eng.allocator` | `std.mem.Allocator` | Engine-owned allocator |
| `eng.projection()` | `zmath.Mat` | Orthographic matrix for the logical coordinate space; use this as the MVP base for all game rendering |
| `eng.screenProjection()` | `zmath.Mat` | Orthographic matrix for the full framebuffer in actual pixels; use for UI overlays that should be in screen-pixel coordinates |

## Game Loop Details

The default update rate is 120 Hz. Set `updateStepHz` in `PixzigEngineOptions` to change it. Rendering is uncapped unless vsync limits it.

```zig
// Inside AppRunner.gameLoopCore, simplified:
while (lag > UpdateStepMs) {
    lag -= UpdateStepMs;
    eng.inputs.update(eng.window, eng.window_state.scale_factor, &eng.viewport);
    if (!app.update(eng, UpdateStepMs)) return false;
}
app.render(eng);
window.swapBuffers();
```

## Stack vs Heap App

For simple apps with no allocations, the app can live on the stack:

```zig
var app = App.init(123);   // returns App, not *App
appRunner.run(&app);
```

For apps that load assets or own heap memory, allocate with the provided allocator and return `*App` from `init`:

```zig
pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
    const app = try alloc.create(App);
    app.* = .{ .alloc = alloc, ... };
    return app;
}

pub fn deinit(self: *App) void {
    self.alloc.destroy(self);
}
```
