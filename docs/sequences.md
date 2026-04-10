# Sequences

The sequencer coordinates timed game events — moving a sprite, switching an animation state, waiting, or triggering custom game logic — in a clean, composable way without nested callbacks or state machines.

## Core Concepts

| Type | Role |
|---|---|
| `Step` | A single action with a VTable (`update` + `deinit`) |
| `Sequence` | An ordered list of steps that run one after another |
| `SequencePlayer` | Holds and ticks all active sequences; removes them when done |

## Built-in Steps

### WaitStep

Pauses the sequence for a given number of milliseconds:

```zig
try sequence.add(alloc, try seq.WaitStep.init(alloc, 500.0)); // 500 ms pause
```

### MoveToStep

Linearly interpolates a flecs entity's `Sprite` component from its current position to a target over a duration. Start position is captured lazily on the first tick.

```zig
const target = Vec2F{ .x = 100, .y = 48 };
try sequence.add(alloc, try seq.MoveToStep.init(
    alloc, world, entity, target, 300.0, // 300 ms
));
```

### SetActorStateStep

Instantly switches a flecs entity's `Actor` animation state. Fire-and-forget — the sequence advances immediately.

```zig
try sequence.add(alloc, try seq.SetActorStateStep.init(
    alloc, world, entity, "walk_right",
));
```

### ParallelStep

Runs multiple sub-steps concurrently. The parallel step finishes when **all** sub-steps are done.

```zig
var par = try seq.ParallelStep.init(alloc);
try seq.ParallelStep.add(&par, alloc, try seq.WaitStep.init(alloc, 200.0));
try seq.ParallelStep.add(&par, try seq.MoveToStep.init(alloc, world, entityB, target, 200.0));
try sequence.add(alloc, par);
```

## Building and Playing a Sequence

```zig
// 1. Create a SequencePlayer (owned by your App).
var seqPlayer = seq.SequencePlayer.init(alloc);
defer seqPlayer.deinit();

// 2. Build a Sequence.
var sequence = seq.Sequence.init(alloc);
try sequence.add(alloc, try seq.SetActorStateStep.init(alloc, world, entity, "right"));
try sequence.add(alloc, try seq.MoveToStep.init(alloc, world, entity, .{ .x = 80, .y = 16 }, 300.0));
try sequence.add(alloc, try seq.WaitStep.init(alloc, 200.0));

// 3. Hand the sequence to the player (transfers ownership).
try seqPlayer.add(sequence);

// 4. Tick every update — the player removes finished sequences automatically.
pub fn update(self: *App, ...) bool {
    self.seqPlayer.update(delta);
    ...
}
```

## Blocking Input While a Sequence Runs

A common pattern is to queue a move only when no sequence is already in flight:

```zig
if (self.seqPlayer.sequences.items.len == 0) {
    if (eng.keyboard.pressed(.right)) {
        try self.queueMove("right", 16, 0);
    }
}
```

## Custom Game-Side Steps

Steps not appropriate for the engine (e.g. screen flashes, sound triggers) live in your game and follow the same VTable pattern:

```zig
pub const FlashStep = struct {
    flash: *FlashState,
    durationMs: f64,
    color: [4]f32,

    const vtable: seq.Step.VTable = .{ .update = update, .deinit = deinit };

    pub fn init(alloc: std.mem.Allocator, flash: *FlashState, ms: f64, color: [4]f32) !seq.Step {
        const ptr = try alloc.create(FlashStep);
        ptr.* = .{ .flash = flash, .durationMs = ms, .color = color };
        return .{ .ptr = ptr, .vtable = &vtable, .done = false };
    }

    pub fn update(step: *seq.Step, _: f64) f64 {
        const self: *FlashStep = @ptrCast(@alignCast(step.ptr));
        self.flash.* = .{ .active = true, .remainingMs = self.durationMs,
                          .totalMs = self.durationMs, .color = self.color };
        step.done = true;
        return -1.0; // negative → done immediately
    }

    pub fn deinit(step: *seq.Step, alloc: std.mem.Allocator) void {
        const self: *FlashStep = @ptrCast(@alignCast(step.ptr));
        alloc.destroy(self);
    }
};
```

The `update` function returns the time remaining. Return a negative value to signal that the step is done and the sequence should advance immediately.

## Lua Scripting Bridge

`SeqScriptingContext` exposes sequence building to Lua scripts. Bind it once after init:

```zig
var seqCtx = seq.SeqScriptingContext.init(alloc, world, &seqPlayer);
defer seqCtx.deinit();
seqCtx.bindToLua(scriptEng.lua);
```

This registers five Lua globals:

| Function | Description |
|---|---|
| `seq_new() -> handle` | Allocate a new pending sequence slot |
| `seq_wait(h, ms)` | Append a WaitStep |
| `seq_move_to(h, eid, x, y, ms)` | Append a MoveToStep |
| `seq_set_actor_state(h, eid, name)` | Append a SetActorStateStep |
| `seq_play(h)` | Submit the sequence to the player |

Set entity ID and position globals from Zig before running the script:

```zig
scriptEng.lua.pushInteger(@intCast(self.entity));
scriptEng.lua.setGlobal("player_entity");

const spr = flecs.get(world, entity, Sprite).?;
scriptEng.lua.pushNumber(@floatCast(spr.dest.l));
scriptEng.lua.setGlobal("player_x");
scriptEng.lua.pushNumber(@floatCast(spr.dest.t));
scriptEng.lua.setGlobal("player_y");

try scriptEng.runScript("assets/circle_move.lua");
```

The script then builds and submits the sequence entirely in Lua:

```lua
-- circle_move.lua
local step = 16
local ms   = 300
local h = seq_new()

seq_set_actor_state(h, player_entity, "right")
seq_move_to(h, player_entity, player_x + step, player_y, ms)

seq_set_actor_state(h, player_entity, "down")
seq_move_to(h, player_entity, player_x + step, player_y + step, ms)

seq_set_actor_state(h, player_entity, "left")
seq_move_to(h, player_entity, player_x, player_y + step, ms)

seq_set_actor_state(h, player_entity, "up")
seq_move_to(h, player_entity, player_x, player_y, ms)

seq_play(h)
```

## Step VTable Contract

| Field | Type | Semantics |
|---|---|---|
| `ptr` | `*anyopaque` | Pointer to the concrete step struct |
| `vtable` | `*const Step.VTable` | Points to a `const` vtable on the concrete type |
| `done` | `bool` | Set to `true` by `update` when finished |

`update(step, deltaMs) f64` — tick the step; return time remaining (negative means done). The sequence advances to the next step on the tick after `done` is set.

`deinit(step, alloc)` — free all memory owned by the step. Called by the sequence when it is destroyed.
