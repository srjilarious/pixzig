# The Game Loop

[](sym:AppRunner) owns the window, the engine and the main loop. You give it an app with `update` and `render` methods and it calls them at the right times, on desktop and in the browser.

## The App

An app is any struct with these two methods:

```zig
pub const App = struct {
    // Called at a fixed rate (120 Hz by default). `deltaMs` is the step
    // length in milliseconds. Return false to quit.
    pub fn update(self: *App, eng: *AppRunner.Engine, deltaMs: f64) bool { ... }

    // Called once per displayed frame.
    pub fn render(self: *App, eng: *AppRunner.Engine) void { ... }
};
```

Game logic goes in `update` and drawing goes in `render`. Keep them apart: `update` runs at a steady rate no matter how fast the screen refreshes, so movement and timers behave the same on every machine.

## Creating the Runner

`AppRunner` takes your app type and a set of compile-time [](sym:EngineOptions):

```zig
const AppRunner = pixzig.AppRunner(App, .{
    .audioOpts = .{ .enabled = true },
    .inputOpts = .{ .numGamepads = 1 },
});
```

| Option | Default | What it does |
|---|---|---|
| `updateStepHz` | `120` | How often `update` runs. |
| `maxLagMs` | `250` | The most time one frame will catch up on. See below. |
| `rendererOpts` | `.{}` | `shapeRendering`, `textRendering` (both on) and the batch size `maxSprites`. |
| `audioOpts` | off | Set `.enabled = true` to get `eng.audio`. See [Audio](page:audio). |
| `inputOpts` | mouse on | Mouse, gamepad slots and OS text input. See [Input](page:input). |
| `manifestOpts` | `null` | Load an asset manifest during init. See [Assets](page:assets). |
| `scripting` | `false` | Create a Lua state as `eng.scripts`. See [Scripting](page:scripting). |
| `console` | `null` | Create a Lua console as `eng.console`. Needs `scripting`. |
| `defaultIcon` | `true` | Set pixzig's window icon. |

Turning a feature off removes its code paths. Using it anyway is a compile error that names the option, e.g. calling `eng.audio.playSound` without `audioOpts.enabled`. It doesn't change which native libraries get linked, though: every build still links SDL3, OpenGL, flecs, miniaudio, Lua and the rest.

## Starting It Up

`AppRunner.init` creates the window, loads OpenGL and starts the engine's systems. It takes the window title, an allocator and runtime [](sym:EngineInitOptions):

```zig
pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init("My Game", init.gpa, .{
        .windowSize = .{ .x = 960, .y = 540 },
        .logicalSize = .{ .x = 320, .y = 180 },
        .scalePolicy = .integer_fit,
    });
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
```

| Option | Default | What it does |
|---|---|---|
| `windowSize` | 800x480 | Window size in screen coordinates. |
| `logicalSize` | `null` | The game's own resolution. Null means one unit per framebuffer pixel. |
| `scalePolicy` | `.fit` | How the logical resolution scales to the window. See [Viewport and Cameras](page:viewport). |
| `fullscreen`, `resizable` | `false`, `true` | Window mode. |
| `minWindowSize` | `null` | Smallest size the user can shrink the window to. |
| `vsync` | `true` | Change it later with `eng.enableVSync(bool)`. |
| `rngSeed` | `null` | Seed for `eng.rng`. Null seeds from the clock. |
| `renderInitOpts` | embedded font | The renderer's default font. See [Text and Fonts](page:text). |

`run` owns the loop and returns when `update` returns false or the window closes. The `defer`s then tear down your app first and the engine second, which is the order you want: your app may still hold handles into engine resources.

## The Engine

Both app methods get the engine. It's how you reach every system:

| Member | What it is |
|---|---|
| `eng.renderer` | Sprites, shapes and text. See [Rendering](page:rendering). |
| `eng.resources` | The `ResourceManager`: textures, atlases, fonts, maps and shaders. |
| `eng.inputs` | Keyboard, mouse and gamepads. |
| `eng.viewport` | The logical size and how it maps to the window. |
| `eng.audio` | Sound playback, when enabled. |
| `eng.rng` | A seeded random source. See [Math and Gameplay Helpers](page:math). |
| `eng.scripts`, `eng.console` | Lua state and console, when enabled. |
| `eng.manifest` | The asset manifest, when `manifestOpts` is set. |
| `eng.window` | The platform window: size, clipboard, cursor capture. |
| `eng.windowState` | Window and framebuffer sizes and the HiDPI scale. |
| `eng.allocator` | The allocator the engine was created with. |

A few engine methods are handy at runtime: `enableVSync(bool)`, `showCursor(bool)`, `setCursorCapture(bool)` for mouse look, `defaultFontAtlas()` and `captureScreenshot(alloc, "shot.png")`.

## How the Loop Runs

Each frame, the runner measures how much time passed and runs `update` in fixed steps until it has caught up, then calls `render` once:

```zig
// AppRunner.gameLoopCore, simplified:
lag = @min(lag + elapsed, maxLagMs);
eng.pollEvents();
while (lag > UpdateStepMs) {
    lag -= UpdateStepMs;
    eng.inputs.update(...);          // latch this tick's input
    eng.resources.checkHotReload();  // debug builds: pick up changed files
    const keepRunning = app.update(eng, UpdateStepMs);
    eng.inputs.finishTick();         // so pressed/released are one-tick edges
    if (!keepRunning) return false;
}
app.render(eng);
window.swapBuffers();
```

A few things fall out of this:

- `deltaMs` is always the same value (about 8.33 ms at 120 Hz). You can treat it as a constant, but passing it through keeps your code correct if you change `updateStepHz`.
- On a fast machine `render` runs more often than `update`. On a slow one `update` runs several times per frame. Either way game speed stays the same.
- `pressed` and `released` are true for exactly one `update` call, even when several updates run in one frame.
- Rendering is capped by vsync, which is on by default. With vsync off it runs as fast as it can.

The catch-up is capped at `maxLagMs`. After a long hitch or a debugger pause, the game drops the backlog and briefly slows down instead of running hundreds of updates at once. `run` also resets the clock before the first frame, so time spent loading in `App.init` isn't counted. Call `appRunner.resetClock()` yourself after any other long pause.

## Where the App Lives

Most apps load assets and own memory, so they're heap allocated and `init` returns `*App`, as shown above. A tiny app with nothing to free can live on the stack instead:

```zig
var app = App{ .fps = pixzig.utils.FpsCounter.init() };
appRunner.run(&app);
```

`examples/gameloop_ex.zig` is the smallest complete example.
