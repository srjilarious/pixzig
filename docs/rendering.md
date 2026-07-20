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

`Sprite.create` takes a `*TextureHandle` and a size in logical pixels:

```zig
var spr = pixzig.sprites.Sprite.create(self.player_tex, .{ .x = 16, .y = 16 });
spr.setPos(100, 50);
eng.renderer.drawSprite(&spr);
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
