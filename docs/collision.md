# Collision and Pathfinding

Pixzig has three tools here, from simplest to most general:

| Tool | Use it for |
|---|---|
| `tile.Mover` | Moving a box through a tile map without walking into walls. |
| `collision.CollisionGrid` | Finding which objects are near a point or a box, for object-to-object collision. |
| `a_star.AStarPathFinder` | Planning a path across a tile map, for enemies that chase the player. |

## Moving Against Tiles

`tile.Mover` moves a rect along one axis and stops it at the first blocking tile. Blocking comes from the `blocks` property on tiles in Tiled (see [Tile Maps](page:tile-rendering)):

```zig
const Mover = pixzig.tile.Mover;
const layer = self.mapRenderer.tileMap().layerByName("walls").?;

const speed: f32 = 2;
if (self.actions.down(.left)) _ = Mover.moveLeft(&self.box, speed, layer, pixzig.tile.BlocksAll);
if (self.actions.down(.right)) _ = Mover.moveRight(&self.box, speed, layer, pixzig.tile.BlocksAll);
if (self.actions.down(.up)) _ = Mover.moveUp(&self.box, speed, layer, pixzig.tile.BlocksAll);
if (self.actions.down(.down)) _ = Mover.moveDown(&self.box, speed, layer, pixzig.tile.BlocksAll);
```

Each call returns true when it hit something. In that case the rect is moved flush against the tile's edge rather than overlapping it. The last argument is a mask of tile flags that count as solid, so a platformer can pass `tile.BlocksTop` when falling to get one-way platforms.

Move one axis at a time like this, and sliding along walls works for free.

## Collision Grid

For lots of moving objects, checking every pair gets slow. A `CollisionGrid` splits the world into cells and keeps a list of which objects touch each cell. You only check objects in the cells near you.

The grid stores any small value type, usually an entity id or an index into your own array, with a fixed number of slots per cell:

```zig
const Grid = pixzig.collision.CollisionGrid(u32, 8); // up to 8 objects per cell

// 40x30 cells of 16x16 pixels covers a 640x480 world.
self.grid = try Grid.init(alloc, .{ .x = 40, .y = 30 }, .{ .x = 16, .y = 16 });
defer self.grid.deinit();

try self.grid.insertRect(enemy.rect, enemy.id);
```

`insertRect` adds the object to every cell the rect touches. Parts outside the grid are ignored. A full cell returns `error.NoMoreSpace`, so size the per-cell count for your busiest spots.

When an object moves, remove it with its old rect and insert it with the new one:

```zig
_ = try self.grid.removeRect(oldRect, enemy.id);
try self.grid.insertRect(newRect, enemy.id);
```

For a game where everything moves every tick, it's often simpler to `reset()` the grid and insert everything again.

### Queries

Queries fill a list you pass in and return how many they found:

```zig
var hits: [8]?u32 = undefined;
const n = try self.grid.checkPoint(mousePos, &hits[0..]);
for (hits[0..n]) |hit| self.select(hit.?);
```

| Query | Finds objects in |
|---|---|
| `checkPoint(pos, &list)` | The cell under a point. |
| `checkLeft(&rect, &list)` | The cells along a rect's left edge. Also `checkRight`, `checkUp`, `checkDown`. |
| `checkHorz(cx0, cx1, cy, &list)`, `checkVert(cx, cy0, cy1, &list)` | A row or column of cells, by cell coordinates. |

The edge queries are handy before a move: check the edge you're about to move toward. An object in several of those cells is only listed once. If the list is too small, the query returns `error.NoMoreSpace`. For `checkPoint` the list must hold at least the per-cell count.

The grid is broad phase only. It tells you what's nearby, and you still compare the actual rects with `RectF.intersects` to see if they overlap.

Keep positions inside the grid. `insert` with a single point outside it is out of bounds; `insertRect` clips instead, so prefer it.

## Pathfinding

`AStarPathFinder` finds a path between two tiles, moving up, down, left and right. You give it a checker that says which tiles can be walked on. `BasicTileMapPathChecker` treats any tile with the `BlocksAll` flag as a wall:

```zig
const a_star = pixzig.a_star;
const Finder = a_star.AStarPathFinder(a_star.BasicTileMapPathChecker);

// Once, after loading the map:
const walls = map.layerByName("walls").?;
self.finder = try Finder.init(a_star.BasicTileMapPathChecker.init(walls), alloc, walls.size);
self.path = .empty;

// Whenever the enemy needs a new route:
try self.finder.findPath(enemyTile, playerTile, &self.path);
if (self.path.items.len > 0) {
    const next = self.path.items[0]; // first step after the start
    // move toward `next`
}

// In deinit:
self.finder.deinit();
self.path.deinit(alloc);
```

The path runs from the first step after `start` to `goal`, so it doesn't include the start tile. It's cleared at the start of each search. Reuse one finder per map; it allocates its working memory once in `init`.

If the goal can't be reached, the path's first entry is `(-1, -1)` rather than a real step, so check that before following it.

### Your Own Rules

For anything more than "is this a wall", write your own checker. It's any type with a `checkPosition` method:

```zig
const GhostChecker = struct {
    layer: *const pixzig.TileLayer,
    doorsOpen: bool,

    pub fn checkPosition(self: *GhostChecker, loc: pixzig.a_star.TileLoc) bool {
        const t = self.layer.tile(loc.x, loc.y) orelse return true;
        if (t.core & pixzig.tile.BlocksAll != 0) return false;
        // Custom properties are strings; anything else is up to you.
        return self.doorsOpen or !isDoor(t);
    }
};

var finder = try pixzig.a_star.AStarPathFinder(GhostChecker).init(.{ .layer = layer, .doorsOpen = false }, alloc, layer.size);
```

`examples/collision_ex.zig` uses a collision grid with the mouse, and `examples/a_star_path_ex.zig` shows pathfinding on a grid.
