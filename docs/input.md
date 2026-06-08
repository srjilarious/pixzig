# Input

`PixzigAppRunner` updates `eng.inputs` before each call to `App.update`. Use an `ActionMap` for game controls. Read `eng.inputs` directly for text entry, pointer position, or device-specific behavior.

## Action Maps

An action map names controls independently of their physical bindings:

```zig
const Action = enum { quit, jump, fire };
const Axis = enum { move_x };
const Actions = pixzig.input.ActionMap(Action, Axis);

// During App initialization:
self.actions = try Actions.init(alloc);
try self.actions.bind(.quit, .{ .key = .escape });
try self.actions.bind(.jump, .{ .key = .space });
try self.actions.bind(.fire, .{ .mouse_button = .left });
try self.actions.bindAxis(.move_x, .{ .buttons = .{
    .negative = .{ .key = .a },
    .positive = .{ .key = .d },
} });
```

Update actions once per game tick, then query them:

```zig
pub fn update(self: *App, eng: *AppRunner.Engine, _: f64) bool {
    _ = self.actions.update(&eng.inputs);

    if (self.actions.pressed(.quit)) return false;
    if (self.actions.pressed(.jump)) self.jump();
    if (self.actions.down(.fire)) self.fire();

    self.velocity.x = self.actions.axis(.move_x) * Speed;
    return true;
}
```

`bind` may be called more than once for the same action. Digital bindings accept keys, mouse buttons, and gamepad buttons. Axis bindings accept a keyboard button pair or a gamepad axis.
Call `self.actions.deinit()` from `App.deinit`.

## Input Manager

The input manager exposes raw device state:

| Field | Availability |
|---|---|
| `eng.inputs.keyboard` | Always enabled |
| `eng.inputs.mouse` | Enabled when `inputOpts.mouse` is `true` (the default) |
| `eng.inputs.gamepad(index)` | Enable slots with `inputOpts.numGamepads` |

### Keyboard

```zig
const keyboard = &eng.inputs.keyboard;

if (keyboard.down(.left)) self.x -= 3;
if (keyboard.pressed(.space)) self.jump();
if (keyboard.released(.space)) self.stopJump();
if (keyboard.pressed(.escape)) return false;
```

Keys are `glfw.Key` values such as `.a`, `.space`, `.escape`, `.left`, and `.left_shift`.

For ASCII text input, supply a buffer. `text` returns the number of bytes written for this tick:

```zig
var chars: [16]u8 = undefined;
const len = eng.inputs.keyboard.text(&chars);
self.acceptText(chars[0..len]);

const mods = eng.inputs.keyboard.currKeys().modifiers();
if (mods.ctrl and mods.shift) {
    // Handle Ctrl+Shift shortcut.
}
```

### Mouse

`mouse.pos()` is in logical game coordinates after viewport mapping. It is `(-1, -1)` while the cursor is outside a letterboxed or pillarboxed viewport.

```zig
const mouse = &eng.inputs.mouse;
if (mouse.pressed(.left)) self.onClick(mouse.pos());
if (mouse.down(.left)) self.onDrag(mouse.pos());

const pos = mouse.pos();
const last = mouse.lastPos();
const dx = pos.x - last.x;
```

### Gamepad

Configure the number of tracked gamepads in the runner options:

```zig
const AppRunner = pixzig.PixzigAppRunner(App, .{
    .inputOpts = .{ .numGamepads = 1 },
});
```

Then query a configured slot:

```zig
const pad = eng.inputs.gamepad(0);
if (pad.isConnected()) {
    if (pad.pressed(.a)) self.jump();
    self.velocity.x = pad.axis(.left_x) * Speed;
}
```

## Key Chords

`KeyMap` matches key sequences to command strings. It is intended for command-style input, such as editor bindings, rather than ordinary movement controls.

```zig
var keymap = try pixzig.input.KeyMap.init(alloc);
defer keymap.deinit();

_ = try keymap.addKeyChord(.{}, .g, "goto", null);
_ = try keymap.addTwoKeyChord(.{}, .g, .d, "goto_definition", null);

switch (keymap.update(eng.inputs.keyboard.currKeys(), deltaMs * 1000.0)) {
    .triggered => |chord| self.dispatchCommand(chord.func.?),
    else => {},
}
```

`KeyMap.update` takes elapsed microseconds. Chord timing defaults are defined in `pixzig.input.keychord`.
