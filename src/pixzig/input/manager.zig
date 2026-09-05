const std = @import("std");
const sdl = @import("sdl3");
const windowing = @import("../window.zig");
const common = @import("../common.zig");
const Vec2F = common.Vec2F;
const keys = @import("./keys.zig");
const keyboard_mod = @import("./keyboard.zig");
const Keyboard = keyboard_mod.Keyboard;
const KeyModifier = keyboard_mod.KeyModifier;
const Mouse = @import("./mouse.zig").Mouse;
const gamepad_mod = @import("./gamepad.zig");
const Gamepad = gamepad_mod.Gamepad;

/// Maximum number of gamepads that an InputManager can own.
pub const MaxGamepads: u8 = 4;

/// Runtime options for configuring which input subsystems the InputManager
/// owns and updates.  Passed to `InputManager.init()`.
pub const InputOptions = struct {
    /// Whether to update the Mouse each tick and expose logical coordinates.
    mouse: bool = true,
    /// Number of gamepads to own and update (controller slots 0..numGamepads-1).
    /// Clamped to MaxGamepads at init time.
    numGamepads: u8 = 0,
    /// Whether to arm the OS text-input machinery on the window.
    ///
    /// This is what makes `Keyboard.text()` produce anything and what
    /// enables IME composition (`Keyboard.preedit()`). It is off by
    /// default: on some platforms an armed text input changes on-screen
    /// keyboard behaviour, and a game that only reads key bindings does
    /// not want an IME candidate bar appearing over it.
    textInput: bool = false,
};

/// Owns and updates all input subsystems for a single player session.
/// Keyboard is always present.  Mouse and gamepads are activated via the
/// `opts` passed to `init()` and updated based on the runtime flags stored
/// in `mouse_enabled` and `num_gamepads`.
pub const InputManager = struct {
    mouse_enabled: bool,
    num_gamepads: u8,
    keyboard: Keyboard,
    mouse: Mouse,
    gamepads: [MaxGamepads]Gamepad,

    const Self = @This();

    pub fn init(opts: InputOptions) Self {
        const n = @min(opts.numGamepads, MaxGamepads);
        var result: Self = .{
            .mouse_enabled = opts.mouse,
            .num_gamepads = n,
            .keyboard = Keyboard.init(),
            .mouse = Mouse.init(),
            .gamepads = undefined,
        };
        for (0..MaxGamepads) |i| {
            result.gamepads[i] = Gamepad.init(i);
        }
        if (n > 0) gamepad_mod.initSubsystem();
        return result;
    }

    pub fn deinit(self: *Self) void {
        for (0..self.num_gamepads) |i| {
            self.gamepads[i].deinit();
        }
    }

    /// Routes one SDL event into the subsystem it belongs to. Called from
    /// `PixzigEngine.pollEvents` for every event that isn't a window-level
    /// one the engine handles itself.
    ///
    /// This replaces the GLFW backend's per-callback module-level target
    /// pointers (`setKeyboardTarget` / `setScrollTarget`) and the
    /// one-Keyboard-at-a-time limitation they imposed: SDL is polled, so
    /// the engine can hand events straight to whichever manager it owns.
    pub fn handleEvent(self: *Self, event: sdl.SDL_Event) void {
        switch (event.type) {
            sdl.SDL_EVENT_KEY_DOWN, sdl.SDL_EVENT_KEY_UP => {
                self.keyboard.setKey(
                    keys.fromScancode(event.key.scancode),
                    keys.fromKeycode(event.key.key),
                    event.key.down,
                );
                self.keyboard.setModsFromEvent(modsFromSdl(event.key.mod));
            },
            sdl.SDL_EVENT_TEXT_INPUT => {
                self.keyboard.pushText(std.mem.span(event.text.text));
                // A commit ends the composition. SDL doesn't reliably
                // follow it with an empty editing event, so drop the
                // preedit here or the committed text stays ghosted at the
                // caret.
                self.keyboard.clearPreedit();
            },
            sdl.SDL_EVENT_TEXT_EDITING => {
                const composing = if (event.edit.text) |t| std.mem.span(t) else "";
                if (composing.len == 0) {
                    self.keyboard.clearPreedit();
                } else {
                    self.keyboard.setPreedit(composing, event.edit.start);
                }
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                if (self.mouse_enabled) self.mouse.curr_mut().setRawPos(event.motion.x, event.motion.y);
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                if (!self.mouse_enabled) return;
                var state = self.mouse.curr_mut();
                state.setRawPos(event.button.x, event.button.y);
                if (keys.fromSdlMouseButton(event.button.button)) |btn| {
                    state.set(btn, event.button.down);
                }
            },
            sdl.SDL_EVENT_MOUSE_WHEEL => {
                if (!self.mouse_enabled) return;
                var dx = event.wheel.x;
                var dy = event.wheel.y;
                if (event.wheel.direction == sdl.SDL_MOUSEWHEEL_FLIPPED) {
                    dx = -dx;
                    dy = -dy;
                }
                var state = self.mouse.curr_mut();
                state.scroll_delta.x += dx;
                state.scroll_delta.y += dy;
            },
            else => {},
        }
    }

    /// Advances all active input subsystems by one tick.  Call after the
    /// event pump has run and before `app.update()`, and pair it with
    /// `finishTick()` after.
    ///
    /// `scale_factor` is `WindowState.scale_factor` (framebuffer/window
    /// ratio).  `viewport` is used to map the cursor position into logical
    /// game coordinates for `mouse.pos()`.
    pub fn update(
        self: *Self,
        scale_factor: Vec2F,
        viewport: *const windowing.Viewport,
    ) void {
        _ = self.keyboard.update();

        if (self.mouse_enabled) {
            const raw = self.mouse.rawPos();
            const fb = Vec2F{ .x = raw.x * scale_factor.x, .y = raw.y * scale_factor.y };
            self.mouse.curr_mut().fb_pos = fb;
            self.mouse.curr_mut().logical_pos =
                viewport.framebufferToLogical(fb) orelse Vec2F{ .x = -1, .y = -1 };
        }

        for (0..self.num_gamepads) |i| {
            _ = self.gamepads[i].update();
        }
    }

    /// Ends a tick, rolling the current keyboard and mouse state into the
    /// previous one so the next tick's `pressed`/`released` edges are
    /// measured against it.
    pub fn finishTick(self: *Self) void {
        self.keyboard.finishTick();
        if (self.mouse_enabled) self.mouse.finishTick();
    }

    /// Drops all key and button state. The engine calls this on window
    /// focus loss: an event-driven bitset latches where the GLFW backend's
    /// per-tick polling self-healed, so without this a key held while the
    /// window loses focus stays down forever.
    pub fn clear(self: *Self) void {
        self.keyboard.clear();
        self.mouse.clear();
    }

    /// Returns a pointer to the gamepad at the given index.
    pub fn gamepad(self: *Self, idx: usize) *Gamepad {
        return &self.gamepads[idx];
    }
};

/// Translates SDL's modifier bitfield into the engine's KeyModifier.
fn modsFromSdl(mods: sdl.SDL_Keymod) KeyModifier {
    return .{
        .ctrl = (mods & sdl.SDL_KMOD_CTRL) != 0,
        .alt = (mods & sdl.SDL_KMOD_ALT) != 0,
        .shift = (mods & sdl.SDL_KMOD_SHIFT) != 0,
        .super = (mods & sdl.SDL_KMOD_GUI) != 0,
    };
}
