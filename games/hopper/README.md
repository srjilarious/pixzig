# Hopper

A one-level platformer made to be copied: run, jump, stomp the beetles,
grab the coins and reach the flag. It comes twice, in Zig (`src/`) and in
Python (`python/hopper.py`), sharing one `assets/` folder.

```sh
# From the pixzig checkout:
just hopper              # the Zig version
just py_install          # once, for the Python version
just py_hopper
```

Controls: arrows or A/D move, Space/Up/W/Z jump (hold for higher), P
pauses, Esc backs out. A gamepad's d-pad, A, Start and Back work too.

## Make your own

```sh
zig build new -Dfrom=games/hopper -Dname=my_game -Ddest=../my_game
cd ../my_game && zig build my_game
```

That copies this folder, renames `hopper` to `my_game` everywhere (file
names included, so the sprite sheet becomes `assets/my_game.png`), and
points the copy at your pixzig checkout. Then change things in roughly this
order:

| To change | Edit |
|---|---|
| How it feels: run speed, jump height, gravity, lives | `assets/tuning.json` (both versions read it; no rebuild needed for Python) |
| The level | `assets/level1.tmx` in [Tiled](https://www.mapeditor.org/) |
| The art | the ASCII sprites and tile painters in `tools/gen_art.py`, then `python3 tools/gen_art.py` (or draw over the PNG) |
| What happens: enemies, pickups, rules | `src/play.zig` / the `Play` class in `python/hopper.py` |
| Screens and text | `src/screens.zig` / `Title`, `Paused`, `Message` |
| Controls | `bindControls` in `src/main.zig` / `bind_controls` |

### The level

`level1.tmx` has three layers:

- **Background**: drawn only (clouds, bushes, the flag pole).
- **Main**: what the player stands on. Tiles 0-3 (grass, dirt, brick,
  crate) have the Tiled property `blocks = all`; give any tile that
  property to make it solid.
- **Spawns** (object layer): objects with the class `player_start`,
  `walker`, `coin`, and one `goal` rectangle that finishes the level.
  Spawns are tile-sized boxes; bodies stand on the box's bottom edge.

To add a second level, save it as `assets/level2.tmx`, list it in
`build.zig`'s manifest and in `levels` in `src/play.zig` (and `LEVELS` in
the Python version). Finishing the last level shows "LEVEL CLEAR!".

### The sprite sheet

`assets/hopper.png` is 8 columns of 16x16 cells; `src/sheet.zig` (and the
constants near the top of `hopper.py`) name them. Left-facing frog frames
are the right-facing ones mirrored, 4 cells along, because pixzig sprites
can't flip yet.

## How it fits together

| Zig | Python | What |
|---|---|---|
| `main.zig` | `Hopper`, `bind_controls` | engine setup, controls, switching screens with a state stack |
| `play.zig` | `Play` | the level, player, walkers, coins, camera and HUD |
| `screens.zig` | `Title`, `Paused`, `Message` | the other screens; pause and messages are pushed over the frozen game |
| `body.zig` | `Body`, `Level` | gravity and tile collision for everything that moves |
| `config.zig` | `Tuning` | loading `tuning.json` |
| `sheet.zig` | constants | where each sprite is |

Movement runs at a fixed 120 ticks a second; drawing interpolates between
the last two ticks with `alpha`, so it stays smooth at any frame rate. The
Python `Body` does its own tile collision because pixzig's Python API has
no tile mover; the Zig one uses `tile.Mover`.
