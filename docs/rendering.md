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

Draws appear in the order you submit them. Each kind of draw (plain sprites and textures, tinted sprites, shapes, text, colored text) queues into its own batch; switching to a different kind flushes the previous batch first, and `end` flushes whatever is left. Consecutive draws of the same kind and texture still go out as one GL call, so when order doesn't matter, grouping similar draws keeps the call count down.

## Loading Textures

Every texture loader returns a `*TextureHandle`. There are two ways to hold one:

- **Borrowed** (the simple path): `loadTexture`, `loadTextureFromBuffer`, `createTextureImageFromChars`, `addSubTexture`, and `getTexture(name)` return a handle without taking a reference. Keep it and draw with it; never release it. It stays valid until the resource manager deinits.
- **Owned**: `acquireTexture(name)` bumps the refcount. Call `handle.release()` when you're done. Use this when something must keep a texture alive on its own terms (a cache, a long-lived renderer).

```zig
// During App.init -- nothing to release later:
self.tex = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png");

// Later, anywhere:
const tiles = try eng.resources.getTexture("tiles");
```

To draw a region of a texture, pass the handle straight to `drawTexture`:

```zig
eng.renderer.drawTexture(self.tex, dest, srcCoords);
eng.renderer.drawFullTexture(self.tex, .{ .x = 10, .y = 10 }, 2.0); // whole frame, 2x
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

`eng.resources.createSprite(name)` builds a sprite from any loaded texture, atlas frame, or subtexture, sized to that frame. `Sprite.create(handle)` does the same from a handle, borrowed or owned. Either way the sprite retains its own reference and releases it in `deinit()`; your handle is untouched.

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

`setPos`, `setPosF`, `setSize`, `setScale`, and `setOrigin` keep `dest` and `size` in sync; writing `dest` directly skips that. `setSrcRect(RectI)` draws a sub-region of the frame, in pixels. `setTexture(handle)` switches the texture (retaining the new one, releasing the old).

### Origin

A sprite's origin is its pivot, in the texture frame's own pixels, measured from the frame's top-left corner. `setPos` places the origin, and `setSize`/`setScale` grow the sprite around it. It defaults to `(0, 0)`, the top-left corner.

```zig
spr.setOriginNormalized(0.5, 1); // bottom-center: feet on the ground
spr.setPos(100, 50);             // feet at (100, 50)
spr.setScale(2, 2);              // grows up and out; feet stay put

spr.setOriginCentered();         // same as setOriginNormalized(0.5, 0.5)
spr.setOrigin(3, 12);            // an exact pixel of the frame, e.g. a hand
```

`setOrigin` keeps `pos()` where it was and shifts the image so the new origin lands on it.

### Animated Actors

An `Actor` owns the `Sprite` it animates and plays named states (each a `FrameSequence`) on it. Move, scale, and draw it through `actor.sprite`:

```zig
// During App.init (the actor takes ownership of the sprite):
self.hero = Actor.init(alloc, try eng.resources.createSprite("player_right_1"));
_ = try self.hero.addState(seqMgr.getState("walk_right").?, .{}); // first state applies its first frame
self.hero.sprite.setOriginNormalized(0.5, 1);

// In update:
self.hero.setState("walk_right"); // no-op if already in it; otherwise shows frame 0 now
self.hero.update(delta);
self.hero.sprite.setPosF(x, y);

// In render:
eng.renderer.drawSprite(&self.hero.sprite);

// During App.deinit (also releases the sprite):
self.hero.deinit();
```

Frames may come from different textures; applying a frame switches the sprite's texture as needed.

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
eng.renderer.drawTexture(self.tex, dest, src);
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

`reacquire` atomically upgrades to the latest generation and releases the old handle. In release builds, `dirty` is always false and `reacquire` is a no-op. Until you reacquire, a stale handle keeps drawing the old image: atlas frames and subtextures hold a reference to their image, so a reload doesn't delete the GL texture out from under them.

`reacquire` is for owned handles. A borrowed handle can't be reacquired (it holds no reference to hand back); call `getTexture(name)` again to pick up the new generation. In debug builds, superseded texture generations are kept until the resource manager deinits, so a borrowed handle you kept in a struct still points at valid (stale) data after a reload. Release builds reclaim an unreferenced older generation as soon as the same name is loaded again, so don't hold a borrowed handle across an explicit re-load there.

When the resource manager deinits with a handle still referenced, the log names it, e.g. `Texture 'player_right_1' (generation 1): refCount = 1 on deinit`.

## Text and Fonts

Text rendering is on by default (`rendererOpts.textRendering = true`). Setting it to false compiles the text path out, along with the embedded font bytes; calling `drawString` and friends then is a compile error that names the flag.

The renderer keeps one default font, set through `renderInitOpts.font`. Out of the box that is `.embedded`: the font `buildGame` compiled into the executable, which is Karla-Regular at 20px unless the build's `default_font` names another file (see [Getting Started](getting-started.html)). `drawString` works with no font setup at all.

```zig
// The embedded font at a different size.
.renderInitOpts = .{ .font = .{ .embedded = .{ .size = 16.0 } } },
```

To use a different font at runtime, load it from a file:

```zig
const appRunner = try AppRunner.init("My Game", alloc, .{
    .renderInitOpts = .{ .font = .{ .path = .{
        .face = "assets/AmigaTopaz.ttf",
        .size = 18.0,
        .face_index = 0, // face inside a .ttc collection; 0 for a plain file
    } } },
});
```

`font` is a `FontSource`:

- `.embedded` -- the build's embedded font (the default). If the build set `default_font = .none`, nothing is loaded and a debug build logs a warning.
- `.path` -- a font file, as above. An app that reads its font from a Lua config just fills this struct from those values.
- `.data` -- font bytes already in memory, e.g. `.{ .data = .{ .bytes = @embedFile("MyFont.ttf"), .size = 18.0 } }`.
- `.id` -- a font already loaded elsewhere (e.g. a manifest boot group).
- `.none` -- start with no default font, for a game that only draws bitmap fonts or sets its font later with `renderer.setDefaultFont`.

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

Calling a shape or text draw function when the corresponding option is compiled out is a compile error that names the flag.

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
    alloc: std.mem.Allocator,
    tex: *pixzig.TextureHandle, // borrowed: never released

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);
        app.* = .{
            .alloc = alloc,
            .tex = try eng.resources.loadTexture("tiles", "assets/mario_grassish2.png"),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        self.alloc.destroy(self);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 0, 0.2, 1);
        eng.renderer.begin(eng.projection());

        eng.renderer.drawTexture(self.tex, RectF.fromPosSize(10, 10, 32, 32),
                                 RectF.fromCoords(32, 32, 32, 32, 512, 512));

        // Drawn after the texture, so the outline sits on top of it.
        eng.renderer.drawRect(RectF.fromPosSize(10, 10, 32, 32),
                              Color.from(255, 255, 0, 200), 2);

        eng.renderer.end();
    }
};
```
