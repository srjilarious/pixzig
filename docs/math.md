# Math and Gameplay Helpers

Small building blocks most games need: vector math on `Vec2F`, a seeded random source, easing curves, and a repeating timer.

## Vec2F

`Vec2F` methods take and return values, so they chain left to right:

```zig
const Vec2F = pixzig.Vec2F;

self.vel = self.vel.add(thrust.scale(dt));
self.pos = self.pos.add(self.vel.scale(dt));

const toPlayer = player.pos.sub(self.pos);
if (toPlayer.lengthSq() < range * range) {
    self.heading = toPlayer.normalize();
}
```

| Method | Result |
|---|---|
| `add(b)`, `sub(b)` | Component-wise sum / difference |
| `scale(s)` | Both components times `s` |
| `mul(b)` | Component-wise product |
| `neg()` | Flipped direction |
| `dot(b)` | Dot product |
| `cross(b)` | z of the 3D cross product: positive when `b` is clockwise from the vector on screen |
| `length()`, `lengthSq()` | Length, and its square (cheaper for comparisons) |
| `distance(b)` | Distance between two points |
| `normalize()` | Unit vector; a zero vector stays zero |
| `lerp(b, t)` | Linear interpolation, `t` unclamped |
| `rotate(radians)` | Rotated around the origin |
| `angle()` | Direction in radians, in (-pi, pi] |
| `Vec2F.fromAngle(radians)` | Unit vector pointing at an angle |
| `Vec2F.zero`, `Vec2F.one` | Constants |

Angles are radians measured from +x toward +y. Since y grows down on screen, positive angles turn clockwise, the same way `Camera2D.rotation` does.

## Random numbers

The engine owns a seeded `pixzig.Rng` as `eng.rng`. Draw gameplay randomness from it rather than from your own generator: with a fixed seed, the same inputs replay the same game, which is what replays, bug repros and lockstep networking depend on.

```zig
const runner = try AppRunner.init("Game", alloc, .{ .rngSeed = 1234 });
```

`rngSeed` defaults to null, which seeds from the clock so every run differs.

| Method | Result |
|---|---|
| `float()` | f32 in [0, 1) |
| `floatRange(min, max)` | f32 in [min, max) |
| `intRange(T, min, max)` | Integer in [min, max], both ends included |
| `chance(p)` | True with probability `p` |
| `pick(T, items)` | Random element, or null for an empty slice |
| `direction()` | Random unit `Vec2F` |
| `reseed(seed)` | Restart the sequence |
| `random()` | The `std.Random` interface, for `shuffle` and the rest of std's helpers |

```zig
const spread = eng.rng.floatRange(-0.2, 0.2);
const bullet = heading.rotate(spread).scale(speed);
if (eng.rng.chance(0.1)) self.dropPowerUp();
```

A game that needs separate streams (say, level generation apart from combat) can create its own `pixzig.Rng.init(seed)`.

## Easing

`pixzig.Ease` maps progress `t` in [0, 1] to an eased value from 0 to 1; `t` is clamped first. `_in` curves start slow, `_out` curves end slow, `_in_out` do both. `back_*` and `elastic_out` overshoot before settling.

`linear`, `quad_in`, `quad_out`, `quad_in_out`, `cubic_in`, `cubic_out`, `cubic_in_out`, `sine_in`, `sine_out`, `sine_in_out`, `back_in`, `back_out`, `elastic_out`, `bounce_out`.

```zig
const t = self.elapsedMs / 400.0;
const y = pixzig.easing.tween(.bounce_out, startY, floorY, @floatCast(t));
```

In a sequence, `MoveToStep.initEased` and `TweenStep` take an `Ease`, and Lua's `seq_move_to` takes the curve's name as an optional sixth argument. See [Sequences](sequences.md).

## Timer

`pixzig.utils.Timer(T)` fires once every `period` units of whatever you feed it: milliseconds as `f64`, or ticks as an integer.

```zig
spawn: pixzig.utils.Timer(f64) = .{ .period = 500 },

pub fn update(self: *App, eng: *AppRunner.Engine, deltaMs: f64) bool {
    if (self.spawn.update(deltaMs)) self.spawnEnemy();
    ...
}
```

`update` returns true once `elapsed` reaches `period`, and carries the overshoot into the next period so uneven steps still average out to the right rate. `reset()` starts the period over, and `progress()` gives how far through it the timer is in [0, 1], ready to pass to an `Ease`.
