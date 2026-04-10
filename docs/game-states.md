# Game States

`GameStateMgr` is a compile-time generic that dispatches `update` and `render` to whichever state is currently active, with optional `activate` / `deactivate` lifecycle hooks.

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

States that omit `activate` or `deactivate` are silently skipped — you only pay for what you implement.

## Creating the Manager

Instantiate `GameStateMgr` with three compile-time arguments: the engine type, the state enum, and a slice of the concrete state types in enum-order:

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

State instances are passed as `*anyopaque` pointers, which lets state objects live anywhere (stack, heap, as fields of App, etc.):

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
        // Switch states on key press — triggers deactivate/activate.
        if (eng.keyboard.pressed(.one)) self.states.setCurrState(.StateA);
        if (eng.keyboard.pressed(.two)) self.states.setCurrState(.StateB);
        if (eng.keyboard.pressed(.escape)) return false;

        // Delegate update to the active state.
        return self.states.update(eng, delta);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        // Delegate render to the active state.
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

The manager starts with no active state (index 0 is not pre-selected). Call `setCurrState` at least once before the first `update`, or handle the null case in each state's methods.

## Notes

- States are identified by enum value, making call sites self-documenting (`.StateA` vs an integer index).
- There is no built-in state stack; if you need push/pop semantics, layer a stack on top of `setCurrState`.
- `update` on the manager returns the bool returned by the active state's `update`, so returning `false` from a state exits the game loop.
