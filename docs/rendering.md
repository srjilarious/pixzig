# Rendering

`eng.renderer` draws sprites, textures, rectangles and text. Every draw goes between a `begin` and an `end`, and shows up in the order you submit it.

## A Render Frame

```zig
pub fn render(self: *App, eng: *AppRunner.Engine) void {
    eng.renderer.clear(0, 0, 51, 255);

    eng.renderer.begin(.logical);
    eng.renderer.drawSprite(&self.player);
    eng.renderer.drawRect(self.player.dest, Color.from(255, 255, 0, 255), 1);
    eng.renderer.end();
}
```

`clear` takes 0-255 RGBA values. `begin` takes the coordinate space to draw in:

| `begin(...)` | Space |
|---|---|
| `.logical` | The game's logical resolution, y down. The usual choice. |
| `.{ .camera = &cam }` | World space seen through a `Camera2D`. See [Viewport and Cameras](page:viewport). |
| `.screen` | Framebuffer pixels, y down. Covers the whole window, letterbox bars included. Good for debug overlays. |
| `.{ .matrix = m }` | Your own model-view-projection matrix. |

You can run as many passes as you like in one frame. A common pattern is a camera pass for the world and a logical pass for the HUD on top:

```zig
eng.renderer.begin(.{ .camera = &self.camera });
// world: tiles, enemies, the player
eng.renderer.end();

eng.renderer.begin(.logical);
// HUD: score, health
eng.renderer.end();
```

## Batching

Every draw call (sprites, textures, shapes and text) goes into one batch. Consecutive draws that use the same texture go out to the GPU as a single draw call, whatever their color or kind. Switching texture flushes the batch, and so does `end`.

All shapes share a built-in white texture and all text shares the font atlas, so a run of rectangles or a block of text is one call. When draw order doesn't matter, grouping draws by texture keeps the call count down. Pack your sprites into an atlas (see [Assets](page:assets)) and most of a scene becomes one call.

The batch flushes on its own when it fills up. If a scene really draws tens of thousands of quads, raise `rendererOpts.maxSprites` to keep it in one call.

## Drawing Textures

To draw part of a texture, give a destination rect and a source rect in UV coordinates (0 to 1):

```zig
const dest = RectF.fromPosSize(10, 10, 32, 32);
const src = RectF.fromCoords(32, 32, 32, 32, 512, 512); // px, py, pw, ph, texW, texH
eng.renderer.drawTexture(self.tex, dest, src);

eng.renderer.drawFullTexture(self.tex, .{ .x = 10, .y = 50 }, 2.0); // whole texture, 2x
```

`self.tex` is a `*TextureHandle` from the resource manager. [Assets](page:assets) covers loading textures, atlases and subtextures.

## Sprites

For anything that moves, use a `Sprite`. It holds a texture region plus a position, size, origin and color options. Create one from any loaded texture, atlas frame or subtexture:

```zig
// During init:
self.player = try eng.resources.createSprite("player_right_1");
self.player.setPos(100, 50);

// Each frame:
eng.renderer.drawSprite(&self.player);
```

`Sprite.create(handle)` does the same from a handle you already have. A sprite owns nothing, so there's nothing to free.

| Method | What it does |
|---|---|
| `setPos(x, y)`, `setPosF(x, y)` | Place the sprite's origin, in integers or floats. |
| `pos()` | Where the origin is now. |
| `setSize(w, h)`, `setScale(sx, sy)` | Resize, around the origin. `setScale` is relative to the frame's size. |
| `setOrigin(x, y)` | The pivot, in the frame's own pixels. |
| `setOriginNormalized(nx, ny)`, `setOriginCentered()` | The pivot as a fraction of the frame. |
| `setSrcRect(RectI)` | Draw only part of the frame, in pixels. |
| `setTexture(handle)` | Switch to another texture. |

Use these setters rather than writing `dest` yourself. They keep `dest`, `size` and the origin in sync.

Positions are floats, so slow movement accumulates smoothly, but `drawSprite` snaps the sprite to a whole pixel when it draws. A sprite sitting between pixels never comes out blurry.

### Origin

The origin is the sprite's pivot point. `setPos` places it, and scaling grows the sprite around it. It defaults to the top-left corner. For a character, bottom-center is usually what you want:

```zig
spr.setOriginNormalized(0.5, 1); // feet
spr.setPos(100, 50);             // feet at (100, 50)
spr.setScale(2, 2);              // grows up and out; feet stay put
```

`setOrigin(3, 12)` picks an exact pixel of the frame, like a hand holding a weapon. Changing the origin keeps `pos()` where it was and moves the image so the new origin lands on it.

### Tint, Fill and Rotation

`tint` multiplies the sprite's colors. `fill` replaces the color entirely while keeping the shape, which makes the classic white hit flash. `fill.a` blends between the sprite's own color (0) and a solid fill (1), and `fill` wins over `tint` when both are set:

```zig
self.spr.tint = Color{ .r = 1, .g = 0.4, .b = 0.4, .a = 1 }; // reddish
self.spr.fill = Color.from(255, 255, 255, 255);             // white silhouette
self.spr.fill = null;                                       // back to normal
```

For a one-off draw without changing the sprite, use `drawSpriteColored(&spr, color)` or `drawSpriteFilled(&spr, color)`.

`rotate` turns or flips the image in quarter turns: `.none`, `.rot90`, `.rot180`, `.rot270`, `.flipHorz` and `.flipVert`. The sprite's rect stays the same, so quarter turns are meant for square sprites.

To animate sprites, wrap them in an `Actor`. See [Sprites and Animation](page:animation).

## Shapes

```zig
const box = RectF.fromPosSize(50, 50, 100, 40);

eng.renderer.drawFilledRect(box, Color.from(100, 200, 255, 128));
eng.renderer.drawRect(box, Color.from(255, 255, 0, 255), 2);          // border inside the rect
eng.renderer.drawEnclosingRect(box, Color.from(255, 0, 255, 255), 2); // border outside the rect
```

Shapes and text are on by default. Set `rendererOpts.shapeRendering = false` or `textRendering = false` to compile them out. Calling one of their draw functions after that is a compile error that names the option.

## Clipping

`setClip(rect)` clips later draws to a rect in logical coordinates. `setClip(null)` goes back to the normal viewport. It flushes queued draws first, so they keep the clip they were drawn under:

```zig
eng.renderer.setClip(RectF.fromPosSize(10, 10, 100, 60));
// draws here are cut off at the panel's edges
eng.renderer.setClip(null);
```

If you change any other OpenGL state in the middle of a pass, call `eng.renderer.flush()` first so the queued draws go out under the old state.

## Mixing in Other Renderers

A few renderers draw on their own rather than through the batch: `TileMapRenderer`, `PixelBuffer`, `GridRenderer` and the 3D quad batches. Call them outside a `begin`/`end` pair, between your own passes:

```zig
self.mapRenderer.renderLayersBelow(1.0, &self.camera, &eng.viewport);

eng.renderer.begin(.{ .camera = &self.camera });
eng.renderer.drawSprite(&self.player);
eng.renderer.end();

self.mapRenderer.renderLayersAbove(1.0, &self.camera, &eng.viewport);
```

See [Tile Maps](page:tile-rendering) and [Low-Level Rendering](page:low-level-rendering).

`examples/render_ex.zig` draws textures and shapes, and `examples/actor_ex.zig` draws an animated sprite.
