# Platform Backend

Pixzig owns the public platform abstraction: windows, input, clipboard,
timing, cursor state, and text input are exposed through engine APIs. The
current implementation uses SDL3 underneath, but game code should treat that
as a backend detail rather than a dependency to program against.

## Engine Boundary

Games, examples, scripting bindings, and Python bindings should stay on the
Pixzig side of the boundary:

- `eng.window` is a `*platform.Window`, with methods for sizing, clipboard,
  cursor capture, text-input area, and buffer swapping.
- `eng.inputs` is the engine-owned `InputManager`.
- `pixzig.Key`, `MouseButton`, `GamepadButton`, and `GamepadAxis` are the
  stable device identities for game code, bindings, and serialized action
  maps.

The backend is responsible for translating OS events into those types. That
keeps application code portable across desktop and web builds, and leaves
room for the backend to change without forcing games to rename their inputs
or include backend modules.

## Input Identities

The `Key` enum is dense and 0-based, and its values are Pixzig's own. That
matters twice over:

- The keyboard and mouse bitsets index straight off `@intFromEnum`, so key
  and button queries are constant-time enum lookups.
- The Python bindings pass those values across the C ABI as plain ints.
  `python/pixzig/constants.py` is **generated** from these enums by
  `zig build py-constants`; after editing `keys.zig`, re-run it and commit
  the result.

Field names are the stable names used by games, `ActionMap` binding strings,
and saved keybind configs. They are intentionally engine-owned names; for
example, Pixzig can expose reserved keyboard slots such as `world_1`,
`world_2`, or `F25`, and mouse side buttons are spelled `x1` and `x2`.

### Position, Not Keycap

`Key` names a physical keyboard position: `.w` is the key where W sits on a
US QWERTY board whatever layout is active, and WASD bindings stay under the
same fingers on AZERTY or Dvorak. This is the right default for a game and
the opposite of what a terminal wants.

The layout-resolved identity of the same key is available alongside it, via
`keyboard.layoutDown` / `layoutPressed` / `layoutReleased`, for UI that
cares about the keycap. Typed text should come from `keyboard.text()`,
which is correct for every layout without either of these.

## Event Flow

`PixzigEngine.pollEvents` drains the platform event queue, handles
window-level events itself, and hands device events to
`InputManager.handleEvent`.

Two consequences:

- Input events are routed directly through the engine-owned `InputManager`,
  so each engine instance owns its keyboard, mouse, and gamepad state.
- Polling self-heals and events latch. A key-up that never arrives leaves a
  key stuck down forever, so the engine clears all input state when the
  window loses focus.

The tick has two halves. `inputs.update()` opens it, latching typed text and
mapping the cursor into logical coordinates. `inputs.finishTick()` closes
it, rolling the current state into the previous one so `pressed` /
`released` are edges against exactly one tick. `PixzigAppRunner` does both
around `app.update()`. A caller driving the loop by hand -- the Python
bindings, for instance -- must call both; `pz_finish_tick` is the C entry
point.

## Text Input and IME

`InputOptions.textInput` enables OS text input for the window. It is **off
by default**: a game that only reads key bindings does not want an IME
candidate bar armed over it, and on some platforms active text input changes
on-screen-keyboard behaviour. With it off, `keyboard.text()` returns
nothing.

With it on, the engine also tracks the IME's in-progress composition
through `keyboard.preedit()` and `keyboard.preeditCursorByte()`. An app that
wants to accept Japanese, Chinese, or Korean input has to draw that
composition at the caret and call `window.setTextInputArea` to tell the OS
where the caret is. Otherwise the candidate window sits at the window origin
and the user types into an apparently dead window until the commit lands.
Note that `setTextInputArea` takes **window** coordinates, so a caret rect
measured in framebuffer pixels must be divided by
`window_state.scale_factor` first.

## HiDPI

Windows request high pixel density framebuffers, so on a 2x display
`framebuffer_size` genuinely differs from `window_size` and
`window_state.scale_factor` is the ratio between them. Prefer
`scale_factor` for coordinate math: the display content scale can disagree
with the actual framebuffer ratio under Wayland fractional scaling.
Anything handed back *to* the platform in window units -- `window.setSize`,
`window.setTextInputArea` -- has to be divided down by it.

## Targets

| Target | Platform behavior |
|---|---|
| Linux, Windows | Pixzig links the platform backend through its build package, so games import the engine module rather than adding platform libraries themselves. |
| Emscripten | The web build uses Emscripten's platform support and the engine's translated backend declarations, keeping the public Pixzig API the same as desktop. |

Desktop and web builds may sit on slightly different backend point releases,
so a platform-specific bug can still exist. Treat that as an engine/backend
diagnostic detail; application code should continue to use the Pixzig
abstractions.
