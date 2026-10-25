# Math and Gameplay Helpers

The small building blocks most games need: points, rects and colors, vector math, a seeded random source, easing curves, a repeating timer and an FPS counter.

## Points, Rects and Colors

| Type | What it is |
|---|---|
| `Vec2F`, `Vec2I`, `Vec2U` | A 2D point or size: `.{ .x = 1, .y = 2 }`. Convert with `asVec2F()`, `asVec2I()` and so on. |
| `RectF` | A float rect stored as edges: `l`, `t`, `r`, `b`. |
| `RectI` | The same with integers. |
| `Color` | RGBA floats from 0 to 1. |
| `Color8` | RGBA bytes from 0 to 255, for pixel data. |

Rects are stored as edges, not as position and size, so build them with a helper:

```zig
const box = RectF.fromPosSize(10, 20, 32, 16);       // x, y, w, h as f32
const hit = RectF.fromPosSizeV(self.pos, size);      // from two Vec2Fs
const region = RectI.init(32, 32, 16, 16);            // x, y, w, h

box.width();       // 32
box.centerF();     // .{ .x = 26, .y = 28 }
box.intersects(&other);
box.contains(mousePos); // left/top edges inside, right/bottom outside
```

`RectF.fromCoords(x, y, w, h, texW, texH)` turns a pixel region of a texture into UV coordinates; it takes integers since those are texture pixels.

Colors come from constants, bytes, or a hex literal:

```zig
Color.white, Color.black, Color.transparent, Color.red // also green, blue, yellow, cyan, magenta, gray
Color.rgb(255, 128, 0)          // opaque
Color.from(255, 128, 0, 128)    // with alpha
Color.hex(0xff8000ff)           // 0xRRGGBBAA
Color.red.withAlpha(0.5)
Color.black.lerp(Color.white, t)
```

## Vec2F Math

`Vec2F` methods take and return values, so they chain left to right:

```zig
self.vel = self.vel.add(thrust.scale(dt));
self.pos = self.pos.add(self.vel.scale(dt));

const toPlayer = player.pos.sub(self.pos);
if (toPlayer.lengthSq() < range * range) {
    self.heading = toPlayer.normalize();
}
```

| Method | Result |
|---|---|
| `add(b)`, `sub(b)` | Sum and difference. |
| `scale(s)` | Both components times `s`. |
| `mul(b)` | Component-wise product. |
| `neg()` | The opposite direction. |
| `dot(b)` | Dot product. |
| `cross(b)` | The z of the 3D cross product: positive when `b` is clockwise from the vector on screen. |
| `length()`, `lengthSq()` | Length, and its square (cheaper for comparisons). |
| `distance(b)` | Distance between two points. |
| `normalize()` | Unit vector. A zero vector stays zero. |
| `lerp(b, t)` | Linear interpolation. `t` isn't clamped. |
| `rotate(radians)` | Rotated around the origin. |
| `angle()` | Direction in radians, in (-pi, pi]. |
| `Vec2F.fromAngle(radians)` | A unit vector pointing at an angle. |
| `Vec2F.zero`, `Vec2F.one` | Constants. |

Angles are radians measured from +x toward +y. Since y grows downward on screen, positive angles turn clockwise, the same way `Camera2D.rotation` does.

For matrices, pixzig re-exports [zmath](https://github.com/zig-gamedev/zmath) as `pixzig.zmath`.

## Random Numbers

The engine has a seeded random source, `eng.rng`. Draw gameplay randomness from it rather than from your own generator. With a fixed seed, the same inputs replay the same game, which is what replays, bug reports and lockstep networking depend on.

```zig
const runner = try AppRunner.init("Game", alloc, .{ .rngSeed = 1234 });
```

`rngSeed` defaults to null, which seeds from the clock so every run differs.

| Method | Result |
|---|---|
| `float()` | f32 in [0, 1). |
| `floatRange(min, max)` | f32 in [min, max). |
| `intRange(T, min, max)` | An integer in [min, max], both ends included. |
| `chance(p)` | True with probability `p`. |
| `pick(T, items)` | A random element, or null for an empty slice. |
| `direction()` | A random unit `Vec2F`. |
| `reseed(seed)` | Restart the sequence. |
| `random()` | The `std.Random` interface, for `shuffle` and the rest of std's helpers. |

```zig
const spread = eng.rng.floatRange(-0.2, 0.2);
const bullet = heading.rotate(spread).scale(speed);
if (eng.rng.chance(0.1)) self.dropPowerUp();
```

For separate streams, say level generation apart from combat, create your own `pixzig.Rng.init(seed)`.

## Easing

`pixzig.Ease` maps progress `t` from 0 to 1 onto an eased value from 0 to 1. `t` is clamped first. `_in` curves start slow, `_out` curves end slow, and `_in_out` curves do both. `back_*` and `elastic_out` overshoot before settling.

The curves are `linear`, `quad_in`, `quad_out`, `quad_in_out`, `cubic_in`, `cubic_out`, `cubic_in_out`, `sine_in`, `sine_out`, `sine_in_out`, `back_in`, `back_out`, `elastic_out` and `bounce_out`.

```zig
const t: f32 = @floatCast(self.elapsedMs / 400.0);
const y = pixzig.easing.tween(.bounce_out, startY, floorY, t);
```

The [sequencer](page:sequences) uses these too: `MoveToStep.initEased` and `TweenStep` take an `Ease`, and Lua's `seq_move_to` takes a curve name.

## Timer

`pixzig.utils.Timer(T)` fires once every `period` units of whatever you feed it, like milliseconds as `f64` or ticks as an integer:

```zig
// In App:
spawnTimer: pixzig.utils.Timer(f64) = .{ .period = 500 },

// In update:
if (self.spawnTimer.update(deltaMs)) self.spawnEnemy();
```

`update` returns true once `elapsed` reaches `period`, and carries the extra time into the next period so it keeps a steady rate. `reset()` starts the period over. `progress()` says how far through the period it is, from 0 to 1, ready to pass to an `Ease`.

## FPS Counter

`pixzig.utils.FpsCounter` counts rendered frames per second:

```zig
// In App:
fps: pixzig.utils.FpsCounter = pixzig.utils.FpsCounter.init(),

// In update:
if (self.fps.update(deltaMs)) std.log.info("FPS: {}", .{self.fps.fps()});

// In render:
self.fps.renderTick();
```

`update` returns true once a second, when `fps()` has a new value.
