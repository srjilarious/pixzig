//! Touch input: the fingers on the screen, and a virtual pad of on-screen
//! buttons and sticks laid out over the game.
//!
//! The pad feeds `ActionMap` like any other device. A binding names a pad
//! control (`touch_button`, `touch_stick`) or a stretch of screen a finger
//! drags across (`touch_drag`), so one bindings table serves every
//! platform: where there's no touchscreen, or no pad control by that name,
//! the binding simply reads as up / 0.
//!
//! A layout is declared once, in code (`addButton`, `addStick`) or in Lua
//! (`loadFromLua`), the same way bindings are:
//!
//! ```lua
//! touch = {
//!     sticks  = { { name = "move", anchor = "bottom_left", x = 110, y = 110, radius = 80 } },
//!     buttons = { { name = "a", anchor = "bottom_right", x = 80, y = 100, radius = 40, label = "A" } },
//! }
//! ```
//!
//! Positions and sizes are in density-independent pixels (dp), measured
//! inward from the anchor to the control's centre and kept inside the
//! screen's safe area (clear of notches and rounded corners), so a layout
//! looks the same size on a phone and a tablet. The engine draws the pad
//! over the game while touch is the input in use, and hides it once a key,
//! a real mouse or a gamepad is used instead.
//!
//! A finger belongs to whatever it first lands on: a stick (a little beyond
//! its ring, so a thumb needn't be exact), a button, or neither. Fingers on
//! neither are the ones `touch_drag` reads. A finger keeps its control
//! until it lifts, so a thumb that slides off a held button keeps it held.

const std = @import("std");
const common = @import("../common.zig");
const ScriptEngine = @import("../scripting.zig").ScriptEngine;
const Vec2F = common.Vec2F;
const RectF = common.RectF;

pub const MaxFingers = 10;
pub const MaxButtons = 16;
pub const MaxSticks = 4;

/// A control's name, stored inline so neither a layout nor an `ActionMap`
/// binding needs an allocator for it. Up to `capacity` bytes.
pub const Name = struct {
    buf: [capacity]u8 = undefined,
    len: u8 = 0,

    pub const capacity = 31;

    pub fn init(text: []const u8) !Name {
        if (text.len > capacity) return error.TouchNameTooLong;
        var n: Name = .{ .len = @intCast(text.len) };
        @memcpy(n.buf[0..text.len], text);
        return n;
    }

    pub fn slice(self: *const Name) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn eql(self: *const Name, text: []const u8) bool {
        return std.mem.eql(u8, self.slice(), text);
    }
};

/// The screen corner, edge midpoint or centre a control is placed from.
pub const Anchor = enum {
    top_left,
    top,
    top_right,
    left,
    center,
    right,
    bottom_left,
    bottom,
    bottom_right,
};

/// The part of the screen a `touch_drag` binding reads: fingers that
/// landed there, and on no control.
pub const DragRegion = enum {
    full,
    left_half,
    right_half,
    top_half,
    bottom_half,

    pub fn contains(self: DragRegion, screen: Vec2F, pos: Vec2F) bool {
        return switch (self) {
            .full => true,
            .left_half => pos.x < screen.x / 2,
            .right_half => pos.x >= screen.x / 2,
            .top_half => pos.y < screen.y / 2,
            .bottom_half => pos.y >= screen.y / 2,
        };
    }
};

/// One component of a 2-d touch value: across (`x`, right positive) or
/// down (`y`, down positive, as on screen).
pub const Component = enum { x, y };

/// A button's place on screen, as declared.
pub const ButtonDef = struct {
    name: []const u8,
    /// Short text drawn on the button, e.g. "A". Empty for none.
    label: []const u8 = "",
    anchor: Anchor = .bottom_right,
    /// Distance in dp from the anchor to the centre, inward.
    x: f32 = 80,
    y: f32 = 80,
    /// Radius in dp.
    radius: f32 = 36,
};

/// A stick's place on screen, as declared.
pub const StickDef = struct {
    name: []const u8,
    anchor: Anchor = .bottom_left,
    x: f32 = 110,
    y: f32 = 110,
    /// Radius of the stick's ring in dp: dragging the knob this far is a
    /// full deflection.
    radius: f32 = 70,
};

pub const Button = struct {
    name: Name,
    label: Name,
    anchor: Anchor,
    offset: Vec2F,
    radius: f32,
    /// Where the button is this tick, in framebuffer pixels.
    center: Vec2F = .{ .x = 0, .y = 0 },
    radiusPx: f32 = 0,
    /// Whether a finger is holding it.
    down: bool = false,
    /// Set when a finger lands on it, cleared at the end of the tick, so a
    /// tap that lands and lifts between two ticks still reads as down for
    /// one of them.
    tapped: bool = false,
};

pub const Stick = struct {
    name: Name,
    anchor: Anchor,
    offset: Vec2F,
    radius: f32,
    center: Vec2F = .{ .x = 0, .y = 0 },
    radiusPx: f32 = 0,
    /// Deflection, each component in [-1, +1] and the vector at most 1
    /// long. Zero while no finger holds it.
    value: Vec2F = .{ .x = 0, .y = 0 },
};

const Owner = union(enum) {
    none,
    button: usize,
    stick: usize,
};

const Finger = struct {
    id: u64,
    /// Where the finger landed and where it is now, in framebuffer pixels.
    start: Vec2F,
    pos: Vec2F,
    /// How far it has moved since the last tick, in framebuffer pixels.
    motion: Vec2F = .{ .x = 0, .y = 0 },
    owner: Owner,
};

/// How far beyond its ring a stick still catches a finger, as a multiple of
/// its radius, and the same for a button.
const stick_catch = 1.3;
const button_catch = 1.15;

pub const Touch = struct {
    buttons: [MaxButtons]Button = undefined,
    numButtons: usize = 0,
    sticks: [MaxSticks]Stick = undefined,
    numSticks: usize = 0,
    fingers: [MaxFingers]?Finger = @splat(null),
    /// Set when a finger lands, cleared when another kind of input is used.
    /// The pad is drawn only while this is set.
    active: bool = false,
    /// The screen in framebuffer pixels, density (framebuffer pixels per
    /// dp), and the safe area controls are kept inside. Refreshed by
    /// `layout` every tick.
    screen: Vec2F = .{ .x = 1, .y = 1 },
    dpScale: f32 = 1,
    safe: RectF = .{ .l = 0, .t = 0, .r = 1, .b = 1 },

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Whether any pad control is declared. With none, touches go on to SDL's
    /// mouse emulation, so mouse-driven games still work by touch.
    pub fn hasPad(self: *const Self) bool {
        return self.numButtons + self.numSticks > 0;
    }

    /// Whether the engine should draw the pad this frame.
    pub fn visible(self: *const Self) bool {
        return self.active and self.hasPad();
    }

    pub fn addButton(self: *Self, def: ButtonDef) !void {
        if (self.numButtons == MaxButtons) return error.TooManyTouchButtons;
        if (self.findButton(def.name) != null or self.findStick(def.name) != null) return error.DuplicateTouchControl;
        self.buttons[self.numButtons] = .{
            .name = try Name.init(def.name),
            .label = try Name.init(def.label),
            .anchor = def.anchor,
            .offset = .{ .x = def.x, .y = def.y },
            .radius = def.radius,
        };
        self.numButtons += 1;
        self.relayout();
    }

    pub fn addStick(self: *Self, def: StickDef) !void {
        if (self.numSticks == MaxSticks) return error.TooManyTouchSticks;
        if (self.findButton(def.name) != null or self.findStick(def.name) != null) return error.DuplicateTouchControl;
        self.sticks[self.numSticks] = .{
            .name = try Name.init(def.name),
            .anchor = def.anchor,
            .offset = .{ .x = def.x, .y = def.y },
            .radius = def.radius,
        };
        self.numSticks += 1;
        self.relayout();
    }

    /// Removes every control, releasing any fingers on them.
    pub fn clearLayout(self: *Self) void {
        self.numButtons = 0;
        self.numSticks = 0;
        for (&self.fingers) |*slot| {
            if (slot.*) |*f| f.owner = .none;
        }
    }

    pub fn buttonSlice(self: *const Self) []const Button {
        return self.buttons[0..self.numButtons];
    }

    pub fn stickSlice(self: *const Self) []const Stick {
        return self.sticks[0..self.numSticks];
    }

    pub fn findButton(self: *const Self, name: []const u8) ?usize {
        for (self.buttonSlice(), 0..) |*b, i| {
            if (b.name.eql(name)) return i;
        }
        return null;
    }

    pub fn findStick(self: *const Self, name: []const u8) ?usize {
        for (self.stickSlice(), 0..) |*s, i| {
            if (s.name.eql(name)) return i;
        }
        return null;
    }

    /// Whether the button `name` is held, or was tapped since the last
    /// tick. False when there is no such button.
    pub fn buttonDown(self: *const Self, name: []const u8) bool {
        const i = self.findButton(name) orelse return false;
        return self.buttons[i].down or self.buttons[i].tapped;
    }

    /// The stick `name`'s deflection, or zero when there is no such stick.
    pub fn stick(self: *const Self, name: []const u8) Vec2F {
        const i = self.findStick(name) orelse return .{ .x = 0, .y = 0 };
        return self.sticks[i].value;
    }

    /// This tick's movement, in dp, of the fingers on no control that
    /// landed in `region`.
    pub fn drag(self: *const Self, region: DragRegion) Vec2F {
        var sum: Vec2F = .{ .x = 0, .y = 0 };
        for (self.fingers) |slot| {
            const f = slot orelse continue;
            if (f.owner != .none or !region.contains(self.screen, f.start)) continue;
            sum.x += f.motion.x;
            sum.y += f.motion.y;
        }
        return .{ .x = sum.x / self.dpScale, .y = sum.y / self.dpScale };
    }

    /// Number of fingers down.
    pub fn fingerCount(self: *const Self) usize {
        var n: usize = 0;
        for (self.fingers) |slot| {
            if (slot != null) n += 1;
        }
        return n;
    }

    /// Places the controls for a screen of `screen` framebuffer pixels with
    /// `dpScale` pixels per dp, inside `safe`. The input manager calls it
    /// every tick, so a rotation or resize moves the pad with the screen.
    pub fn layout(self: *Self, screen: Vec2F, dpScale: f32, safe: RectF) void {
        self.screen = screen;
        self.dpScale = if (dpScale > 0) dpScale else 1;
        self.safe = safe;
        self.relayout();
    }

    fn relayout(self: *Self) void {
        for (self.buttons[0..self.numButtons]) |*b| {
            b.center = self.place(b.anchor, b.offset);
            b.radiusPx = b.radius * self.dpScale;
        }
        for (self.sticks[0..self.numSticks]) |*s| {
            s.center = self.place(s.anchor, s.offset);
            s.radiusPx = s.radius * self.dpScale;
        }
        self.refreshControls();
    }

    /// The framebuffer position `offset` dp inward from `anchor` of the
    /// safe area.
    fn place(self: *const Self, anchor: Anchor, offset: Vec2F) Vec2F {
        const s = self.safe;
        const dx = offset.x * self.dpScale;
        const dy = offset.y * self.dpScale;
        const mid_x = (s.l + s.r) / 2;
        const mid_y = (s.t + s.b) / 2;
        return switch (anchor) {
            .top_left => .{ .x = s.l + dx, .y = s.t + dy },
            .top => .{ .x = mid_x + dx, .y = s.t + dy },
            .top_right => .{ .x = s.r - dx, .y = s.t + dy },
            .left => .{ .x = s.l + dx, .y = mid_y + dy },
            .center => .{ .x = mid_x + dx, .y = mid_y + dy },
            .right => .{ .x = s.r - dx, .y = mid_y + dy },
            .bottom_left => .{ .x = s.l + dx, .y = s.b - dy },
            .bottom => .{ .x = mid_x + dx, .y = s.b - dy },
            .bottom_right => .{ .x = s.r - dx, .y = s.b - dy },
        };
    }

    /// A finger landed at `pos` (framebuffer pixels).
    pub fn fingerDown(self: *Self, id: u64, pos: Vec2F) void {
        self.active = true;
        const slot = self.slotFor(id) orelse self.freeSlot() orelse return;
        const owner = self.ownerAt(pos);
        slot.* = .{ .id = id, .start = pos, .pos = pos, .owner = owner };
        if (owner == .button) self.buttons[owner.button].tapped = true;
        self.refreshControls();
    }

    /// A finger moved to `pos`.
    pub fn fingerMove(self: *Self, id: u64, pos: Vec2F) void {
        const slot = self.slotFor(id) orelse return;
        const f = &slot.*.?;
        f.motion.x += pos.x - f.pos.x;
        f.motion.y += pos.y - f.pos.y;
        f.pos = pos;
        self.refreshControls();
    }

    /// A finger lifted (or the OS cancelled it).
    pub fn fingerUp(self: *Self, id: u64) void {
        const slot = self.slotFor(id) orelse return;
        slot.* = null;
        self.refreshControls();
    }

    /// Ends a tick: finger motion and taps count from here for the next one.
    pub fn finishTick(self: *Self) void {
        for (&self.fingers) |*slot| {
            if (slot.*) |*f| f.motion = .{ .x = 0, .y = 0 };
        }
        for (self.buttons[0..self.numButtons]) |*b| b.tapped = false;
    }

    /// Lifts every finger. The engine calls this on focus loss, when the OS
    /// stops sending the lifts.
    pub fn clear(self: *Self) void {
        self.fingers = @splat(null);
        for (self.buttons[0..self.numButtons]) |*b| b.tapped = false;
        self.refreshControls();
    }

    fn slotFor(self: *Self, id: u64) ?*?Finger {
        for (&self.fingers) |*slot| {
            if (slot.*) |f| {
                if (f.id == id) return slot;
            }
        }
        return null;
    }

    fn freeSlot(self: *Self) ?*?Finger {
        for (&self.fingers) |*slot| {
            if (slot.* == null) return slot;
        }
        return null;
    }

    fn ownerAt(self: *const Self, pos: Vec2F) Owner {
        // Sticks first: their catch area is the larger, and a thumb resting
        // on the edge of a stick means the stick.
        for (self.stickSlice(), 0..) |*s, i| {
            if (distance(pos, s.center) <= s.radiusPx * stick_catch) return .{ .stick = i };
        }
        for (self.buttonSlice(), 0..) |*b, i| {
            if (distance(pos, b.center) <= b.radiusPx * button_catch) return .{ .button = i };
        }
        return .none;
    }

    /// Recomputes button and stick state from the fingers holding them.
    fn refreshControls(self: *Self) void {
        for (self.buttons[0..self.numButtons]) |*b| b.down = false;
        for (self.sticks[0..self.numSticks]) |*s| s.value = .{ .x = 0, .y = 0 };
        for (self.fingers) |slot| {
            const f = slot orelse continue;
            switch (f.owner) {
                .none => {},
                .button => |i| if (i < self.numButtons) {
                    self.buttons[i].down = true;
                },
                .stick => |i| if (i < self.numSticks) {
                    const s = &self.sticks[i];
                    var v: Vec2F = .{
                        .x = (f.pos.x - s.center.x) / s.radiusPx,
                        .y = (f.pos.y - s.center.y) / s.radiusPx,
                    };
                    const len = @sqrt(v.x * v.x + v.y * v.y);
                    if (len > 1) {
                        v.x /= len;
                        v.y /= len;
                    }
                    s.value = v;
                },
            }
        }
    }

    /// Reads a layout from the Lua table in the global `global_name`, with
    /// `buttons` and `sticks` lists as in the module comment. Does nothing
    /// when the global isn't set, so a config without a pad loads on every
    /// platform.
    pub fn loadFromLua(self: *Self, script: *const ScriptEngine, global_name: []const u8) !void {
        const lua = script.lua;
        _ = script.getGlobal(global_name);
        defer lua.pop(1);
        if (lua.isNil(-1)) return;
        if (!lua.isTable(-1)) return error.InvalidTouchTable;
        const table = lua.absIndex(-1);

        _ = lua.getField(table, "sticks");
        defer lua.pop(1);
        if (lua.isTable(-1)) {
            const list = lua.absIndex(-1);
            for (0..lua.rawLen(list)) |i| {
                _ = lua.rawGetIndex(list, @intCast(i + 1));
                defer lua.pop(1);
                const entry = lua.absIndex(-1);
                const defaults: StickDef = .{ .name = "" };
                try self.addStick(.{
                    .name = try stringField(lua, entry, "name") orelse return error.MissingTouchName,
                    .anchor = try anchorField(lua, entry) orelse defaults.anchor,
                    .x = try numberField(lua, entry, "x") orelse defaults.x,
                    .y = try numberField(lua, entry, "y") orelse defaults.y,
                    .radius = try numberField(lua, entry, "radius") orelse defaults.radius,
                });
            }
        }

        _ = lua.getField(table, "buttons");
        defer lua.pop(1);
        if (lua.isTable(-1)) {
            const list = lua.absIndex(-1);
            for (0..lua.rawLen(list)) |i| {
                _ = lua.rawGetIndex(list, @intCast(i + 1));
                defer lua.pop(1);
                const entry = lua.absIndex(-1);
                const defaults: ButtonDef = .{ .name = "" };
                try self.addButton(.{
                    .name = try stringField(lua, entry, "name") orelse return error.MissingTouchName,
                    .label = try stringField(lua, entry, "label") orelse defaults.label,
                    .anchor = try anchorField(lua, entry) orelse defaults.anchor,
                    .x = try numberField(lua, entry, "x") orelse defaults.x,
                    .y = try numberField(lua, entry, "y") orelse defaults.y,
                    .radius = try numberField(lua, entry, "radius") orelse defaults.radius,
                });
            }
        }
    }
};

fn distance(a: Vec2F, b: Vec2F) f32 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return @sqrt(dx * dx + dy * dy);
}

/// The string at `entry[key]`, or null when it's nil. The slice is Lua's,
/// valid while the entry is on the stack.
fn stringField(lua: anytype, entry: i32, key: [:0]const u8) !?[]const u8 {
    _ = lua.getField(entry, key);
    defer lua.pop(1);
    if (lua.isNil(-1)) return null;
    return try lua.toString(-1);
}

fn numberField(lua: anytype, entry: i32, key: [:0]const u8) !?f32 {
    _ = lua.getField(entry, key);
    defer lua.pop(1);
    if (lua.isNil(-1)) return null;
    return @floatCast(try lua.toNumber(-1));
}

fn anchorField(lua: anytype, entry: i32) !?Anchor {
    const text = try stringField(lua, entry, "anchor") orelse return null;
    return std.meta.stringToEnum(Anchor, text) orelse error.UnknownTouchAnchor;
}
