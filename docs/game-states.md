# Game States

Most games have a few distinct screens: a title screen, the game itself, a pause menu, a game over screen. `GameStateMgr` gives each one its own struct and forwards `update` and `render` to whichever is active.

## Defining States

A state is a plain struct with the same `update` and `render` methods as an app. It can also have `activate` and `deactivate`, which run when it becomes active or stops being active:

```zig
const TitleState = struct {
    pub fn activate(self: *TitleState) void {
        _ = self;
        std.log.info("showing title", .{});
    }

    pub fn update(self: *TitleState, eng: *AppRunner.Engine, deltaMs: f64) void {
        _ = self;
        _ = deltaMs;
        if (eng.inputs.keyboard.pressed(.escape)) eng.quit();
    }

    pub fn render(self: *TitleState, eng: *AppRunner.Engine) void {
        _ = self;
        eng.renderer.clear(0, 0, 80, 255);
    }
};

const PlayState = struct { ... };
```

## Creating the Manager

Name the states with an enum, and list the state types in the same order:

```zig
const States = enum { title, play };

const StateMgr = pixzig.gamestate.GameStateMgr(
    AppRunner.Engine,
    States,
    &[_]type{ TitleState, PlayState },
);
```

The compiler checks that the enum and the list are the same length, and that the enum's values run 0, 1, 2... in order, which is the default when you don't assign any.

Create it with a tuple of pointers to your state instances, in the same order:

```zig
self.titleState = .{};
self.playState = .{};
self.states = StateMgr.init(.{ &self.titleState, &self.playState });
```

The tuple's type is `StateMgr.StatePtrs`, so a missing state or a pointer of the wrong type is a compile error. The states have to stay put while the manager uses them, so keep them in your heap-allocated app (or somewhere else stable), not in local variables of `init`.

## Using It

Forward the app's methods to the manager and switch states with `setCurrState`:

```zig
pub const App = struct {
    titleState: TitleState,
    playState: PlayState,
    states: StateMgr,

    pub fn update(self: *App, eng: *AppRunner.Engine, deltaMs: f64) void {
        if (self.states.currState == .title and eng.inputs.keyboard.pressed(.enter)) {
            self.states.setCurrState(.play);
        }
        self.states.update(eng, deltaMs);
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        self.states.render(eng);
    }
};
```

Some things to know:

- The manager starts on the first state, without calling its `activate`.
- `setCurrState` calls `deactivate` on the old state and `activate` on the new one, when they exist.
- A state's `update` returns `void` or `!void`, like the app's. A state ends the game with `eng.quit()`; an error it returns is logged and quits too.
- There's no state stack. For a pause menu over gameplay, keep a stack of your own on top of `setCurrState`, or draw the menu from the play state.

States often need to reach back into the game, e.g. to switch states themselves. Give them a pointer to the app, or to a shared game struct, when you create them.

`examples/game_state_ex.zig` switches between two states with the number keys.
