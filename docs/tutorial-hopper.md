# Tutorial: Building Hopper

This tutorial builds a small platformer from an empty window up to a finished game: run, jump, stomp the beetles, grab the coins and reach the flag. The finished game is `games/hopper` in the pixzig repo. Each step below adds one piece of it, shows the code, and says which engine page covers that system in more depth.

Hopper comes in Zig and in Python, and the two versions mirror each other file for file. Code samples have **Zig** and **Python** tabs; pick one and every sample switches to it.

To play the finished game first:

```sh
# From the pixzig checkout:
just hopper              # the Zig version
just py_install          # once, for the Python version
just py_hopper
```

Arrows or A/D move, Space jumps (hold it for a higher jump), P pauses and Esc backs out.

## The Plan

Before writing code, decide where things will live. A game's main file tends to collect everything: setup, controls, the player, the enemies, the HUD. It stays readable for a few hundred lines and then stops being readable. Hopper avoids that by giving every *thing* in the game its own file from the start, the same way larger pixzig games like remzman do:

| Zig | Python | What it holds |
|---|---|---|
| `main.zig` | `hopper.py` | The App: engine setup, drawing sprites, switching screens |
| `controls.zig` | `controls.py` | The named actions and the keys bound to them |
| `config.zig` | `config.py` | Gameplay numbers, read from `assets/tuning.json` |
| `sheet.zig` | `sheet.py` | Where each sprite is in `assets/hopper.png` |
| `level.zig` | `level.py` | The tile map, solid tiles and spawn points |
| `body.zig` | `body.py` | Falling and bumping into tiles, shared by everything that moves |
| `player.zig` | `player.py` | The frog: running and jumping |
| `walker.zig` | `walker.py` | The beetles: walking back and forth |
| `coin.zig` | `coin.py` | The coins |
| `hud.zig` | `hud.py` | The coins and lives counter |
| `play.zig` | `play.py` | The rules: stomping, collecting, the goal, lives, the camera |
| `screens.zig` | `screens.py` | Title, pause, and level clear / game over |

Two rules decide what goes where:

- **An entity's file owns how it behaves.** `player.zig` knows how the frog runs and jumps; `walker.zig` knows how a beetle walks. Neither knows the other exists.
- **`play.zig` owns how entities interact.** Stomping a beetle, picking up a coin and touching the flag involve two things at once, so they live in the file that holds both. That file reads like the game's rule book.

The rest of this tutorial builds the files roughly in the order above.

## Step 1: A Window

Start from a copy of pixzig's template (see [Getting Started](page:getting-started)), or from hopper itself:

```sh
zig build new -Dfrom=games/hopper -Dname=my_game -Ddest=../my_game
```

`build.zig` uses `buildGame`, which compiles `src/main.zig` and adds a `zig build hopper` step that runs it:

```zig
const pixzig_dep = b.dependency("pixzig", .{ .target = target, .build_examples = false });
const manifest = pixzig_build.manifestFromFile(b, "manifest.json");

_ = pixzig_build.buildGame(b, .{
    .target = target,
    .optimize = optimize,
    .engine_dep = pixzig_dep,
    .name = "hopper",
    .root_source_file = b.path("src/main.zig"),
    .manifest = manifest,
});
```

Hopper is pixel art, so it lays everything out on a small 320x180 screen and lets the engine scale that up by whole pixels to fill the window. Nothing in the game ever thinks about the real window size:

=== "Zig"

    ```zig
    pub fn main(init: std.process.Init) !void {
        const appRunner = try AppRunner.init("Hopper", init.gpa, .{
            .windowSize = .{ .x = 960, .y = 540 },
            .logicalSize = .{ .x = 320, .y = 180 },
            .scalePolicy = .integer_fit,
        });
        defer appRunner.deinit();

        const app = try App.init(init.gpa, appRunner.engine);
        defer app.deinit();

        appRunner.run(app);
    }
    ```

=== "Python"

    ```python
    class Hopper(App):
        def __init__(self):
            super().__init__(
                "Hopper",
                width=960,
                height=540,
                logical_size=(320, 180),
                scale_policy=ScalePolicy.INTEGER_FIT,
                asset_root=GAME_ROOT,
            )

    if __name__ == "__main__":
        Hopper().run()
    ```

The App has an `update` and a `render`. `update` runs at a fixed 120 ticks a second, so movement code can use a constant step. `render` runs once per displayed frame and gets an `alpha` that says how far the frame falls between the last two ticks; Step 6 uses it. [The Game Loop](page:app-runner) explains the timing and [Viewport and Cameras](page:viewport) the scale policies.

## Step 2: Assets and the Sprite Sheet

Every file the game loads is listed once, in `manifest.json`. Both versions read it, so they always load the same things:

```json
{
  "version": 1,
  "root": "assets",
  "groups": {
    "boot": ["hopper", "level1", "tuning"]
  },
  "assets": [
    { "id": "hopper", "kind": "texture", "path": "hopper.png" },
    { "id": "level1", "kind": "tilemap", "path": "level1.tmx" },
    { "id": "tuning", "kind": "raw", "path": "tuning.json" }
  ]
}
```

The `boot` group loads before the App starts. In Zig, passing the manifest to the engine through `manifestOpts` does that; in Python, opening it with `load_manifest` does. After that, game code refers to assets by id (`"hopper"`, `"level1"`), never by path. See [Assets](page:assets).

`assets/hopper.png` is one image holding every tile and sprite, in 16x16 cells, eight to a row. `sheet.zig` gives the cells names and turns a cell number into a source rectangle:

=== "Zig"

    ```zig
    pub const FrogIdle = 8;
    pub const FrogRun1 = 9;
    pub const FrogRun2 = 10;
    pub const FrogJump = 11;
    // ...

    pub fn rect(index: usize) RectI {
        const col: i32 = @intCast(index % Columns);
        const row: i32 = @intCast(index / Columns);
        return RectI.init(col * Size, row * Size, Size, Size);
    }
    ```

=== "Python"

    ```python
    FROG_IDLE, FROG_RUN1, FROG_RUN2, FROG_JUMP = 8, 9, 10, 11
    # ...

    def rect(index):
        return ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL, CELL, CELL)
    ```

The App keeps a single sprite over the sheet and points it at a different cell for each thing it draws. Everything in hopper is drawn through this one method:

=== "Zig"

    ```zig
    /// Draws a sheet cell with its top-left at (x, y), mirrored by `flip`.
    pub fn drawCell(self: *App, cell: usize, x: f32, y: f32, flip: Flip) void {
        self.cell_sprite.setSrcRect(sheet.rect(cell));
        self.cell_sprite.flip = flip;
        self.cell_sprite.setPosF(x, y);
        self.eng.renderer.drawSprite(&self.cell_sprite);
    }
    ```

=== "Python"

    ```python
    def draw_cell(self, cell, x, y, flip=Flip.NONE):
        s = self.cell_sprite
        s.set_src_rect(*sheet.rect(cell))
        s.set_flip(flip)
        s.set_pos(x, y)
        s.draw()
    ```

The art faces right. To face left, the sprite is drawn flipped rather than needing a second copy of every frame. [Rendering](page:rendering) covers sprites and the renderer.

## Step 3: Controls

Game code never asks whether the space bar is down. It asks whether *jump* is down, and `controls.zig` decides which keys and gamepad buttons mean jump:

=== "Zig"

    ```zig
    pub const Action = enum { left, right, jump, confirm, pause, back };

    pub fn bind(eng: *Engine) !void {
        const a = eng.actions;
        try a.bind(.left, .{ .key = .left });
        try a.bind(.left, .{ .key = .a });
        try a.bind(.left, .{ .gamepad_button = .dpad_left });
        try a.bind(.jump, .{ .key = .space });
        try a.bind(.jump, .{ .gamepad_button = .a });
        // ...
    }
    ```

=== "Python"

    ```python
    BINDINGS = [
        ("left", [Key.LEFT, Key.A], [GamepadButton.DPAD_LEFT]),
        ("right", [Key.RIGHT, Key.D], [GamepadButton.DPAD_RIGHT]),
        ("jump", [Key.SPACE, Key.UP, Key.W, Key.Z], [GamepadButton.A]),
        # ...
    ]

    def bind(actions):
        for action, keys, buttons in BINDINGS:
            for key in keys:
                actions.bind_key(action, key)
            for button in buttons:
                actions.bind_gamepad_button(action, button)
    ```

In Zig, the `Action` enum is handed to the engine in `main.zig`, and `eng.actions` then answers `down(.jump)`, `pressed(.jump)` (this tick only) and `released(.jump)`:

```zig
const engine_options: pixzig.EngineOptions = .{
    .actionOpts = .{ .Action = controls.Action },
    .manifestOpts = manifest_options,
};
pub const Engine = pixzig.Engine(engine_options);
```

Adding a gamepad or remapping a key is now a change to one file. See [Input](page:input).

## Step 4: Tuning Numbers

How a platformer *feels* comes down to a dozen numbers: run speed, acceleration, gravity, jump height. Tuning them means trying a value, playing, and trying another, so hopper keeps them out of the code, in `assets/tuning.json`:

```json
{
  "run_speed": 95,
  "ground_accel": 900,
  "gravity": 1000,
  "jump_speed": 380,
  "jump_release_cut": 0.45,
  "coyote_ms": 90,
  "jump_buffer_ms": 110
}
```

`config.zig` declares the same fields with defaults, and loads the file through the manifest (which also works inside an Android APK):

=== "Zig"

    ```zig
    pub const Tuning = struct {
        run_speed: f32 = 95,
        ground_accel: f32 = 900,
        // ...
    };

    pub fn load(alloc: std.mem.Allocator, manifest: *const pixzig.AssetManifest, id: []const u8) !Tuning {
        const bytes = try manifest.readRaw(alloc, id);
        defer alloc.free(bytes);
        const parsed = try std.json.parseFromSlice(Tuning, alloc, bytes, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        return parsed.value;
    }
    ```

=== "Python"

    ```python
    @dataclass
    class Tuning:
        run_speed: float = 95
        ground_accel: float = 900
        # ...

        @classmethod
        def load(cls, manifest, asset_id):
            data = json.loads(manifest.read_raw(asset_id))
            known = {f.name for f in fields(cls)}
            return cls(**{k: v for k, v in data.items() if k in known})
    ```

The App loads it once, in `init`, and everything else reads `app.tuning`.

## Step 5: The Level

The level is drawn in [Tiled](https://www.mapeditor.org/) and saved as `assets/level1.tmx`, using `hopper.png` as its tileset. It has three layers:

- **Background**: only drawn (clouds, bushes, the flag pole).
- **Main**: what things stand on. The solid tiles have the Tiled property `blocks = all`, which the engine turns into a flag on the tile.
- **Spawns**: an object layer. Each object's class says what starts there: `player_start`, `walker`, `coin`, or the `goal` rectangle.

`level.zig` wraps the map so the rest of the game can ask simple questions: how big is it, is this pixel solid, where do things start?

=== "Zig"

    ```zig
    pub const Level = struct {
        map_renderer: tile.TileMapRenderer,

        pub fn init(alloc: std.mem.Allocator, res: *pixzig.ResourceManager, id: []const u8) !Level {
            return .{ .map_renderer = try tile.TileMapRenderer.init(alloc, res, id) };
        }

        pub fn mainLayer(self: *const Level) *tile.TileLayer { ... }
        pub fn width(self: *const Level) f32 { ... }
        pub fn height(self: *const Level) f32 { ... }

        /// Whether the tile under world pixel (x, y) is solid.
        pub fn solidAt(self: *const Level, x: f32, y: f32) bool {
            const layer = self.mainLayer();
            const tx: i32 = @intFromFloat(@floor(x / @as(f32, @floatFromInt(layer.tileSize.x))));
            const ty: i32 = @intFromFloat(@floor(y / @as(f32, @floatFromInt(layer.tileSize.y))));
            const t = layer.tile(tx, ty) orelse return false;
            return (t.core & tile.BlocksAll) != 0;
        }

        pub fn spawns(self: *const Level) ![]tile.Object { ... }

        pub fn render(self: *Level, camera: *const pixzig.Camera2D, viewport: *const pixzig.Viewport) void {
            self.map_renderer.render(camera, viewport);
        }
    };
    ```

=== "Python"

    ```python
    class Level:
        def __init__(self, app, map_id):
            self.map = app.create_tilemap_renderer(map_id)
            self.main = self.map.layer_index("Main")
            cols, rows = self.map.layer_size(self.main)
            tile_w, tile_h = self.map.tile_size(self.main)
            self.width = cols * tile_w
            self.height = rows * tile_h

        def solid_at(self, x, y):
            tx, ty = self.map.world_to_tile(self.main, x, y)
            return self.map.is_blocked(self.main, tx, ty)

        def spawns(self):
            return self.map.objects(self.map.object_group_index("Spawns"))

        def render(self, camera):
            self.map.render(camera)
    ```

Spawn objects are tile-sized boxes, but the frog's hitbox is 12x13 and a beetle's 14x11. `standOn` works out where a smaller body goes so it stands on the bottom of the box, centred across it:

=== "Zig"

    ```zig
    pub fn standOn(obj: *const tile.Object, w: f32, h: f32) Vec2F {
        const box = objectRect(obj);
        return .{ .x = box.l + (box.width() - w) / 2, .y = box.b - h };
    }
    ```

=== "Python"

    ```python
    def stand_on(obj, w, h):
        return (obj.x + (obj.w - w) / 2, obj.y + obj.h - h)
    ```

The list of levels, in play order, lives here too (`level.order` / `ORDER`). [Tile Maps](page:tile-rendering) covers loading and drawing maps.

## Step 6: A Body That Falls

The frog and the beetles move the same way: gravity pulls them down, they move by their velocity, and they stop against solid tiles. That shared part is `body.zig`, so neither entity has to repeat it.

A `Body` is a hitbox, a velocity, and whether it's standing on something. `step` moves it one tick, one axis at a time so it slides along walls and floors. The engine's tile mover does the actual collision:

=== "Zig"

    ```zig
    pub fn step(self: *Body, dt: f32, layer: *tile.TileLayer, tun: *const Tuning) Hits {
        self.prev = .{ .x = self.rect.l, .y = self.rect.t };
        self.vel.y = @min(self.vel.y + tun.gravity * dt, tun.max_fall_speed);

        var hits: Hits = .{};
        const dx = self.vel.x * dt;
        if (dx > 0) {
            hits.wall = tile.Mover.moveRight(&self.rect, dx, layer, tile.BlocksAll);
        } else if (dx < 0) {
            hits.wall = tile.Mover.moveLeft(&self.rect, -dx, layer, tile.BlocksAll);
        }
        if (hits.wall) self.vel.x = 0;

        const dy = self.vel.y * dt;
        if (dy > 0) {
            hits.floor = tile.Mover.moveDown(&self.rect, dy, layer, tile.BlocksAll);
        } else if (dy < 0) {
            hits.ceiling = tile.Mover.moveUp(&self.rect, -dy, layer, tile.BlocksAll);
        }
        if (hits.floor or hits.ceiling) self.vel.y = 0;
        self.on_ground = hits.floor;
        return hits;
    }
    ```

=== "Python"

    ```python
    def step(self, dt, level, tun):
        self.prev_x, self.prev_y = self.x, self.y
        self.vy = min(self.vy + tun.gravity * dt, tun.max_fall_speed)

        self.x, hit_wall = level.map.move_x(level.main, self.x, self.y, self.w, self.h, self.vx * dt)
        if hit_wall:
            self.vx = 0

        dy = self.vy * dt
        self.y, hit_y = level.map.move_y(level.main, self.x, self.y, self.w, self.h, dy)
        if hit_y:
            self.vy = 0
        self.on_ground = hit_y and dy > 0
        return hit_wall, self.on_ground
    ```

Note `prev`: before moving, the body remembers where it was. When drawing, `drawPos(alpha)` blends between the previous tick's position and this one's. Without that, movement looks slightly uneven whenever the 120 Hz tick and the monitor's refresh rate don't line up.

The App turns that into one more drawing helper. Hitboxes are smaller than the 16x16 cells, so a sprite is centred across its body with the bottoms lined up, which keeps feet on the ground:

=== "Zig"

    ```zig
    pub fn drawOnBody(self: *App, cell: usize, body: *const Body, alpha: f32, flip: Flip) void {
        const pos = body.drawPos(alpha);
        const x = pos.x + body.rect.width() / 2 - sheet.CellSize / 2;
        const y = pos.y + body.rect.height() - sheet.CellSize;
        self.drawCell(cell, x, y, flip);
    }
    ```

=== "Python"

    ```python
    def draw_on_body(self, cell, body, alpha, flip=Flip.NONE):
        x, y = body.draw_pos(alpha)
        self.draw_cell(cell, x + body.w / 2 - sheet.CELL / 2, y + body.h - sheet.CELL, flip)
    ```

See [Collision and Pathfinding](page:collision) for the tile mover and the other collision helpers.

## Step 7: The Player

`player.zig` holds a `Body` plus the few things only the frog cares about. Its `update` reads the controls and steers the body, then lets the body move.

Running eases toward full speed instead of jumping to it, and eases back to a stop on the ground. In the air there's no friction, so a jump keeps its momentum:

=== "Zig"

    ```zig
    var dir: f32 = 0;
    if (actions.down(.left)) dir -= 1;
    if (actions.down(.right)) dir += 1;
    if (dir != 0) {
        const accel = if (body.on_ground) tun.ground_accel else tun.air_accel;
        body.vel.x = approach(body.vel.x, dir * tun.run_speed, accel * dt);
        self.facing_left = dir < 0;
    } else if (body.on_ground) {
        body.vel.x = approach(body.vel.x, 0, tun.ground_friction * dt);
    }
    ```

=== "Python"

    ```python
    direction = (1 if actions.down("right") else 0) - (1 if actions.down("left") else 0)
    if direction != 0:
        accel = tun.ground_accel if body.on_ground else tun.air_accel
        body.vx = approach(body.vx, direction * tun.run_speed, accel * dt)
        self.facing_left = direction < 0
    elif body.on_ground:
        body.vx = approach(body.vx, 0, tun.ground_friction * dt)
    ```

Jumping uses two small timers that make the controls feel fair:

- **Coyote time**: a jump still works for a moment after running off a ledge.
- **Jump buffer**: a jump pressed just before landing happens on landing.

And letting go of jump while still rising cuts the upward speed, so a tap is a short hop and a hold is a full jump:

=== "Zig"

    ```zig
    self.coyote_ms = if (body.on_ground) tun.coyote_ms else self.coyote_ms - delta;
    self.jump_buffer_ms = if (actions.pressed(.jump)) tun.jump_buffer_ms else self.jump_buffer_ms - delta;
    if (self.jump_buffer_ms > 0 and self.coyote_ms > 0) {
        body.vel.y = -tun.jump_speed;
        self.jump_buffer_ms = 0;
        self.coyote_ms = 0;
    }
    if (actions.released(.jump) and body.vel.y < 0) body.vel.y *= tun.jump_release_cut;

    _ = body.step(dt, level.mainLayer(), tun);
    ```

=== "Python"

    ```python
    self.coyote_ms = tun.coyote_ms if body.on_ground else self.coyote_ms - dt_ms
    self.jump_buffer_ms = tun.jump_buffer_ms if actions.pressed("jump") else self.jump_buffer_ms - dt_ms
    if self.jump_buffer_ms > 0 and self.coyote_ms > 0:
        body.vy = -tun.jump_speed
        self.jump_buffer_ms = 0
        self.coyote_ms = 0
    if actions.released("jump") and body.vy < 0:
        body.vy *= tun.jump_release_cut

    body.step(dt, level, tun)
    ```

The player also picks its own animation frame from its state: in the air it's the jump frame, moving it alternates two run frames by distance travelled, and otherwise it's idle:

=== "Zig"

    ```zig
    pub fn cell(self: *const Player) usize {
        if (!self.body.on_ground) return sheet.FrogJump;
        if (@abs(self.body.vel.x) > 5) {
            return if (@mod(self.run_px, 16) < 8) sheet.FrogRun1 else sheet.FrogRun2;
        }
        return sheet.FrogIdle;
    }
    ```

=== "Python"

    ```python
    def cell(self):
        if not self.body.on_ground:
            return sheet.FROG_JUMP
        if abs(self.body.vx) > 5:
            return sheet.FROG_RUN1 if self.run_px % 16 < 8 else sheet.FROG_RUN2
        return sheet.FROG_IDLE
    ```

Choosing frames from state like this is enough for a three-frame frog. For longer animations, see [Sprites and Animation](page:animation).

## Step 8: Playing the Level

`play.zig` is where the pieces meet. `PlayState` owns the level, a camera, the player, the lists of walkers and coins, and the score. Its first job is setting a level up from the Spawns layer:

=== "Zig"

    ```zig
    fn restartLevel(self: *PlayState) !void {
        self.walkers.clearRetainingCapacity();
        self.coins.clearRetainingCapacity();
        self.player = .init(16, 16);
        self.dying_ms = 0;

        for (try self.level.spawns()) |*obj| {
            const class = obj.class orelse continue;
            if (std.mem.eql(u8, class, "player_start")) {
                const pos = levels.standOn(obj, player_mod.Width, player_mod.Height);
                self.player.body.teleport(pos.x, pos.y);
            } else if (std.mem.eql(u8, class, "walker")) {
                const pos = levels.standOn(obj, walker_mod.Width, walker_mod.Height);
                try self.walkers.append(self.alloc, .init(pos.x, pos.y));
            } else if (std.mem.eql(u8, class, "coin")) {
                const pos = levels.centreIn(obj, coin_mod.Size);
                try self.coins.append(self.alloc, .init(pos.x, pos.y));
            } else if (std.mem.eql(u8, class, "goal")) {
                self.goal = levels.objectRect(obj);
            }
        }

        self.camera.bounds = .{ .l = 0, .t = 0, .r = self.level.width(), .b = self.level.height() };
        self.camera.pos = self.player.body.rect.centerF();
    }
    ```

=== "Python"

    ```python
    def restart_level(self):
        self.walkers.clear()
        self.coins.clear()
        self.player = Player(16, 16)
        self.dying_ms = 0.0
        for obj in self.level.spawns():
            if obj.class_ == "player_start":
                self.player.body.teleport(*levels.stand_on(obj, player_mod.WIDTH, player_mod.HEIGHT))
            elif obj.class_ == "walker":
                self.walkers.append(Walker(*levels.stand_on(obj, walker_mod.WIDTH, walker_mod.HEIGHT)))
            elif obj.class_ == "coin":
                self.coins.append(Coin(*levels.centre_in(obj, coin_mod.SIZE)))
            elif obj.class_ == "goal":
                self.goal = levels.object_rect(obj)
        self.camera.set_bounds(0, 0, self.level.width, self.level.height)
        self.camera.set_pos(*self.player.body.center())
    ```

Each tick, it updates every entity, checks how they interact, and moves the camera. Each entity's own logic is one call, so `update` reads like a list of what happens:

=== "Zig"

    ```zig
    self.player.update(eng, self.tun(), &self.level, delta);
    for (self.walkers.items) |*w| w.update(self.tun(), &self.level, delta);

    self.checkWalkers();
    self.checkCoins();
    if (self.player.body.rect.intersects(&self.goal)) {
        self.finishLevel();
        return;
    }
    if (self.player.body.rect.t > self.level.height()) self.die();

    self.camera.follow(self.player.body.rect.centerF(), delta, .{
        .deadzone = .{ .x = self.tun().camera_deadzone_x, .y = 0 },
        .smoothing = self.tun().camera_smoothing,
    });
    ```

=== "Python"

    ```python
    self.player.update(actions, self.tun, self.level, dt_ms)
    for w in self.walkers:
        w.update(self.tun, self.level, dt_ms)

    self.check_walkers()
    self.check_coins()
    if self.player.body.overlaps(*self.goal):
        self.finish_level()
        return
    if self.player.body.y > self.level.height:
        self.die()

    cx, cy = self.player.body.center()
    self.camera.follow(cx, cy, dt_ms, deadzone=(self.tun.camera_deadzone_x, 0), smoothing=self.tun.camera_smoothing)
    ```

The camera follows the frog with a small dead zone (small moves don't scroll the screen) and smoothing (it catches up rather than snapping), and its bounds keep it from showing past the map's edges.

Drawing happens in two passes. The world draws through the camera; the HUD draws in screen space, so it stays in the corner:

=== "Zig"

    ```zig
    eng.renderer.clear(sheet.Sky[0], sheet.Sky[1], sheet.Sky[2], 255);
    self.level.render(&self.camera, &eng.viewport);

    eng.renderer.begin(.{ .camera = &self.camera });
    // ... coins and walkers ...
    const flip: Flip = if (self.player.facing_left) .horz else .none;
    app.drawOnBody(self.player.cell(), &self.player.body, alpha, flip);
    eng.renderer.end();

    hud.draw(eng, self.coins_collected, self.lives);
    ```

=== "Python"

    ```python
    app.render_begin(self.camera)
    self.level.render(self.camera)
    # ... coins and walkers ...
    flip = Flip.HORZ if self.player.facing_left else Flip.NONE
    app.draw_on_body(self.player.cell(), self.player.body, alpha, flip)
    app.render_end()

    hud.draw(app, self.coins_collected, self.lives)
    ```

At this point the frog runs and jumps around the level. See [Viewport and Cameras](page:viewport) for `Camera2D.follow` and [Text and Fonts](page:text) for `drawText`, which the HUD uses.

## Step 9: Beetles to Stomp

A beetle is another `Body` that walks back and forth. It turns around when it hits a wall, and (unless tuning says otherwise) when the ground ahead of it ends. To check for a drop, it asks the level whether the pixel just past its leading foot is solid:

=== "Zig"

    ```zig
    pub fn update(self: *Walker, tun: *const Tuning, level: *const Level, delta: f64) void {
        if (self.squashed_ms) |*ms| {
            ms.* -= delta;
            return;
        }
        const dt: f32 = @floatCast(delta / 1000.0);
        self.body.vel.x = self.dir * tun.walker_speed;
        const hits = self.body.step(dt, level.mainLayer(), tun);
        if (hits.wall) self.dir = -self.dir;

        if (tun.walkers_turn_at_ledges and self.body.on_ground) {
            const r = self.body.rect;
            const ahead_x = if (self.dir > 0) r.r + 1 else r.l - 1;
            if (!level.solidAt(ahead_x, r.b + 1)) self.dir = -self.dir;
        }
    }
    ```

=== "Python"

    ```python
    def update(self, tun, level, dt_ms):
        if self.squashed_ms is not None:
            self.squashed_ms -= dt_ms
            return
        self.body.vx = self.dir * tun.walker_speed
        hit_wall, _ = self.body.step(dt_ms / 1000.0, level, tun)
        if hit_wall:
            self.dir = -self.dir
        if tun.walkers_turn_at_ledges and self.body.on_ground:
            ahead_x = self.body.right + 1 if self.dir > 0 else self.body.x - 1
            if not level.solid_at(ahead_x, self.body.bottom + 1):
                self.dir = -self.dir
    ```

A stomped beetle stays on screen, squashed, for a moment before `PlayState` removes it (`isGone`).

Whether touching a beetle squashes it or costs a life depends on both the frog and the beetle, so that decision is in `play.zig`. The frog only answers the question about itself: was it coming down from above?

=== "Zig"

    ```zig
    // player.zig
    pub fn landedOn(self: *const Player, rect: *const RectF) bool {
        const was_above = self.body.prev.y + Height <= rect.t + 2;
        return self.body.vel.y > 0 and was_above;
    }

    // play.zig
    fn checkWalkers(self: *PlayState) void {
        const p = &self.player;
        for (self.walkers.items) |*w| {
            if (w.isSquashed()) continue;
            if (!p.body.rect.intersects(&w.body.rect)) continue;

            if (p.landedOn(&w.body.rect)) {
                w.squash(self.tun());
                p.bounce(self.app.eng.actions.down(.jump), self.tun());
            } else {
                self.die();
                return;
            }
        }
    }
    ```

=== "Python"

    ```python
    # player.py
    def landed_on(self, other):
        was_above = self.body.prev_y + HEIGHT <= other.y + 2
        return self.body.vy > 0 and was_above

    # play.py
    def check_walkers(self):
        p = self.player
        for w in self.walkers:
            if w.is_squashed():
                continue
            if not p.body.overlaps(w.body.x, w.body.y, w.body.w, w.body.h):
                continue
            if p.landed_on(w.body):
                w.squash(self.tun)
                p.bounce(self.app.actions.down("jump"), self.tun)
            else:
                self.die()
                return
    ```

The check uses the frog's position *last tick* (`prev`), not this tick's. By the time the two boxes overlap, the frog's feet are already below the beetle's top, so this tick's position can't tell a stomp from walking into it.

## Step 10: Coins, the Goal, and Lives

Coins are the simplest entity: a rectangle and whether it's been taken. All coins spin in step, so the frame is a function of time rather than something each coin tracks:

=== "Zig"

    ```zig
    pub fn cell(elapsed_ms: f64) usize {
        const frame: usize = @intFromFloat(@mod(elapsed_ms / 120.0, sheet.CoinFrames));
        return sheet.Coin1 + frame;
    }
    ```

=== "Python"

    ```python
    def cell(elapsed_ms):
        return sheet.COIN1 + int(elapsed_ms / 120) % sheet.COIN_FRAMES
    ```

The rest of the rules are in `play.zig`:

- Touching a coin marks it taken and counts it.
- Touching the goal loads the next level in `level.order`, or shows "LEVEL CLEAR!" after the last one.
- Touching a beetle, or falling below the map, starts a short death pause (the frog blinks). When it ends, the frog loses a life and the level restarts, or it's "GAME OVER".

The death pause is a countdown, `dying_ms`, rather than a separate state: while it runs, `update` skips straight to counting it down and nothing else moves.

## Step 11: Screens

The title, the pause overlay and the end message are each their own state, in `screens.zig`. The App switches between them with a state stack:

=== "Zig"

    ```zig
    pub const GameState = enum { title, play, paused, message };
    const StateMgr = pixzig.gamestate.GameStateMgr(Engine, GameState, &[_]type{
        screens.TitleState,
        PlayState,
        screens.PausedState,
        screens.MessageState,
    });

    pub fn pause(self: *App) void {
        self.states.push(.paused, .{ .renderBelow = true }) catch {};
    }

    pub fn resume_(self: *App) void {
        self.states.pop() catch {};
    }
    ```

=== "Python"

    ```python
    self.states = StateStack(self.title)

    def pause(self):
        self.states.push(self.paused, render_below=True)

    def resume_game(self):
        self.states.pop()
    ```

Pausing *pushes* the pause screen on top of play instead of replacing it. Only the top state updates, so the game freezes; `renderBelow` keeps the frozen game drawing underneath, and the pause screen dims it and draws its text on top. Popping goes back to exactly where play left off. The end message works the same way.

The screens never switch states themselves. They call App methods with names that say what they mean (`startGame`, `pause`, `showMessage`, `toTitle`), so the screen flow is all in one place in `main.zig`. See [Game States](page:game-states).

## Adding to It

With each part in its own file, most changes touch one or two files:

| To add | Change |
|---|---|
| A new enemy | A new file like `walker.zig` with its own `update` and `cell`, a list of them in `PlayState`, a class name in `restartLevel`, and its interaction with the player in a `check...` function |
| A second level | `assets/level2.tmx`, an entry in `manifest.json`'s `boot` group, and `"level2"` in `level.order` / `ORDER` |
| A new control | The action in `controls.zig`, then `eng.actions.pressed(...)` where it's used |
| Sound | Load sounds through the manifest and play them in `play.zig` where things happen (a coin taken, a beetle squashed); see [Audio](page:audio) |
| Different feel | Only `assets/tuning.json` |
| New art | `tools/gen_art.py`, or draw over `hopper.png`; name any new cells in `sheet.zig` |

## Splitting Your Own Game

Hopper started as fewer, bigger files, and was split along these lines. The same questions work for any game:

- **Does this code describe one thing, or two things meeting?** One thing's behavior goes in that thing's file. Two things meeting goes in the file that owns both, usually the play state.
- **Would two entities copy this?** Then it's shared, like `body.zig`. Physics, health, and animation timers are the usual candidates.
- **Is it a number someone will tweak?** Put it in data (`tuning.json`) rather than code.
- **Is it a name for something on disk?** Asset ids go in the manifest; sprite cell numbers go in one place, like `sheet.zig`.
- **Does the main file know about gameplay?** Ideally it only builds the engine, owns the shared resources (the sprite sheet, the tuning), and switches states.

When a game grows past this size, the next step is usually the one remzman takes: entities move into an ECS, and each `check...` function in the play state becomes its own system file. See [Entities and Events](page:ecs).
