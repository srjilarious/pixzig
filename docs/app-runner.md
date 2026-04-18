# App Runner Model

Pixzig applications almost always utilize a [](sym:PixzigAppRunner), a generic structure that allows you to provide your own application context and runs runs the fixed-time-step game loop for you, working on both desktop and web builds.  It sets up the engine for you and calls your `update` and `render` methods for you.

## Creating the AppRunner
 
```zig
const AppRunner = pixzig.PixzigAppRunner(App, .{
    .gameScale     = 8.0,          // pixel scale factor applied to projection matrix
    .rendererOpts  = .{
        .shapeRendering  = true,   // enable drawRect / drawFilledRect
        .textRendering = false,  // enable text rendering (requires font)
    },
    .audioOpts = .{ .enabled = false },
});
```

[](sym:PixzigEngineOptions) (the second parameter) is evaluated at compile time, so unused subsystems produce zero overhead.

## Initialising

```zig
pub fn main() !void {
    const alloc     = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Window Title", alloc, .{
        .windowSize = .{ .x = 800, .y = 600 },
        .fullscreen = false,
    });
    const app = try App.init(alloc, appRunner.engine);
    glfw.swapInterval(0);
    appRunner.run(app);
}
```

[](sym:AppRunner.init) initializes the engine, which creates the GLFW window, loads OpenGL, and sets up components like the [](sym:ResourceManager) and [](sym:SoundEngine) (if audio is enabled in your [](sym:PixzigEngineOptions)). Calling `appRunner.run(app)` blocks until the window closes, then calls `app.deinit()` and cleans up the engine and various resources.

## The App Interface

Your app struct must provide the `update` and `render` public methods, with the following signatures, otherwise you'll get a compile time error when the [](sym:AppRunner) game loop tries to call them on your struct:

```zig
pub const App = struct {
    // Called at a fixed rate of 120 Hz. Return false to exit.
    // delta is the step size in milliseconds (≈ 8.33 ms).
    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool { ... }

    // Called once per rendered frame (uncapped, or capped by vsync).
    pub fn render(self: *App, eng: *AppRunner.Engine) void { ... }
};
```


The engine reference `eng` gives you access to:

| Field | Type | Description |
|---|---|---|
| `eng.keyboard` | `input.Keyboard` | Frame-level keyboard state |
| `eng.renderer` | `Renderer` | Sprite, shape, and text drawing |
| `eng.resources` | `ResourceManager` | Texture and atlas loading |
| `eng.projMat` | `zmath.Mat` | Orthographic projection matrix |
| `eng.audio` | `AudioEngine` | Sound playback (if enabled) |
| `eng.window` | `*glfw.Window` | Raw GLFW window handle |
| `eng.allocator` | `std.mem.Allocator` | Engine-owned allocator |

## Game Loop Details

The loop runs at a **fixed update rate of 120 Hz** with an uncapped render rate. `update` receives a constant `delta` of `1000.0 / 120.0` ms (~8.33 ms). Accumulated real-time lag is drained in whole update steps before each render, keeping physics and input deterministic regardless of frame rate.

```zig
// Inside AppRunner.gameLoopCore — simplified:
while (lag > UpdateStepMs) {
    lag -= UpdateStepMs;
    eng.keyboard.update(window);
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
