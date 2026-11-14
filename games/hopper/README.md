# Hopper

A one-level platformer made to be copied: run, jump, stomp the beetles,
grab the coins and reach the flag. It comes twice, in Zig (`src/`) and in
Python (`python/hopper.py`), sharing one `assets/` folder and one
`manifest.json` that lists what's in it.

```sh
# From the pixzig checkout:
just hopper              # the Zig version
just py_install          # once, for the Python version
just py_hopper
```

pixzig's own build compiles hopper too (`zig build hopper` from the
checkout's root), so an engine change that breaks it shows up there and in
CI.

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
| Which files the game loads | `manifest.json` (both versions read it) |
| The level | `assets/level1.tmx` in [Tiled](https://www.mapeditor.org/) |
| The art | the ASCII sprites and tile painters in `tools/gen_art.py`, then `python3 tools/gen_art.py` (or draw over the PNG) |
| How the frog or the beetles move | `src/player.zig`, `src/walker.zig` (`python/player.py`, `python/walker.py`) |
| What happens when things meet: stomping, coins, the goal, lives | `src/play.zig` / `python/play.py` |
| Screens and text | `src/screens.zig` / `python/screens.py` |
| Controls | `src/controls.zig` / `python/controls.py` |

### The level

`level1.tmx` has three layers:

- **Background**: drawn only (clouds, bushes, the flag pole).
- **Main**: what the player stands on. Tiles 0-3 (grass, dirt, brick,
  crate) have the Tiled property `blocks = all`; give any tile that
  property to make it solid.
- **Spawns** (object layer): objects with the class `player_start`,
  `walker`, `coin`, and one `goal` rectangle that finishes the level.
  Spawns are tile-sized boxes; bodies stand on the box's bottom edge.

To add a second level, save it as `assets/level2.tmx`, add it to
`manifest.json` (an asset with the id `level2`, in the `boot` group), and
add `"level2"` to `order` in `src/level.zig` and `ORDER` in
`python/level.py`. Finishing the last level shows "LEVEL CLEAR!".

### The sprite sheet

`assets/hopper.png` is 8 columns of 16x16 cells; `src/sheet.zig` (and
`python/sheet.py`) name them. Sprites are drawn facing
right, and the frog is flipped (`Sprite.flip` / `set_flip`) to face left.

## How it fits together

The two versions match file for file: `src/player.zig` is
`python/player.py`, and so on. The docs' "Tutorial: Building Hopper" page
walks through them in order.

| File | What |
|---|---|
| `main.zig` / `hopper.py` | the App: engine setup, drawing sprites, switching screens with a state stack |
| `controls.zig` | the named actions and the keys and buttons bound to them |
| `play.zig` | the rules: stomping, coins, the goal, lives, the camera |
| `player.zig` | the frog: running and jumping |
| `walker.zig` | the beetles: walking back and forth |
| `coin.zig` | the coins |
| `level.zig` | the tile map, solid tiles, spawn points and the level order |
| `body.zig` | gravity and tile collision (the engine's tile mover) for everything that moves |
| `hud.zig` | the coins and lives counter |
| `screens.zig` | title, pause and messages; pause and messages are pushed over the frozen game |
| `config.zig` | reading `tuning.json` through the manifest |
| `sheet.zig` | where each sprite is, and the sky and shadow colours |

Movement runs at a fixed 120 ticks a second; drawing interpolates between
the last two ticks with `alpha`, so it stays smooth at any frame rate. Both
versions move bodies with the engine's tile mover (`tile.Mover` in Zig,
`TileMapRenderer.move_x`/`move_y` in Python), so they collide identically.
