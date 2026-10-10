# Rendering

Pixzig renders sprites, rectangles, and optional text. Submit drawing between `renderer.begin` and `renderer.end`.

## The Render Frame

```zig
pub fn render(self: *App, eng: *AppRunner.Engine) void {
    eng.renderer.clear(0, 0, 51, 255);

    eng.renderer.begin(.logical);
    // Issue draw calls.

    eng.renderer.end();
}
```

`clear` takes 0-255 RGBA values. `begin` takes the coordinate space to draw in:

| `begin(...)` | Space |
|---|---|
| `.logical` | The logical game resolution, y down. The usual choice. |
| `.screen` | Framebuffer pixels, y down. For debug overlays in physical pixels; the pass spans the whole framebuffer (letterbox bars included) and `end()` restores the game viewport. |
| `.{ .camera = &cam }` | World space seen through a `Camera2D`. Its `viewRect`, `worldToLogical` and `logicalToWorld` take `&eng.viewport` too, and account for `zoom` and `rotation`. |
| `.{ .matrix = m }` | Your own model-view-projection matrix. |

Draws appear in the order you submit them. Each kind of draw (plain sprites and textures, tinted sprites, filled sprites, shapes, text, colored text) queues into its own batch; switching to a different kind flushes the previous batch first, and `end` flushes whatever is left. Consecutive draws of the same kind and texture still go out as one GL call, so when order doesn't matter, grouping similar draws keeps the call count down.

Sprites keep float positions so slow movement accumulates smoothly, but `drawSprite` snaps a sprite's top-left to a whole pixel, so a sprite between pixels never draws blurry. The other draw calls take integer positions (`drawString`) or whole-pixel rects.

`renderer.setClip(rect)` clips later draws to a rect in logical coordinates, and `setClip(null)` restores the viewport's clip. It flushes queued draws first, so they keep the clip they were submitted under. Call `renderer.flush()` yourself before changing any other GL state mid-pass.

## Loading Textures

Every texture loader (`loadTexture`, `loadTextureFromBuffer`, `createTextureImageFromChars`, `addSubTexture`) and `getTexture(name)` returns a `*TextureHandle`. A handle points at the resource manager's slot for that name: keep it, draw with it, and never free it. It stays valid until the resource manager deinits, and a reload of the same name updates it in place (see [Hot Reload](#hot-reload)).

```zig
// During App.init -- nothing to free later:
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

`loadAtlas` reads matching `.json` and `.png` files. Each named frame in the JSON becomes its own texture entry. Look up individual frames by their frame name:

```zig
_ = try eng.resources.loadAtlas("assets/pac-tiles");
self.player_tex = try eng.resources.getTexture("player_right_1");
```

`loadAtlasNamed` lets the resource id differ from the filename:

```zig
_ = try eng.resources.loadAtlasNamed("main_sprites", "assets/pac-tiles");
```

## Drawing Sprites

`eng.resources.createSprite(name)` builds a sprite from any loaded texture, atlas frame, or subtexture, sized to that frame. `Sprite.create(handle)` does the same from a handle. A sprite owns nothing, so there is no `deinit`.

```zig
// During App.init:
self.spr = try eng.resources.createSprite("player_right_1");
self.spr.setPosF(100.5, 50);  // or setPos(i32, i32)
self.spr.setScale(2, 2);      // relative to the frame size
self.spr.tint = .{ .r = 1, .g = 0.4, .b = 0.4, .a = 1 }; // null = untinted

// Each frame:
eng.renderer.drawSprite(&self.spr);
```

Set `fill` to draw the sprite as a flat silhouette of its own shape: the texture's rgb is replaced by the fill color (blended by `fill.a`, 1 = solid) while its alpha is kept. That's the classic hit flash. `fill` takes precedence over `tint`; `eng.renderer.drawSpriteFilled(&spr, color)` does the same for a single draw.

```zig
self.spr.fill = .{ .r = 1, .g = 1, .b = 1, .a = 1 }; // solid white silhouette
self.spr.fill = null;                                 // back to normal
```

`setPos`, `setPosF`, `setSize`, `setScale`, and `setOrigin` keep `dest` and `size` in sync; writing `dest` directly skips that. `setSrcRect(RectI)` draws a sub-region of the frame, in pixels. `setTexture(handle)` switches the texture.

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
// During App.init:
self.hero = Actor.init(alloc, try eng.resources.createSprite("player_right_1"));
_ = try self.hero.addState(seqMgr.getState("walk_right").?, .{}); // first state applies its first frame
self.hero.sprite.setOriginNormalized(0.5, 1);

// In update:
try self.hero.setState("walk_right", .{}); // no-op if already in it; otherwise shows frame 0 now
self.hero.update(delta);
self.hero.sprite.setPosF(x, y);

// In render:
eng.renderer.drawSprite(&self.hero.sprite);

// During App.deinit (frees the actor's state table):
self.hero.deinit();
```

Frames may come from different textures; applying a frame switches the sprite's texture as needed.

An `ActorState` is shared data: `addState` keeps a pointer to it, not a copy, so any number of actors can use one state, and the state must outlive them. Register states with a `FrameSequenceManager` (`addState`, or a sequence JSON file) and pass `getState(name)`; re-adding a name there updates the state in place, so actors see the change. `addState`'s `.name` option gives the state a different name on this actor, e.g. `.{ .name = "left" }` for a shared `"red_left"` state.

Frames and states flip with `flipX`/`flipY`. A state's flip is applied on top of each frame's own, and two flips on the same axis cancel. Sequence JSON files keep the `"flip": "none" | "horz" | "vert" | "both"` field.

`setState` returns `error.UnknownActorState` for a name that was never added.

#### Play-once states

A sequence's `mode` is `.loop` (the default) or `.once`. A `.once` sequence plays through one time. When it ends, the actor switches to the state's `nextState`. With no `nextState`, it holds the last frame and `actor.finished()` returns true until the state changes. `.loop` sequences ignore `nextState`.

```zig
// "attack" plays once, then drops back to "idle".
try seqMgr.addState(.{ .name = "attack", .nextState = "idle", .sequence = attackSeq });
_ = try self.hero.addState(seqMgr.getState("attack").?, .{});

// In update, when the attack button is pressed:
try self.hero.setState("attack", .{});
```

`setState` on the state the actor is already in is a no-op, even after a `.once` state has finished. Pass `.{ .reset = true }` to restart it from frame 0 instead, e.g. to replay an attack:

```zig
try self.hero.setState("attack", .{ .reset = true });
``` In a sequence JSON file, set `"mode": "once"` on the sequence and `"nextStateName"` on the state.

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

In debug builds, the resource manager watches texture, atlas, font, and tilemap files for changes. When a file changes, it reloads the asset **in place**: the handle you already hold now holds the new value, and the old one is freed. Sprites, actors, the text renderer and tile renderers all draw the new asset on their next draw with no code of yours. Loading the same name again yourself does the same thing in any build mode.

A reloaded image is re-uploaded into the same GL texture, so its atlas frames and subtextures keep working. A frame that disappears from an atlas's JSON keeps its last value rather than being removed, so a handle to it never dangles.

Each handle has a `version` that goes up by one on every reload. If you derived something from an asset (a mesh built from a map, positions read from it), keep the version you built from and rebuild when it changes:

```zig
if (self.map.version != self.mapVersion) {
    self.mapVersion = self.map.version;
    self.rebuildSpawns();
}
```

A `TileMapRenderer` does this for you: it rebuilds its layers on the next render call after a reload (see [Tile Rendering](tile-rendering.md#hot-reload)). Reloads happen in `checkHotReload`, between frames, never inside a `begin`/`end` pass.

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
        .faceIndex = 0, // face inside a .ttc collection; 0 for a plain file
    } } },
});
```

`font` is a `FontSource`:

- `.embedded` -- the build's embedded font (the default). If the build set `default_font = .none`, nothing is loaded and a debug build logs a warning.
- `.path` -- a font file, as above. An app that reads its font from a Lua config just fills this struct from those values.
- `.data` -- font bytes already in memory, e.g. `.{ .data = .{ .bytes = @embedFile("MyFont.ttf"), .size = 18.0 } }`.
- `.id` -- a font already loaded elsewhere (e.g. a manifest boot group).
- `.none` -- start with no default font, for a game that only draws bitmap fonts or sets its font later with `renderer.setDefaultFont`.

Draw with `drawString`, `drawStringColored`, or `drawScaledString` between `begin` and `end`. Add extra coverage for codepoints the primary face lacks with `eng.renderer.addDefaultFontFallback(&eng.resources, path, faceIndex)`.

### Changing font size at runtime

`eng.defaultFontAtlas()` returns a `?*FontAtlas` -- the live atlas the renderer draws from. `FontAtlas.setFontSize(px)` repacks it in place at a new pixel size: every face (primary and fallbacks) is rescaled and the glyphs are re-rasterized on the same GL texture, so the next `drawString` uses the new size with no other bookkeeping.

```zig
pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
    const kb = &eng.inputs.keyboard;
    if (kb.ctrl()) {
        if (eng.defaultFontAtlas()) |fa| {
            if (kb.pressed(.minus)) fa.setFontSize(@max(8, fa.fontSize - 2)) catch {};
            if (kb.pressed(.equal)) fa.setFontSize(@min(72, fa.fontSize + 2)) catch {}; // Shift+= is '+'
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
const AppRunner = pixzig.AppRunner(App, .{
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

Draw with `renderer.begin(.logical)`. With `.integer_fit`, the logical grid is scaled to the largest integer multiple that fits, and the remainder is letterboxed.

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
        eng.renderer.clear(0, 0, 51, 255);
        eng.renderer.begin(.logical);

        eng.renderer.drawTexture(self.tex, RectF.fromPosSize(10, 10, 32, 32),
                                 RectF.fromCoords(32, 32, 32, 32, 512, 512));

        // Drawn after the texture, so the outline sits on top of it.
        eng.renderer.drawRect(RectF.fromPosSize(10, 10, 32, 32),
                              Color.from(255, 255, 0, 200), 2);

        eng.renderer.end();
    }
};
```
