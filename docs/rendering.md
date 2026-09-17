# Rendering

Pixzig renders sprites, rectangles, and optional text. Submit drawing between `renderer.begin` and `renderer.end`.

## The Render Frame

```zig
pub fn render(self: *App, eng: *AppRunner.Engine) void {
    eng.renderer.clear(0.0, 0.0, 0.2, 1.0);

    eng.renderer.begin(eng.projection());
    // Issue draw calls.

    eng.renderer.end();
}
```

`end` flushes each batch queue.

## Loading Textures

Resources are reference-counted. `loadTexture` registers the file and returns a `*ManagedTexture`. Call `acquire()` on it to get a `*TextureHandle` with a bumped refcount, store the handle in your app, and call `handle.release()` in `deinit`.

```zig
// During App.init:
const managed = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
self.tex = managed.acquire() orelse return error.NoTexture;

// During App.deinit:
self.tex.release();
```

To draw, pass a pointer to the `Texture` value inside the handle:

```zig
eng.renderer.draw(&self.tex.val, dest, srcCoords);
```

`acquireTexture` is a convenience that combines the lookup and acquire in one call:

```zig
self.tex = try eng.resources.acquireTexture("tiles");
```

### Atlas Loading

`loadAtlas` reads matching `.json` and `.png` files. Each named frame in the JSON becomes its own texture entry. Acquire individual frames by their frame name:

```zig
_ = try eng.resources.loadAtlas("assets/pac-tiles");
self.player_tex = try eng.resources.acquireTexture("player_right_1");
```

`loadAtlasNamed` lets the resource id differ from the filename:

```zig
_ = try eng.resources.loadAtlasNamed("main_sprites", "assets/pac-tiles");
```

## Drawing Sprites

`eng.resources.createSprite(name)` builds a sprite from any loaded texture, atlas frame, or subtexture. The sprite acquires its own handle and starts at the frame's size; release it with `deinit()`:

```zig
// During App.init:
self.spr = try eng.resources.createSprite("player_right_1");
self.spr.setPosF(100.5, 50);  // or setPos(i32, i32)
self.spr.setScale(2, 2);      // relative to the frame size
self.spr.tint = .{ .r = 1, .g = 0.4, .b = 0.4, .a = 1 }; // null = untinted

// Each frame:
eng.renderer.drawSprite(&self.spr); // uses the tinted batch when tint is set

// During App.deinit:
self.spr.deinit();
```

`setPos`, `setPosF`, `setSize`, and `setScale` keep `dest` and `size` in sync; writing `dest` directly skips that. `setSrcRect(RectI)` draws a sub-region of the frame, in pixels.

`Sprite.create(managed)` does the same from a `*ManagedTexture` (it acquires a new handle; `managed` is not consumed). `Sprite.createFromHandle(handle)` takes ownership of a handle you already acquired, so don't release that handle separately.

### Subtextures

`addSubTexture` registers a named region of a texture, in pixels relative to that texture's top-left corner. It works on atlas frames and other subtextures too. Use `addSubTextureUV` if you have UV coordinates (0..1) instead.

```zig
const sheet = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
_ = try eng.resources.addSubTexture(sheet, "guy", RectI.init(32, 32, 32, 32));
var guy = try eng.resources.createSprite("guy");
```

To draw a raw texture region instead:

```zig
const dest = RectF.fromPosSize(10, 10, 32, 32);
const src  = RectF.fromCoords(32, 32, 32, 32, 512, 512); // px, py, pw, ph, texW, texH
eng.renderer.draw(&self.tex.val, dest, src);
```

## Hot Reload

In debug builds, the resource manager watches texture, atlas, font, and tilemap files for changes. When a file changes, it reloads the asset and marks any live handles dirty. If you need to respond to a reload (for example to rebuild a renderer), check `handle.dirty` each tick and call `handle.reacquire()`:

```zig
pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
    _ = delta;
    if (self.tex.dirty) self.tex = self.tex.reacquire();
    // ...
    return true;
}
```

`reacquire` atomically upgrades to the latest generation and releases the old handle. In release builds, `dirty` is always false and `reacquire` is a no-op.

## Text and Fonts

Text rendering must be enabled at compile time (`rendererOpts.textRendering = true`); calling `drawString` and friends without it is a compile error that names the flag. The renderer keeps one default font, set through `renderInitOpts.font`:

```zig
const appRunner = try AppRunner.init("My Game", alloc, .{
    .renderInitOpts = .{ .font = .{ .path = .{
        .face = "assets/AmigaTopaz.ttf",
        .size = 18.0,
        .face_index = 0, // face inside a .ttc collection; 0 for a plain file
    } } },
});
```

`font` is a `FontSource`: either `.path` (a file, as above) or `.id` for a font already loaded elsewhere (e.g. a manifest boot group). An app that reads its font from a Lua config just fills the `.path` struct from those values.

Draw with `drawString`, `drawStringColored`, or `drawScaledString` between `begin` and `end`. Add extra coverage for codepoints the primary face lacks with `eng.renderer.addDefaultFontFallback(&eng.resources, path, face_index)`.

### Changing font size at runtime

`eng.defaultFontAtlas()` returns a `?*FontAtlas` -- the live atlas the renderer draws from. `FontAtlas.setFontSize(px)` repacks it in place at a new pixel size: every face (primary and fallbacks) is rescaled and the glyphs are re-rasterized on the same GL texture, so the next `drawString` uses the new size with no other bookkeeping.

```zig
pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
    const kb = &eng.inputs.keyboard;
    if (kb.ctrl()) {
        if (eng.defaultFontAtlas()) |fa| {
            if (kb.pressed(.minus)) fa.setFontSize(@max(8, fa.font_size - 2)) catch {};
            if (kb.pressed(.equal)) fa.setFontSize(@min(72, fa.font_size + 2)) catch {}; // Shift+= is '+'
            if (kb.pressed(.zero))  fa.setFontSize(20) catch {};
        }
    }
    return true;
}
```

- The engine applies the size verbatim -- any min/max clamp or step is the app's to impose.
- `setFontSize` reloads and repacks glyphs, so call it on a key press, not every frame, and outside a `begin`/`end` pair.
- It returns `error.NotAScalableFont` for a bitmap font (`loadFontFromBitmap`).
- Metrics that were read once at startup (`measureFontFileIndexed`, e.g. a terminal's cell size) are not recomputed -- do that yourself after a resize if you depend on them.
- In debug builds a later hot-reload of the font file rebuilds the atlas at its originally configured size.

## Shape Rendering

Shape rendering must be enabled at compile time:

```zig
const AppRunner = pixzig.PixzigAppRunner(App, .{
    .rendererOpts = .{ .shapeRendering = true },
});
```

```zig
const yellow = Color.from(255, 255, 0, 200); // RGBA 0-255
const rect   = RectF.fromPosSize(50, 50, 100, 40);

eng.renderer.drawRect(rect, yellow, 2);
eng.renderer.drawEnclosingRect(rect, Color.from(255, 0, 255, 200), 2);
eng.renderer.drawFilledRect(rect, Color.from(100, 200, 255, 128));
```

Calling a shape or text draw function when the corresponding option is compiled out is only checked with a debug assertion. In a release build it isn't a caught error — it reads an uninitialized batch, which is undefined behavior. Only call these when the matching `rendererOpts` flag is `true`.

## Logical Resolution

Set a logical resolution and scaling policy when initializing the runner:

```zig
const appRunner = try AppRunner.init("My Game", alloc, .{
    .windowSize = .{ .x = 1280, .y = 720 },
    .logicalSize = .{ .x = 320, .y = 180 },
    .scalePolicy = .integer_fit,
});
```

Pass `eng.projection()` to `renderer.begin`. With `.integer_fit`, the logical grid is scaled to the largest integer multiple that fits, and the remainder is letterboxed.

## Full Sprite+Shape Example

```zig
pub const App = struct {
    tex: *pixzig.TextureHandle,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);
        const managed = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");
        app.* = .{ .tex = managed.acquire() orelse return error.NoTexture };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.tex.release();
        self.alloc.destroy(self);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);
        eng.renderer.begin(eng.projection());

        eng.renderer.draw(&self.tex.val, RectF.fromPosSize(10, 10, 32, 32),
                          RectF.fromCoords(32, 32, 32, 32, 512, 512));

        eng.renderer.drawRect(RectF.fromPosSize(10, 10, 32, 32),
                              Color.from(255, 255, 0, 200), 2);

        eng.renderer.end();
    }
};
```
