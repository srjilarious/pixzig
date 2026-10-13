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

## Events

An app can also declare `onEvent` to hear about things the OS reports that aren't keyboard, mouse or text input. It's optional; the runner only calls it when the method exists.

```zig
pub fn onEvent(self: *App, eng: *AppRunner.Engine, event: pixzig.Event) void {
    switch (event) {
        .close_requested => if (self.unsavedChanges) {
            eng.cancelClose();
            self.showSavePrompt = true;
        },
        .drop_file => |drop| self.loadLevel(drop.path),
        .focus_lost => self.paused = true,
        else => {},
    }
}
```

| Event | When |
|---|---|
| `close_requested` | The close button, Alt+F4, Cmd+Q, or SIGINT/SIGTERM. The window closes afterwards unless `onEvent` calls `eng.cancelClose()`. |
| `window_resized` | The window changed size. Carries the new size in window coordinates; `eng.viewport` already matches it. |
| `focus_gained`, `focus_lost` | Keyboard focus moved. Input state is already cleared on `focus_lost`. |
| `minimized`, `maximized`, `restored` | The window's state changed. |
| `drop_begin`, `drop_file`, `drop_text`, `drop_complete` | Drag-and-drop onto the window. `drop_file` carries a `path` and `drop_text` a `text`, plus the drop `pos` in window coordinates. Both strings are only valid during the call, so copy them to keep them. |
| `gamepad_added`, `gamepad_removed` | A pad was plugged in or out. Only reported with `inputOpts.numGamepads` above zero. See [Input](page:input). |
| `will_enter_background`, `did_enter_background`, `will_enter_foreground`, `did_enter_foreground`, `low_memory`, `terminating` | App lifecycle, mostly from mobile platforms. |

`onEvent` runs during the event pump at the start of each frame, before that frame's `update` calls. Input isn't delivered here on purpose: keys and buttons are latched per tick so `pressed` stays a one-update edge, and reading them in `update` keeps that true.

A close request is reported once per frame even though SDL reports closing the last window twice (a window close, then a quit), so cancelling it once is enough. To close later, after the prompt is answered, call `eng.window.requestClose()` or return false from `update`.

The lifecycle events come through the same once-per-frame pump. That's too late for iOS and Android, which expect `will_enter_background` to be handled before the OS suspends the app, so treat them as advisory for now.

## Creating the Runner

`AppRunner` takes your app type and a set of compile-time [](sym:EngineOptions):

```zig
const AppRunner = pixzig.AppRunner(App, .{
    .inputOpts = .{ .numGamepads = 1 },
    .scripting = true,
});
```

| Option | Default | What it does |
|---|---|---|
| `updateStepHz` | `120` | How often `update` runs. |
| `maxLagMs` | `250` | The most time one frame will catch up on. See below. |
| `rendererOpts` | `.{}` | `shapeRendering`, `textRendering` (both on) and the batch size `maxSprites`. |
| `audioOpts` | on | Sound, music and streams as `eng.audio`; `.enabled = false` turns it off. See [Audio](page:audio). |
| `inputOpts` | mouse on | Mouse, gamepad slots and OS text input. See [Input](page:input). |
| `actionOpts` | `null` | Set `.Action` (and optionally `.Axes`) to get an action map as `eng.actions`. See [Input](page:input). |
| `manifestOpts` | `null` | Load an asset manifest during init. See [Assets](page:assets). |
| `scripting` | `false` | Create a Lua state as `eng.scripts`. See [Scripting](page:scripting). |
| `console` | `null` | Create a Lua console as `eng.console`. Needs `scripting`. |
| `defaultIcon` | `true` | Set pixzig's window icon. |
| `screenshotHook` | `false` | Let `PIXZIG_SCREENSHOT` capture a frame and exit. See [Building and Shipping](page:building). |

Turning a feature off removes its code paths. Using it anyway is a compile error that names the option, e.g. calling `eng.audio.play` with `audioOpts.enabled = false`. It doesn't change which native libraries get linked, though: every build still links SDL3, OpenGL, flecs, miniaudio, Lua and the rest.

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
| `eng.resources` | The `ResourceManager`: textures, atlases, fonts, maps, shaders, sounds and music. |
| `eng.inputs` | Keyboard, mouse and gamepads. |
| `eng.actions` | The action map, when `actionOpts` is set. |
| `eng.viewport` | The logical size and how it maps to the window. |
| `eng.audio` | Sound, music and stream playback. See [Audio](page:audio). |
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
eng.pollEventsWith(app);             // app.onEvent, when it has one
while (lag > UpdateStepMs) {
    lag -= UpdateStepMs;
    eng.inputs.update(...);          // latch this tick's input
    eng.updateActions(UpdateStepMs); // when actionOpts is set
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
