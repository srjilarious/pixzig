# Platform Backend

Pixzig's windowing, input and clipboard all run on **SDL3**. This page
records what that means for engine users.

## The seam

Everything that talks to SDL directly lives in two places:

- `src/pixzig/platform/window.zig` -- the `SDL_Window` plus GL context, the
  clipboard, the window icon, the cursor, the swap interval and the clock.
- `src/pixzig/input/keys.zig` -- the engine's own `Key`, `MouseButton`,
  `GamepadButton` and `GamepadAxis` enums, and the mapping from SDL's codes
  onto them.

Nothing else in `src/`, in `examples/`, in `games/` or in the Python
bindings names SDL. Games see `pixzig.Key`, `eng.window` (a
`*platform.Window`) and `eng.inputs`; SDL stays behind those engine-level
APIs.

## Input identities are pixzig's own

The `Key` enum is dense and 0-based, and its values are pixzig's, not the
backend's. That matters twice over:

- The keyboard and mouse bitsets index straight off `@intFromEnum`, so key
  and button queries are constant-time enum lookups.
- The Python bindings pass those values across the C ABI as plain ints.
  `python/pixzig/constants.py` is **generated** from these enums by
  `zig build py-constants`; after editing `keys.zig`, re-run it and commit
  the result.

Field names are the stable names used by games, `ActionMap` binding strings
and saved keybind configs. SDL does not provide `world_1`, `world_2` or
`F25`; mouse side buttons are spelled `x1` and `x2`.

### Position, not keycap

`Key` comes from SDL's *scancode*, so it names a physical position: `.w` is
the key where W sits on a US QWERTY board whatever layout is active, and
WASD bindings stay under the same fingers on AZERTY or Dvorak. This is the
right default for a game and the opposite of what a terminal wants.

The layout-resolved identity of the same key is available alongside it, via
`keyboard.layoutDown` / `layoutPressed` / `layoutReleased`, for UI that
cares about the keycap. Typed text should come from `keyboard.text()`,
which is correct for every layout without either of these.

## Events, not polling

`PixzigEngine.pollEvents` drains SDL's event queue, handles window-level
events itself, and hands the rest to `InputManager.handleEvent`.

Two consequences:

- Input events are routed directly through the engine-owned `InputManager`,
  so each engine instance owns its keyboard, mouse and gamepad state.
- Polling self-heals and events latch. A key-up that never arrives leaves a
  key stuck down forever, so the engine clears all input state on
  `SDL_EVENT_WINDOW_FOCUS_LOST`.

The tick now has two halves. `inputs.update()` opens it (latching typed
text and mapping the cursor into logical coordinates) and
`inputs.finishTick()` closes it, rolling the current state into the
previous one so `pressed` / `released` are edges against exactly one tick.
`PixzigAppRunner` does both around `app.update()`. A caller driving the
loop by hand -- the Python bindings, for instance -- must call both;
`pz_finish_tick` is the C entry point.

## Text input and IME

`InputOptions.textInput` arms SDL's text-input machinery on the window. It
is **off by default**: a game that only reads key bindings does not want an
IME candidate bar armed over it, and on some platforms an armed text input
changes on-screen-keyboard behaviour. With it off, `keyboard.text()`
returns nothing.

With it on, the engine also tracks the IME's in-progress composition
through `keyboard.preedit()` and `keyboard.preeditCursorByte()`. An app
that wants to accept Japanese, Chinese or Korean input has to draw that
composition at the caret and call `window.setTextInputArea` to tell the OS
where the caret is -- otherwise the candidate window sits at the window
origin and the user types into an apparently dead window until the commit
lands. Note that `setTextInputArea` takes **window** coordinates, so a
caret rect measured in framebuffer pixels must be divided by
`window_state.scale_factor` first.

## HiDPI

Windows are created with `SDL_WINDOW_HIGH_PIXEL_DENSITY`, so on a 2x
display `framebuffer_size` genuinely differs from `window_size` and
`window_state.scale_factor` is the ratio between them. Prefer
`scale_factor` for coordinate math: `content_scale` (SDL's display scale)
can disagree with it under Wayland fractional scaling. Anything handed back
*to* the platform in window units -- `window.setSize`,
`window.setTextInputArea` -- has to be divided down by it.

## Targets

| Target | How SDL3 gets there |
|---|---|
| Linux, Windows | The `allyourcodebase/SDL` package builds a static libSDL3 and the `sdl3` module carries it, so importing the module is all that is needed. |
| Emscripten | The build translates the upstream SDL headers itself and the implementation comes from emcc's own SDL3 port (`--use-port=sdl3`). |

The emscripten port tracks a slightly different SDL point release than the
desktop build; SDL3 is ABI-stable across those, but it is worth knowing
when chasing a web-only difference. emcc also still labels its SDL3 port
experimental.
