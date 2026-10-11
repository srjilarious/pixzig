# Immediate-Mode UI

`imgui.UiContext` is a small immediate-mode UI for debug panels, level editors and simple menus. Immediate mode means there are no widget objects to create or keep in sync. Each frame you call `button(...)`, and it draws the button and tells you whether it was clicked.

It draws through the normal renderer, so it uses the default font and needs shape and text rendering (both on by default).

## Setting It Up

```zig
const AppRunner = pixzig.AppRunner(App, .{
    .inputOpts = .{ .textInput = true }, // only needed for text fields
});
const UiContext = pixzig.imgui.UiContext(AppRunner.Engine);

pub const App = struct {
    ui: UiContext,
    panel: pixzig.RectF = pixzig.RectF.fromPosSize(20, 20, 260, 200),
    volume: f32 = 0.5,
    muted: bool = false,

    // In init:
    //     app.ui = UiContext.init(eng);
    //     app.ui.setClipboardWindow(eng.window); // enables Ctrl+C / Ctrl+V in text fields
};
```

The UI reads input in `update` and draws in `render`. Call `ui.update()` once per tick, and wrap your widgets in `ui.begin()`/`ui.end()` inside a renderer pass:

```zig
pub fn update(self: *App, eng: *AppRunner.Engine, _: f64) bool {
    self.ui.update();
    return !eng.inputs.keyboard.pressed(.escape);
}

pub fn render(self: *App, eng: *AppRunner.Engine) void {
    eng.renderer.clear(30, 30, 60, 255);
    eng.renderer.begin(.logical);
    self.ui.begin();

    self.ui.beginWindow("settings", "Settings", &self.panel);
    self.ui.label("Volume");
    _ = self.ui.slider("volume", &self.volume, 0.0, 1.0);
    _ = self.ui.checkbox("muted", "Mute", &self.muted);
    if (self.ui.button("close", "Close")) self.showSettings = false;
    self.ui.endWindow();

    self.ui.end();
    eng.renderer.end();
}
```

Use the `.logical` pass so the UI matches the mouse coordinates.

## IDs and State

Every interactive widget takes an `id` string. It has to be unique among the widgets drawn that frame, and stay the same from frame to frame, because that's how the UI knows which widget is being hovered, dragged or typed into. The label is separate, so two buttons can both say "OK" with different ids.

The UI doesn't store your values. You own them and pass pointers in: the window's rect, the slider's float, the checkbox's bool, the text field's buffer. Widgets that change something return true on the frame it changed.

## Windows

`beginWindow(id, title, &rect)` starts a window with a title bar. The user can drag it by the title and resize it from the bottom-right corner, and both update your `rect`. Content that's too tall scrolls with the mouse wheel. Every `beginWindow` needs a matching `endWindow`.

`resizeWindowToSide(&rect, .left, 0.3, eng.viewport.logicalSize)` docks a window against a screen edge, taking a fraction of the width (for `.left`/`.right`) or height (for `.up`/`.down`).

## Layout

Widgets stack top to bottom and fill the window's width. A few helpers adjust that:

| Call | What it does |
|---|---|
| `sameLine()` | Put the next widget to the right of the last one. |
| `spacing()` | Add a little vertical space. |
| `contentWidth()` | The usable width, for sizing side-by-side widgets. |
| `remainingHeight()` | The space left in the window, for a text area that fills the rest. |

Two buttons side by side:

```zig
const w = (self.ui.contentWidth() - @as(f32, @floatFromInt(self.ui.style.itemSpacing))) / 2.0;
const ok = self.ui.buttonSized("ok", "OK", w);
self.ui.sameLine();
const cancel = self.ui.buttonSized("cancel", "Cancel", w);
```

## Widgets

| Widget | Returns |
|---|---|
| `label(text)` | Nothing. |
| `image(texture, size)` | Nothing. Draws a texture or atlas frame. |
| `button(id, label)`, `buttonSized(id, label, width)` | True when clicked. |
| `buttonEx(id, label, disabled)` | A `ButtonResult` with `clicked` and the visual `state`. |
| `checkbox(id, label, &bool)`, `toggle(...)` | True when changed. |
| `slider(id, &f32, min, max)` | True when changed. |
| `inputInt(id, &i32)` | True when changed. |
| `inputText(id, buf, &len)` | True when the text changed. |
| `inputTextEx(id, buf, &len, opts)` | An `InputTextResult`. See below. |
| `selectable(id, label, selected)` | True when clicked. |
| `selectableList(id, items, &selected, &scroll, height)` | True when the selection changed. |
| `textArea(id, lines, &scroll, height)` | Nothing. A scrolling, read-only list of lines. |

### Text Fields

A text field edits a buffer you own. `len` is how much of it is in use:

```zig
// In App:
nameBuf: [64]u8 = undefined,
nameLen: usize = 0,

// In render:
const res = self.ui.inputTextEx("name", &self.nameBuf, &self.nameLen, .{ .submitOnEnter = true });
if (res.submitted) self.setName(self.nameBuf[0..self.nameLen]);
```

Text fields need `inputOpts.textInput = true`, or nothing can be typed. Click one or Tab to it to focus it. Arrow keys, Home, End, Backspace and Delete edit as you'd expect. With `setClipboardWindow` called, Ctrl+C copies the whole field and Ctrl+V pastes. Ctrl+L clears it.

`InputTextOptions` turns on `submitOnEnter` and `historyKeys`. With `historyKeys`, Up and Down set `historyPrev`/`historyNext` in the result instead of doing nothing, which is how the console steps through past commands.

`focusWidget(id)` gives a widget keyboard focus from code, for instance to focus a field when a dialog opens.

## Styling

`ui.style` holds every color and size the UI uses: window and button colors, padding, item spacing, widget heights and so on. Change fields on it directly, before drawing:

```zig
self.ui.style.buttonNormal = Color.from(40, 80, 40, 255);
self.ui.style.padding = .{ .x = 4, .y = 4 };
```

`examples/imgui_ex.zig` uses every widget, including two windows you can dock to the screen edges.
