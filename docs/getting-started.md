# :rocket: Getting Started

Pixzig is a 2D game engine written in Zig. It provides a fixed-timestep game loop, OpenGL sprite rendering, ECS via flecs, Lua scripting, audio, keyboard/mouse/gamepad input, and a tween-style action sequencer.

## Adding Pixzig to Your Project

Declare pixzig as a dependency in your `build.zig.zon`:

```zig
.dependencies = .{
    .pixzig = .{
        .path = "../pixzig", // or a URL + hash for a fetched dep
    },
},
```

In your `build.zig`, pull in the engine module and library using `buildGame`:

```zig
const pixzig = b.dependency("pixzig", .{ .target = target, .optimize = optimize });
const exe_mod = b.createModule(.{ .root_source_file = b.path("src/main.zig"), ... });
const exe = pixzig.buildGame(b, target, optimize,
    pixzig,
    pixzig.module("pixzig"),
    "my_game",
    exe_mod,
    &.{ "my_atlas.json", "my_atlas.png" },
);
```

## Minimal Example

The smallest working pixzig program creates an `AppRunner`, initialises an app struct, and hands control to the engine:

```zig
const std   = @import("std");
const pixzig = @import("pixzig");
const glfw  = pixzig.glfw;

pub const panic      = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{});

pub const App = struct {
    pub fn init(_: std.mem.Allocator, _: *AppRunner.Engine) !*App {
        // one-time setup here
        return &App{};
    }

    pub fn deinit(_: *App) void {}

    pub fn update(_: *App, eng: *AppRunner.Engine, _: f64) bool {
        if (eng.keyboard.pressed(.escape)) return false;
        return true;
    }

    pub fn render(_: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.1, 0.1, 0.2, 1);
    }
};

pub fn main() !void {
    const alloc     = std.heap.c_allocator;
    const appRunner = try AppRunner.init("My Game", alloc, .{});
    const app       = try App.init(alloc, appRunner.engine);
    glfw.swapInterval(1);
    appRunner.run(app);
}
```

## Project Conventions

- **`pub const panic = pixzig.system.panic`** — installs platform-appropriate panic and log handlers (required at the root of every executable).
- **`pub const std_options = pixzig.system.std_options`** — same, for log level routing.
- Use `std.heap.c_allocator` for the top-level allocator; it is the most compatible with both native and Emscripten web builds.
- Call `glfw.swapInterval(0)` to disable vsync during development for raw FPS numbers, or `swapInterval(1)` for a production build.
