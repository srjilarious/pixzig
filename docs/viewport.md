# Viewport and Cameras

Most 2D games draw at a fixed, low resolution and scale it up to fill the window. Pixzig calls that the logical resolution. The viewport maps it onto the window, and a `Camera2D` scrolls, zooms and rotates a larger world inside it.

## Logical Resolution

Set `logicalSize` when creating the runner, and pick how it scales with `scalePolicy`:

```zig
const appRunner = try AppRunner.init("My Game", alloc, .{
    .windowSize = .{ .x = 960, .y = 540 },
    .logicalSize = .{ .x = 320, .y = 180 },
    .scalePolicy = .integer_fit,
});
```

Now `begin(.logical)` draws in a 320x180 space no matter how big the window is. Without a `logicalSize`, logical space follows the window and one unit is one pixel.

| `ScalePolicy` | Behavior |
|---|---|
| `.fit` | Scale evenly so the whole game fits. Leaves black bars on two sides when the aspect ratios differ. The default. |
| `.integer_fit` | Like `.fit`, but only by whole multiples (2x, 3x, ...). Pixel art stays crisp. |
| `.fill` | Scale evenly so the game covers the whole window, cropping what doesn't fit. |
| `.integer_fill` | Like `.fill`, by whole multiples. |
| `.stretch` | Fill the window and ignore the aspect ratio. |
| `.{ .fixed = 2.0 }` | Always this scale, centered. |

With `.integer_fit`, the runner also sizes the window at startup to an exact multiple of the logical size, so there are no bars until the user resizes it. Set `minWindowSize` if you don't want it shrunk below 1x.

`eng.viewport.logicalSize` is the current logical size. When you don't set one, it changes as the window resizes, so read it rather than caching it.

## Coordinates

There are three coordinate spaces, and pixzig converts between them for you:

| Space | What it is |
|---|---|
| Logical | The game's resolution. What `begin(.logical)` and `mouse.pos()` use. |
| Framebuffer | Real pixels on screen. Bigger than window coordinates on a HiDPI display. |
| Window | What the OS reports, in screen coordinates. |

You rarely need these yourself. `eng.inputs.mouse.pos()` is already in logical coordinates, and it's null while the cursor sits over a letterbox bar. When you do need them, the viewport has `framebufferToLogical`, `logicalToFramebuffer` and `windowToLogical`, and the engine has `eng.windowToLogical(pos)`.

For a debug overlay in real pixels, draw in a `.screen` pass. It covers the whole framebuffer including the bars, and `end()` puts the normal viewport back.

## Cameras

A `Camera2D` looks at a point in your world. Draw through it with `begin(.{ .camera = &cam })`:

```zig
// In App:
camera: pixzig.Camera2D = .{},

// In update, follow the player:
self.camera.follow(self.player.dest.centerF(), deltaMs, .{});

// In render:
eng.renderer.begin(.{ .camera = &self.camera });
eng.renderer.drawSprite(&self.player);
eng.renderer.end();
```

`pos` is the world point shown at the center of the screen. The camera has a few more fields:

| Field | What it does |
|---|---|
| `zoom` | 2.0 shows everything twice as big. Defaults to 1. |
| `rotation` | Turns the view, in radians. Positive is clockwise on screen. |
| `bounds` | A world rect the camera won't look outside of. Usually the map's size. |

`follow(target, deltaMs, opts)` moves the camera toward a world point once per update. With the default options it jumps straight there. Two options soften that:

| Option | What it does |
|---|---|
| `deadzone` | Half-size of a box around the screen center. The target can move inside it without moving the camera, like a platformer that only scrolls near the edges. |
| `smoothing` | How fast the camera catches up, per second. After one second `exp(-smoothing)` of the gap is left: around 5 feels tight, 2 feels floaty. Null (the default) means no lag. |

```zig
self.camera.follow(target, deltaMs, .{ .deadzone = .{ .x = 32, .y = 24 }, .smoothing = 6 });
```

The smoothing doesn't depend on the step size, so changing `updateStepHz` doesn't change how the camera feels. For flecs games, `pixzig.ecs.followEntity` follows an entity's sprite.

With `bounds` set, the camera stops at the edges instead of showing empty space past the end of the map. If the visible area is bigger than the bounds on an axis, it centers on them instead.

```zig
self.camera.bounds = .{ .l = 0, .t = 0, .r = mapWidthPx, .b = mapHeightPx };
```

The camera doesn't store the screen size. Every method takes the viewport, so it keeps working when the window resizes:

```zig
// Where is the mouse in the world?
if (eng.inputs.mouse.pos()) |screenPos| {
    const worldPos = self.camera.logicalToWorld(&eng.viewport, screenPos);
    self.cursorTile = .{ .x = @intFromFloat(worldPos.x / 16), .y = @intFromFloat(worldPos.y / 16) };
}

// What part of the world is visible? Good for culling.
const visible = self.camera.viewRect(&eng.viewport);
```

`worldToLogical` goes the other way, e.g. to put a name tag over an enemy in a HUD pass. All of these account for zoom, rotation and bounds.

For parallax backgrounds, `camera.matrixAt(&eng.viewport, center)` gives you a matrix centered somewhere else with the same zoom and rotation. Pass `pos` times your scroll factor and draw with `begin(.{ .matrix = m })`. `TileMapRenderer` does this for you per layer (see [Tile Maps](page:tile-rendering)).

## HiDPI

On a 2x display the framebuffer has twice the pixels of the window. `eng.windowState` tracks both sizes, and `windowState.scaleFactor` is the ratio between them. The engine handles this for drawing and mouse input. If you hand the OS something in window units, like `window.setSize`, divide by `scaleFactor` first. [Platform Backend](page:platform-backend) has the details.
