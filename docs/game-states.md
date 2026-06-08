# Game States

`GameStateMgr` dispatches `update` and `render` to the active state. States may also provide `activate` and `deactivate` hooks.

## Defining States

Each state is a plain struct. It must implement `update` and `render` using the same signatures as the top-level App. Lifecycle hooks are optional.

```zig
const StateA = struct {
    // Called when this state becomes active.
    pub fn activate(self: *StateA) void {
        std.debug.print("StateA activated\n", .{});
    }

    // Called when this state is replaced by another.
    pub fn deactivate(self: *StateA) void {
        std.debug.print("StateA deactivated\n", .{});
    }

    pub fn update(self: *StateA, eng: *AppRunner.Engine, delta: f64) bool {
        _ = self; _ = eng; _ = delta;
        return true;
    }

    pub fn render(self: *StateA, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0, 1, 0, 1); // green background
    }
};

const StateB = struct {
    pub fn update(self: *StateB, eng: *AppRunner.Engine, delta: f64) bool {
        _ = self; _ = eng; _ = delta;
        return true;
    }

    pub fn render(self: *StateB, eng: *AppRunner.Engine) void {
        eng.renderer.clear(1, 0, 0, 1); // red background
    }
};
```

`activate` and `deactivate` are optional.

## Creating the Manager

Instantiate `GameStateMgr` with the engine type, state enum, and concrete state types in enum order:

```zig
const States = enum { StateA, StateB };

// Order must match the enum declaration.
const AppStateMgr = pixzig.gamestate.GameStateMgr(
    AppRunner.Engine,
    States,
    &[_]type{ StateA, StateB },
);
```

The compiler validates that the number of types matches the enum variant count.

## Initialising with State Instances

Pass state instances as `*anyopaque` pointers:

```zig
var stateA = StateA{};
var stateB = StateB{};
var stateArr = [_]*anyopaque{ &stateA, &stateB };

const mgr = AppStateMgr.init(stateArr[0..]);
```

## Using the Manager in App

```zig
pub const App = struct {
    states: AppStateMgr,

    pub fn update(self: *App, eng: *AppRunner.Engine, delta: f64) bool {
        if (eng.inputs.keyboard.pressed(.one)) self.states.setCurrState(.StateA);
        if (eng.inputs.keyboard.pressed(.two)) self.states.setCurrState(.StateB);
        if (eng.inputs.keyboard.pressed(.escape)) return false;

        return self.states.update(eng, delta);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        self.states.render(eng);
        self.fps.renderTick();
    }
};
```

## Full Example (main)

```zig
pub fn main() !void {
    const appRunner = try AppRunner.init("State Test", std.heap.c_allocator, .{});

    var stateA = StateA{};
    var stateB = StateB{};
    var statesArr = [_]*anyopaque{ &stateA, &stateB };

    const app = try App.init(std.heap.c_allocator, statesArr[0..]);
    appRunner.run(app);
}
```

The manager starts on the first enum value. Initialization does not call its `activate` hook.

## Notes

- States are identified by enum value (`.StateA` rather than an integer index).
- There is no built-in state stack; if you need push/pop semantics, layer a stack on top of `setCurrState`.
- `update` on the manager returns the bool returned by the active state's `update`, so returning `false` from a state exits the game loop.
