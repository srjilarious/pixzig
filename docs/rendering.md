# Rendering

Pixzig's renderer supports textured sprites, outlined and filled rectangles, and optional text. All drawing happens between `renderer.begin` / `renderer.end` calls.

## The Render Frame

```zig
pub fn render(self: *App, eng: *AppRunner.Engine) void {
    // 1. Clear the framebuffer (RGBA, 0–1 range).
    eng.renderer.clear(0.0, 0.0, 0.2, 1.0);

    // 2. Open a batch with the projection matrix.
    eng.renderer.begin(eng.projMat);

    // 3. Issue draw calls (see below).

    // 4. Flush and present.
    eng.renderer.end();
}
```

The `begin` / `end` pair flushes all batched draw calls to the GPU in a single draw call per batch queue, so the order of individual draw calls within a frame does not affect performance significantly.

## Loading Textures

Load a raw PNG:

```zig
const tex: *pixzig.Texture = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
```

Load a sprite atlas (JSON + matching PNG automatically paired by name):

```zig
_ = try eng.resources.loadAtlas("assets/pac-tiles"); // loads pac-tiles.json + pac-tiles.png

// Retrieve named frames as Texture pointers:
const frame = try eng.resources.getTexture("player_right_1");
```

The atlas JSON lists named rectangular regions inside the PNG. Each named frame becomes a `Texture` with pre-set UV coordinates.

## Drawing Sprites

Draw a texture into an arbitrary destination rectangle:

```zig
// tex: *pixzig.Texture
// dest: RectF  — screen-space destination (pixels)
// src:  RectF  — source UV region (normalised 0–1)
eng.renderer.draw(tex, dest, src);
```

Use `RectF.fromPosSize` for pixel-space rects and `RectF.fromCoords` to compute normalised UVs from pixel coordinates inside a texture:

```zig
const dest = RectF.fromPosSize(10, 10, 32, 32);          // x, y, w, h
const src  = RectF.fromCoords(32, 32, 32, 32, 512, 512); // px, py, pw, ph, texW, texH
eng.renderer.draw(tex, dest, src);
```

For the `Sprite` struct (which wraps a `*Texture`, destination, and flip/rotate state), use `drawSprite`:

```zig
// Sprite.create(texture, size_in_game_units)
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

// Outlined rectangle (just the border, lineWidth pixels thick):
eng.renderer.drawRect(rect, yellow, 2);

// Outlined rectangle grown by lineWidth on all sides:
eng.renderer.drawEnclosingRect(rect, Color.from(255, 0, 255, 200), 2);

// Solid filled rectangle:
eng.renderer.drawFilledRect(rect, Color.from(100, 200, 255, 128));
```

## Game Scale

`PixzigEngineOptions.gameScale` multiplies the projection matrix so that game-unit coordinates map to multiple screen pixels. With `gameScale = 8.0`, drawing a sprite at game position (16, 16) with size (16, 16) occupies a 128×128 screen-pixel area:

```zig
const AppRunner = pixzig.PixzigAppRunner(App, .{ .gameScale = 8.0 });
```

This is the standard setup for pixel-art games where each "tile" is 16×16 game units and you want crisp integer scaling.

## Full Sprite+Shape Example

```zig
pub fn render(self: *App, eng: *AppRunner.Engine) void {
    eng.renderer.clear(0, 0, 0.2, 1);
    self.fps.renderTick();

    eng.renderer.begin(eng.projMat);

    // Textured sprites
    for (0..3) |i| {
        eng.renderer.draw(self.tex, self.dest[i], self.srcCoords[i]);
    }

    // Yellow outline
    for (0..3) |i| {
        eng.renderer.drawRect(self.dest[i], Color.from(255, 255, 0, 200), 2);
    }

    // Semi-transparent filled rects
    for (0..3) |i| {
        eng.renderer.drawFilledRect(self.destRects[i], self.colorRects[i]);
    }

    eng.renderer.end();
}
```
