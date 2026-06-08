# Rendering

Pixzig renders sprites, rectangles, and optional text. Submit drawing between `renderer.begin` and `renderer.end`.

## The Render Frame

```zig
pub fn render(self: *App, eng: *AppRunner.Engine) void {
    eng.renderer.clear(0.0, 0.0, 0.2, 1.0);

    eng.renderer.begin(eng.uiMatrix());
    // Issue draw calls.

    eng.renderer.end();
}
```

`end` flushes each batch queue.

## Loading Textures

Load a raw PNG:

```zig
const tex: *pixzig.Texture = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
```

Load a sprite atlas. `loadAtlas("assets/pac-tiles")` reads matching `.json` and `.png` files:

```zig
_ = try eng.resources.loadAtlas("assets/pac-tiles");

const frame = try eng.resources.getTexture("player_right_1");
```

The atlas JSON lists named rectangular regions inside the PNG. Each named frame becomes a `Texture` with pre-set UV coordinates.

## Drawing Sprites

Draw a texture into an arbitrary destination rectangle:

```zig
// tex: *pixzig.Texture
// dest: logical-coordinate destination
// src: normalized UV region
eng.renderer.draw(tex, dest, src);
```

Use `RectF.fromPosSize` for logical-coordinate rectangles and `RectF.fromCoords` for normalized UVs from texture pixels:

```zig
const dest = RectF.fromPosSize(10, 10, 32, 32);          // x, y, w, h
const src  = RectF.fromCoords(32, 32, 32, 32, 512, 512); // px, py, pw, ph, texW, texH
eng.renderer.draw(tex, dest, src);
```

Draw a `Sprite` with `drawSprite`:

```zig
const spr = Sprite.create(frame, .{ .x = 16, .y = 16 });
eng.renderer.drawSprite(&spr);
```

## Shape Rendering

Shape rendering must be enabled at compile time:

```zig
const AppRunner = pixzig.PixzigAppRunner(App, .{
    .rendererOpts = .{ .shapeRendering = true },
});
```

```zig
const yellow = Color.from(255, 255, 0, 200); // RGBA 0–255
const rect   = RectF.fromPosSize(50, 50, 100, 40);

eng.renderer.drawRect(rect, yellow, 2);
eng.renderer.drawEnclosingRect(rect, Color.from(255, 0, 255, 200), 2);
eng.renderer.drawFilledRect(rect, Color.from(100, 200, 255, 128));
```

## Logical Resolution

Set a logical resolution and scaling policy when initializing the runner:

```zig
const appRunner = try AppRunner.init("My Game", alloc, .{
    .windowSize = .{ .x = 1280, .y = 720 },
    .logicalSize = .{ .x = 320, .y = 180 },
    .scalePolicy = .integer_fit,
});
```

Render with `eng.uiMatrix()`. With `.integer_fit`, logical pixels use an integer framebuffer scale and unused space is letterboxed.

## Full Sprite+Shape Example

```zig
pub fn render(self: *App, eng: *AppRunner.Engine) void {
    eng.renderer.clear(0, 0, 0.2, 1);
    self.fps.renderTick();

    eng.renderer.begin(eng.uiMatrix());

    for (0..3) |i| {
        eng.renderer.draw(self.tex, self.dest[i], self.srcCoords[i]);
    }

    for (0..3) |i| {
        eng.renderer.drawRect(self.dest[i], Color.from(255, 255, 0, 200), 2);
    }

    for (0..3) |i| {
        eng.renderer.drawFilledRect(self.destRects[i], self.colorRects[i]);
    }

    eng.renderer.end();
}
```
