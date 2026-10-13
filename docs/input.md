# Input

The runner updates `eng.inputs` before each `update` call. For game controls, bind named actions with an `ActionMap`. For text entry, the mouse cursor and device-specific behavior, read the keyboard, mouse and gamepads directly.

## Action Maps

An action map lets your game code ask "is the player jumping?" instead of "is Space down?". Players can rebind keys, and one action can have a keyboard key and a gamepad button at the same time.

Define your actions and axes as enums, and ask the engine for an action map over them with `actionOpts`:

```zig
const Action = enum { quit, jump, fire };
const Axis = enum { move_x };

const AppRunner = pixzig.AppRunner(App, .{
    .actionOpts = .{ .Action = Action, .Axes = Axis },
});
```

The engine creates the map as `eng.actions` and frees it on shutdown. Bind it in your app's `init`:

```zig
try eng.actions.bind(.quit, .{ .key = .escape });
try eng.actions.bind(.jump, .{ .key = .space });
try eng.actions.bind(.jump, .{ .gamepad_button = .a });
try eng.actions.bind(.fire, .{ .mouse_button = .left });
try eng.actions.bindAxis(.move_x, .{ .buttons = .{
    .negative = .{ .key = .a },
    .positive = .{ .key = .d },
} });
try eng.actions.bindAxis(.move_x, .{ .gamepad_axis = .{ .axis = .left_x } });
```

The runner updates the map every tick, just before `update`, so all you do is query it:

```zig
pub fn update(self: *App, eng: *AppRunner.Engine, deltaMs: f64) bool {
    if (eng.actions.pressed(.quit)) return false;
    if (eng.actions.pressed(.jump)) self.jump();
    if (eng.actions.down(.fire)) self.fire();
    self.vel.x = eng.actions.axis(.move_x) * Speed;
    return true;
}
```

`pressed` and `released` are true for one tick, on the edge. `down` and `up` are the held state. `axis` is in -1 to 1 for buttons and sticks.

`.Axes` is optional. Leave it out and the map gets `pixzig.input.NoAxes`, which has a single `.none` axis that always reads 0.

A few binding details:

- `bind` can be called several times for one action. Any of its bindings counts.
- Several axis bindings on one axis add up, so keyboard and stick can both drive `move_x`.
- `gamepad_axis` has a `deadzone` (0.18 by default). Gamepad bindings read gamepad slot 0.
- `mouse_axis` reads the mouse movement for the tick, scaled by `sensitivity` and clamped to `clamp`. Use it for mouse look.

### Key Chords

An action can also be bound to a key combination, or a two-step sequence like Ctrl+K then Ctrl+S:

```zig
const KeyChordPiece = pixzig.input.KeyChordPiece;

try eng.actions.bindChord(KeyChordPiece.from(.{ .ctrl = true }, .s), .save);
try eng.actions.bindChord2(
    KeyChordPiece.from(.{ .ctrl = true }, .k),
    KeyChordPiece.from(.{ .ctrl = true }, .s),
    .save_all,
);
```

A partial sequence resets after two seconds.

### Bindings From Lua

Bindings can live in a Lua config file so players can edit them. Each entry names an `action` or an `axis`, plus a `type`:

```lua
bindings = {
    { action = "jump", type = "key", key = "space" },
    { action = "jump", type = "gamepad_button", button = "a" },
    { action = "fire", type = "mouse_button", button = "left" },
    { action = "save", type = "chord", key = "ctrl+s" },
    { action = "save_all", type = "chord", key = "ctrl+k ctrl+s" },
    { axis = "move_x", type = "buttons", neg = "a", pos = "d" },
    { axis = "move_x", type = "gamepad_axis", stick = "left_x", deadzone = 0.2 },
    { axis = "look_x", type = "mouse_axis", component = "x", sensitivity = 0.1 },
}
```

```zig
try eng.scripts.runScript("assets/bindings.lua");
try eng.actions.loadFromLua(&eng.scripts, "bindings");
```

Names match the Zig enum fields. An unknown action or key returns an error such as `error.UnknownAction` or `error.UnknownKey`. See [Scripting](page:scripting) for setting up Lua.

### While the Console Is Open

If the engine owns a console (`EngineOptions.console`), the action map goes quiet while it's open: every action is up and every axis is 0, so typing `w` into the console doesn't walk the player. An action held when the console opens reports `released` on that tick.

Anything that has to work with the console open, like the key that closes it, should read the keyboard directly. `examples/console_ex.zig` toggles the console on F1 this way.

### Your Own Action Maps

`ActionMap` also works on its own, for example to give each local player a separate map. Then you create it, update it and free it yourself:

```zig
const Actions = pixzig.ActionMap(Action, Axis);

// In init:
self.actions = try Actions.init(alloc);

// At the top of update:
self.actions.update(&eng.inputs, deltaMs);

// In deinit:
self.actions.deinit();
```

`update` takes the tick length in milliseconds, which only matters for key chords. `updateSuppressed()` advances a tick as if nothing were held; it's what the engine uses while the console is open.

## Keyboard

```zig
const kb = &eng.inputs.keyboard;

if (kb.down(.left)) self.x -= 3;
if (kb.pressed(.space)) self.jump();
if (kb.released(.space)) self.endJump();
if (kb.ctrl() and kb.pressed(.s)) self.save();
```

`shift()`, `ctrl()`, `alt()` and `super()` check either side of the modifier. Keys are `pixzig.Key` values such as `.a`, `.space`, `.escape`, `.left` and `.left_shift`.

A `Key` names a physical position on the keyboard, not the letter printed on it. `.w` is where W sits on a US QWERTY board, whatever layout the player uses, so WASD controls stay under the same fingers on AZERTY or Dvorak. That's the right choice for game controls. When you mean the printed letter, like "press Y to confirm", use the layout versions:

```zig
if (kb.layoutPressed(.y)) self.confirm();
```

### Typed Text

For anything the player types, like a name or a chat line, read `text()`. It's already run through the keyboard layout, dead keys and IME, so it's correct for every language:

```zig
var buf: [16]u8 = undefined;
const len = eng.inputs.keyboard.text(&buf);
self.name.appendSlice(buf[0..len]);
```

Text input is off by default, and `text()` returns nothing until you turn it on:

```zig
const AppRunner = pixzig.AppRunner(App, .{
    .inputOpts = .{ .textInput = true },
});
```

It's off because an active text input can pop up an IME candidate bar or change on-screen keyboard behavior, which a game that only reads keys doesn't want. For Japanese, Chinese or Korean input, see [Platform Backend](page:platform-backend) for drawing the IME composition.

## Mouse

```zig
const mouse = &eng.inputs.mouse;
if (mouse.pos()) |pos| {
    if (mouse.pressed(.left)) self.clickAt(pos);
    if (mouse.down(.left)) self.dragTo(pos);
}
const wheel = mouse.scroll().y;
```

`pos()` is in logical coordinates and is null while the cursor is outside the game area, over a letterbox bar. `lastPos()` is the previous tick's position. `scroll()` is the wheel movement for this tick. Buttons are `.left`, `.middle`, `.right`, `.x1` and `.x2`.

To convert the cursor to world coordinates under a camera, use `camera.logicalToWorld` (see [Viewport and Cameras](page:viewport)).

For first-person style mouse look, capture the cursor. It's hidden and its movement is no longer stopped by the window edge:

```zig
try eng.setCursorCapture(true);
const turn = eng.inputs.mouse.delta().x * sensitivity;
```

`delta()` is the movement this tick in window coordinates. Release the cursor with `setCursorCapture(false)`. The mouse is on by default; turn it off with `inputOpts.mouse = false` if your game doesn't use it.

## Gamepads

Gamepads are off by default. Ask for as many slots as you need, up to four:

```zig
const AppRunner = pixzig.AppRunner(App, .{
    .inputOpts = .{ .numGamepads = 1 },
});
```

```zig
if (eng.inputs.gamepad(0)) |pad| {
    if (pad.isConnected()) {
        if (pad.pressed(.a)) self.jump();
        self.vel.x = pad.axis(.left_x) * Speed;
    }
}
```

`gamepad(index)` is null past the last slot you asked for. Pads can be plugged in and out while the game runs. To react when that happens, for example to pause when the player's pad drops out, handle `gamepad_added` and `gamepad_removed` in the app's `onEvent` (see [The Game Loop](page:app-runner)). They carry a `GamepadId`; `pad.id()` gives the id of the pad in a slot, or null when the slot is empty. Buttons use positional names (`.a` is the bottom face button) and axes are `.left_x`, `.left_y`, `.right_x`, `.right_y`, `.left_trigger` and `.right_trigger`.

When the window loses focus, all input state is cleared so no key gets stuck down.

## Command Key Maps

For editor-style commands rather than game controls, `KeyMap(T)` maps key chords to any value you like, such as a command name:

```zig
var keymap = try pixzig.input.KeyMap([]const u8).init(alloc);
defer keymap.deinit();

_ = try keymap.addKeyChord(.{ .ctrl = true }, .o, "open", null);
_ = try keymap.addTwoKeyChord(.{}, .g, .d, "goto_definition", null);

switch (keymap.update(eng.inputs.keyboard.currKeys(), deltaMs)) {
    .triggered => |chord| self.runCommand(chord.func.?),
    else => {},
}
```

Most games want an `ActionMap` instead. `examples/mouse_ex.zig` and `examples/gamepad_ex.zig` show the raw devices.
