# Platform Backend

Pixzig runs on SDL3 underneath, but games never talk to SDL. Windows, input, the clipboard, timing and text input all come through pixzig's own types. This page covers how that layer works, for when you need the details: IME text input, HiDPI math, or driving the engine by hand.

## The Boundary

Game code, the scripting bindings and the Python bindings all stay on pixzig's side:

- `eng.window` is a `*platform.Window`, with methods for size, title, fullscreen, the clipboard, cursor capture and the text-input area.
- `eng.inputs` is the engine's `InputManager`.
- `pixzig.Key`, `MouseButton`, `GamepadButton` and `GamepadAxis` are the device names used by game code, action maps and saved key bindings.

The backend translates OS events into those types. That keeps the same code working on desktop and the web, and leaves room to change the backend without renaming anyone's inputs. Inside the engine, SDL is only used by the platform window, the input modules and the event loop.

## Input Names

The `Key` enum belongs to pixzig, and its values run densely from 0. That matters in two places:

- The keyboard and mouse state are bitsets indexed straight from the enum, so every key query is a constant-time lookup.
- The Python bindings pass these values across the C API as plain integers. `python/pixzig/constants.py` is generated from the enums with `zig build py-constants`. After editing `keys.zig`, run it and commit the result.

The field names are what action maps and saved key configs use, so they're stable. Mouse side buttons are `x1` and `x2`.

### Position, Not Keycap

A `Key` is a physical position: `.w` is where W sits on a US QWERTY keyboard, whatever layout is active. That's right for game controls, since WASD stays under the same fingers on AZERTY or Dvorak. The layout's own meaning of each key is tracked alongside, through `keyboard.layoutDown`, `layoutPressed` and `layoutReleased`, for prompts that name a keycap. Typed text should always come from `keyboard.text()`, which is correct for every layout.

## The Event Loop

Each frame, `Engine.pollEvents` drains the OS event queue. It handles window events itself (close, resize, focus) and passes device events to `InputManager.handleEvent`.

`Engine.pollEventsWith(handler)` does the same and also translates every non-input event into a `pixzig.Event` (`platform/event.zig`, `fromSdl`) and calls `handler.onEvent(eng, event)` with it. The engine's own handling runs first, so by the time the handler sees `focus_lost` the input is already cleared and by `window_resized` the viewport is already rebuilt. `AppRunner` passes the app as the handler when it declares `onEvent` (see [The Game Loop](page:app-runner)). The C API's version is `pz_poll_events_cb(eng, callback, user)`, which hands the callback a flat `PzEvent`; `pz_cancel_close` keeps the window open after a close request.

Input state is built from events, so a key-up that never arrives would leave a key stuck down. To avoid that, the engine clears all input state when the window loses focus.

Each update tick has two halves. `inputs.update()` opens it: it latches the text typed since the last tick and maps the cursor into logical coordinates. `inputs.finishTick()` closes it, copying the current state to the previous state so that `pressed` and `released` are edges across exactly one tick. `AppRunner` does both around `app.update`. Anything driving the loop by hand, like the Python bindings, has to call both; the C API's versions are `pz_update_input` and `pz_finish_tick`.

## Text Input and IME

`inputOpts.textInput` turns on OS text input for the window. It's off by default, because a game that only reads keys doesn't want an IME candidate bar popping up, and on some platforms text input changes how the on-screen keyboard behaves. With it off, `keyboard.text()` returns nothing.

With it on, the engine also tracks the IME's in-progress composition: `keyboard.preedit()` is the text being composed and `keyboard.preeditCursorByte()` is the cursor within it. An app that accepts Japanese, Chinese or Korean input should:

1. Draw the preedit text at the caret, so the player sees what they're composing.
2. Call `window.setTextInputArea(x, y, w, h, cursor)` with the caret's rect, so the OS puts its candidate window next to it.

Without step 2 the candidate window sits at the window's corner. `setTextInputArea` takes window coordinates, so divide a framebuffer-pixel rect by `windowState.scaleFactor` first.

## HiDPI

Windows ask for a high-density framebuffer. On a 2x display, `windowState.framebufferSize` really is twice `windowSize`, and `windowState.scaleFactor` is the ratio between them.

Use `scaleFactor` for coordinate math rather than `contentScale`. The display scale the OS reports can disagree with the actual framebuffer ratio under Wayland fractional scaling. Anything you hand back to the platform in window units, like `window.setSize` or `window.setTextInputArea`, has to be divided by `scaleFactor`.

## Targets

| Target | Backend |
|---|---|
| Linux, Windows | SDL3, built and linked by pixzig's build. Games don't add platform libraries themselves. |
| Web | Emscripten's own SDL3 port, with WebGL 2. The pixzig API is the same as on desktop. |

The desktop and web SDL builds can be slightly different versions, so a platform-specific bug is possible. Treat that as an engine problem to fix in the backend; game code should keep using pixzig's types.
