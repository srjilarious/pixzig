# Input Handling

Pixzig provides double-buffered keyboard, mouse, and gamepad state, updated once per fixed-rate update tick. All input is accessed through `eng.keyboard`, `eng.mouse`, and `eng.gamepad` inside your `update` method.

## Keyboard

The `Keyboard` struct tracks key state across two frames, making it easy to detect single-frame transitions.

### Key State Queries

```zig
pub fn update(self: *App, eng: *AppRunner.Engine, _: f64) bool {
    // True every tick the key is physically held down.
    if (eng.keyboard.down(.left)) { self.x -= 3; }

    // True only on the first tick the key goes from up → down.
    if (eng.keyboard.pressed(.space)) { self.jump(); }

    // True only on the first tick the key goes from down → up.
    if (eng.keyboard.released(.space)) { self.landAnimation(); }

    // Quit on Escape.
    if (eng.keyboard.pressed(.escape)) return false;

    return true;
}
```

Keys are `glfw.Key` enum values: `.a`–`.z`, `.zero`–`.nine`, `.space`, `.enter`, `.escape`, `.left`, `.right`, `.up`, `.down`, `.left_shift`, `.left_control`, etc.

### Text Input

Convert the currently pressed key to a character (shift-aware):

```zig
if (eng.keyboard.text()) |ch| {
    // ch: u8 — ASCII character for the key pressed this tick, or null.
    self.inputBuffer.append(ch);
}
```

### Modifiers

```zig
const mods = eng.keyboard.currKeys().modifiers();
if (mods.shift()) { ... }
if (mods.ctrl())  { ... }
if (mods.alt())   { ... }
```

## Mouse

The `Mouse` struct tracks button state and cursor position.

```zig
// Button state (single-frame transitions)
if (eng.mouse.pressed(.left))   { self.onClick(eng.mouse.pos()); }
if (eng.mouse.released(.right)) { self.onRightRelease(); }
if (eng.mouse.down(.left))      { self.onDrag(); }

// Position (screen pixels)
const pos  = eng.mouse.pos();       // Vec2F — current position
const last = eng.mouse.lastPos();   // Vec2F — previous-frame position
const dx   = pos.x - last.x;        // frame delta
```

Mouse buttons are `.left`, `.right`, `.middle`.

## Gamepad

Gamepad support uses GLFW joystick detection. The first connected gamepad is automatically tracked.

```zig
if (eng.gamepad.isConnected()) {
    // Digital buttons
    if (eng.gamepad.pressed(.a))    { self.jump(); }
    if (eng.gamepad.down(.right))   { self.moveRight(); }

    // Analog axes (-1.0 to +1.0)
    const lx = eng.gamepad.axis(.left_x);
    const ly = eng.gamepad.axis(.left_y);
    self.velocity.x = lx * Speed;
    self.velocity.y = ly * Speed;
}
```

## Key Maps and Chords

For more complex input schemes — vim-style key sequences, hold-then-tap combos, or remappable actions — use `KeyMap` and the chord system.

### Defining a KeyMap

```zig
const input = pixzig.input;

var keymap = try input.KeyMap.init(alloc);
defer keymap.deinit(alloc);

// Single key: press 'g' → callback
try keymap.addKeyChord(alloc, .g, .{}, myCallback, &myContext);

// Two-key chord: press 'g' then 'd' → callback
try keymap.addTwoKeyChord(alloc, .g, .{}, .d, .{}, myCallback, &myContext);
```

### Updating the KeyMap

Call `keymap.update` from your `update` method, passing the current keyboard state:

```zig
_ = keymap.update(alloc, &eng.keyboard, deltaMs);
```

`update` returns a `ChordUpdateResult` (`none`, `reset`, or `triggered`) and fires the registered callback when a chord completes.

### Chord Timing

| Constant | Value | Purpose |
|---|---|---|
| `DefaultChordTimeoutUs` | 2 000 000 µs | Max gap between chord keys |
| `InitialRepeatRate` | 500 000 µs | Delay before key repeat starts |
| `DownRepeatRate` | 50 000 µs | Repeat interval once started |

Chords time out if the next key isn't pressed within `DefaultChordTimeoutUs`, resetting the state machine back to the root.
