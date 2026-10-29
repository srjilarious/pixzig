const std = @import("std");
const keys = @import("./keys.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const comp = @import("../comp.zig");
const gamepad = @import("./gamepad.zig");
const keyboard = @import("./keyboard.zig");
const KeyModifier = keyboard.KeyModifier;
const Mouse = @import("./mouse.zig").Mouse;
const InputManager = @import("./manager.zig").InputManager;
const ScriptEngine = @import("../scripting.zig").ScriptEngine;
const keychord = @import("./keychord.zig");
pub const KeyChordPiece = keychord.KeyChordPiece;
const touch = @import("./touch.zig");

/// A single digital (on/off) input source for an action binding.
/// `touch_button` names a button of the virtual pad (`InputManager.touch`);
/// it reads as up when the pad has no button by that name, e.g. on a
/// desktop with no pad declared.
pub const Source = union(enum) {
    key: keys.Key,
    // key_with_mods: struct {
    //     key: keys.Key,
    //     mods: KeyModifier,
    // },
    // chord: []const KeyChordPiece,
    mouse_button: keys.MouseButton,
    // mouse_axis: MouseAxis,
    gamepad_button: keys.GamepadButton,
    touch_button: touch.Name,
    // gamepad_axis: struct {
    //     // id: GamepadId = .any,
    //     axis: keys.GamepadAxis,
    //     deadzone: f32 = 0.18,
    //     scale: f32 = 1.0,
    //     invert: bool = false,
    // },
};

/// Which component of the mouse's per-frame movement delta a `mouse_axis`
/// binding reads.
pub const MouseAxis = enum { x, y };

/// A continuous (analog) input source for an axis binding.
/// `buttons` maps a negative/positive button pair to a [-1, +1] value.
/// `gamepad_axis` reads a physical stick or trigger with a configurable deadzone.
/// `mouse_axis` reads the mouse's raw per-frame movement delta (in window
/// pixels), scaled by `sensitivity` and clamped to `[-clamp, +clamp]`. Unlike
/// the other sources, its natural range isn't [-1, +1] -- `sensitivity` and
/// `clamp` together bound how far a single frame of mouse motion can turn or
/// move the game's response.
/// `touch_stick` reads one component of a virtual pad stick, in [-1, +1]
/// (y is down positive, as on screen; `invert` flips it).
/// `touch_drag` reads how far fingers dragged this tick across `region`
/// (fingers that landed on no pad control), in dp, scaled and clamped like
/// `mouse_axis`. Both read 0 where there's no such stick or no touchscreen.
pub const AxisSource = union(enum) {
    buttons: struct {
        negative: Source,
        positive: Source,
    },
    gamepad_axis: struct {
        axis: keys.GamepadAxis,
        deadzone: f32 = 0.18,
    },
    mouse_axis: struct {
        axis: MouseAxis,
        sensitivity: f32 = 1.0,
        clamp: f32 = 1.0,
    },
    touch_stick: struct {
        stick: touch.Name,
        component: touch.Component,
        invert: bool = false,
        deadzone: f32 = 0.15,
    },
    touch_drag: struct {
        region: touch.DragRegion = .full,
        component: touch.Component,
        sensitivity: f32 = 1.0,
        clamp: f32 = 1.0,
    },
};

/// A `touch_button` source for the pad button `name`, for binding from Zig:
/// `try actions.bind(.jump, try touchButton("a"))`.
pub fn touchButton(name: []const u8) !Source {
    return .{ .touch_button = try touch.Name.init(name) };
}

/// Reads an optional number field, or returns `default` when it's nil.
fn optNumber(lua: *Lua, entry_abs: i32, key: [:0]const u8, default: f32) !f32 {
    _ = lua.getField(entry_abs, key);
    defer lua.pop(1);
    if (lua.isNil(-1)) return default;
    return @floatCast(try lua.toNumber(-1));
}

/// Reads a required string field as an enum value.
fn enumField(comptime E: type, lua: *Lua, entry_abs: i32, key: [:0]const u8, err: anyerror) !E {
    _ = lua.getField(entry_abs, key);
    defer lua.pop(1);
    const text = try lua.toString(-1);
    return std.meta.stringToEnum(E, text) orelse err;
}

fn parseSource(lua: *Lua, entry_abs: i32) !Source {
    _ = lua.getField(entry_abs, "type");
    const type_str = try lua.toString(-1);
    const is_key = std.mem.eql(u8, type_str, "key");
    const is_mouse = std.mem.eql(u8, type_str, "mouse_button");
    const is_gpad = std.mem.eql(u8, type_str, "gamepad_button");
    const is_touch = std.mem.eql(u8, type_str, "touch_button");
    lua.pop(1);

    if (is_key) {
        _ = lua.getField(entry_abs, "key");
        defer lua.pop(1);
        const key_str = try lua.toString(-1);
        const key = std.meta.stringToEnum(keys.Key, key_str) orelse return error.UnknownKey;
        return .{ .key = key };
    } else if (is_mouse) {
        _ = lua.getField(entry_abs, "button");
        defer lua.pop(1);
        const btn_str = try lua.toString(-1);
        const btn = std.meta.stringToEnum(keys.MouseButton, btn_str) orelse return error.UnknownMouseButton;
        return .{ .mouse_button = btn };
    } else if (is_gpad) {
        _ = lua.getField(entry_abs, "button");
        defer lua.pop(1);
        const btn_str = try lua.toString(-1);
        const btn = std.meta.stringToEnum(keys.GamepadButton, btn_str) orelse return error.UnknownGamepadButton;
        return .{ .gamepad_button = btn };
    } else if (is_touch) {
        _ = lua.getField(entry_abs, "button");
        defer lua.pop(1);
        return .{ .touch_button = try touch.Name.init(try lua.toString(-1)) };
    } else {
        return error.UnknownSourceType;
    }
}

// Parses a single chord piece from a string like "ctrl+a", "ctrl+shift+f1", "space".
// Modifier tokens (ctrl, alt, shift, super) are case-insensitive. The key token
// must match a keys.Key field name (e.g. "a", "space", "f1", "enter").
fn parseChordPieceFromString(piece_str: []const u8) !KeyChordPiece {
    var mod = KeyModifier{};
    var key: ?keys.Key = null;

    var it = std.mem.splitScalar(u8, piece_str, '+');
    while (it.next()) |raw_token| {
        const token = std.mem.trim(u8, raw_token, " ");
        if (token.len == 0) continue;
        if (std.ascii.eqlIgnoreCase(token, "ctrl")) {
            mod.ctrl = true;
        } else if (std.ascii.eqlIgnoreCase(token, "alt")) {
            mod.alt = true;
        } else if (std.ascii.eqlIgnoreCase(token, "shift")) {
            mod.shift = true;
        } else if (std.ascii.eqlIgnoreCase(token, "super")) {
            mod.super = true;
        } else {
            var lower_buf: [32]u8 = undefined;
            const lower = std.ascii.lowerString(lower_buf[0..@min(token.len, lower_buf.len)], token);
            key = std.meta.stringToEnum(keys.Key, lower) orelse return error.UnknownKey;
        }
    }

    return KeyChordPiece.from(mod, key orelse return error.MissingChordKey);
}

fn parseAxisSource(lua: *Lua, entry_abs: i32) !AxisSource {
    _ = lua.getField(entry_abs, "type");
    const type_str = try lua.toString(-1);
    const is_buttons = std.mem.eql(u8, type_str, "buttons");
    const is_gpad_axis = std.mem.eql(u8, type_str, "gamepad_axis");
    const is_mouse_axis = std.mem.eql(u8, type_str, "mouse_axis");
    const is_touch_stick = std.mem.eql(u8, type_str, "touch_stick");
    const is_touch_drag = std.mem.eql(u8, type_str, "touch_drag");
    lua.pop(1);

    if (is_buttons) {
        _ = lua.getField(entry_abs, "neg");
        const neg_str = try lua.toString(-1);
        const neg_key = std.meta.stringToEnum(keys.Key, neg_str) orelse {
            lua.pop(1);
            return error.UnknownKey;
        };
        lua.pop(1);

        _ = lua.getField(entry_abs, "pos");
        const pos_str = try lua.toString(-1);
        const pos_key = std.meta.stringToEnum(keys.Key, pos_str) orelse {
            lua.pop(1);
            return error.UnknownKey;
        };
        lua.pop(1);

        return .{ .buttons = .{
            .negative = .{ .key = neg_key },
            .positive = .{ .key = pos_key },
        } };
    } else if (is_gpad_axis) {
        // Field is "stick", not "axis": the entry's "axis" key already names
        // the *target* game axis (e.g. "turn") this binding feeds; reusing it
        // here for the physical gamepad axis would silently clobber that
        // value in the Lua table literal (last write to a duplicate key wins).
        _ = lua.getField(entry_abs, "stick");
        const axis_str = try lua.toString(-1);
        const ax = std.meta.stringToEnum(keys.GamepadAxis, axis_str) orelse {
            lua.pop(1);
            return error.UnknownGamepadAxis;
        };
        lua.pop(1);

        _ = lua.getField(entry_abs, "deadzone");
        const deadzone: f32 = if (!lua.isNil(-1))
            @floatCast(try lua.toNumber(-1))
        else
            0.18;
        lua.pop(1);

        return .{ .gamepad_axis = .{ .axis = ax, .deadzone = deadzone } };
    } else if (is_mouse_axis) {
        // Field is "component" (x/y), not "axis" -- see the gamepad_axis
        // comment above for why: it would collide with the entry's own
        // top-level "axis" (target game axis) key.
        _ = lua.getField(entry_abs, "component");
        const axis_str = try lua.toString(-1);
        const ax = std.meta.stringToEnum(MouseAxis, axis_str) orelse {
            lua.pop(1);
            return error.UnknownMouseAxis;
        };
        lua.pop(1);

        _ = lua.getField(entry_abs, "sensitivity");
        const sensitivity: f32 = if (!lua.isNil(-1))
            @floatCast(try lua.toNumber(-1))
        else
            1.0;
        lua.pop(1);

        _ = lua.getField(entry_abs, "clamp");
        const clamp: f32 = if (!lua.isNil(-1))
            @floatCast(try lua.toNumber(-1))
        else
            1.0;
        lua.pop(1);

        return .{ .mouse_axis = .{ .axis = ax, .sensitivity = sensitivity, .clamp = clamp } };
    } else if (is_touch_stick) {
        _ = lua.getField(entry_abs, "stick");
        const name = touch.Name.init(try lua.toString(-1));
        lua.pop(1);

        _ = lua.getField(entry_abs, "invert");
        const invert = lua.toBoolean(-1);
        lua.pop(1);

        return .{ .touch_stick = .{
            .stick = try name,
            .component = try enumField(touch.Component, lua, entry_abs, "component", error.UnknownTouchComponent),
            .invert = invert,
            .deadzone = try optNumber(lua, entry_abs, "deadzone", 0.15),
        } };
    } else if (is_touch_drag) {
        _ = lua.getField(entry_abs, "region");
        const has_region = !lua.isNil(-1);
        lua.pop(1);

        return .{ .touch_drag = .{
            .region = if (has_region)
                try enumField(touch.DragRegion, lua, entry_abs, "region", error.UnknownTouchRegion)
            else
                .full,
            .component = try enumField(touch.Component, lua, entry_abs, "component", error.UnknownTouchComponent),
            .sensitivity = try optNumber(lua, entry_abs, "sensitivity", 1.0),
            .clamp = try optNumber(lua, entry_abs, "clamp", 1.0),
        } };
    } else {
        return error.UnknownAxisSourceType;
    }
}

/// Compile-time options for the engine-owned action map
/// (`EngineOptions.actionOpts`). When set, the engine creates an
/// `ActionMap(Action, Axes)` reached as `eng.actions` and `AppRunner` updates
/// it each tick before `App.update`.
pub const ActionOptions = struct {
    /// The enum naming the game's digital actions (jump, fire, quit, ...).
    Action: type,
    /// The enum naming the game's analog axes. Defaults to `NoAxes`.
    Axes: type = NoAxes,
};

/// The `Axes` enum for a game without analog axes. It has one value because
/// an empty enum can't be stored in a binding; `axis(.none)` always reads 0.
pub const NoAxes = enum { none };

/// Returns a comptime-specialised action map for the given `Action` and `Axes` enums.
///
/// Binds named actions/axes to physical inputs (keys, mouse buttons, gamepad axes) and
/// produces pressed/released/down/axis queries each tick.  Supports both direct bindings
/// and key-chord bindings for a single `Action` enum.  The returned type is heap-allocated
/// via `init`; call `deinit` to free.
pub fn ActionMap(comptime Action: type, comptime Axes: type) type {
    const DigitalBinding = struct {
        source: Source,
        action: Action,
    };

    const AnalogBinding = struct {
        source: AxisSource,
        axis: Axes,
    };

    const NumActions = comp.numEnumFields(Action);
    const NumAxes = comp.numEnumFields(Axes);

    const helpers = struct {
        fn getIndexForAction(action: Action) usize {
            const enumTypeInfo = @typeInfo(Action).@"enum";
            comptime var keyIdx: usize = 0;
            inline for (enumTypeInfo.field_names) |field_name| {
                const fieldKey = @field(Action, field_name);
                if (action == fieldKey) return keyIdx;
                keyIdx += 1;
            }

            return 0;
        }

        fn getIndexForAxis(ax: Axes) usize {
            const enumTypeInfo = @typeInfo(Axes).@"enum";
            comptime var keyIdx: usize = 0;
            inline for (enumTypeInfo.field_names) |field_name| {
                const fieldKey = @field(Axes, field_name);
                if (ax == fieldKey) return keyIdx;
                keyIdx += 1;
            }

            return 0;
        }
    };

    const DigitalActionState = struct {
        actions: std.StaticBitSet(NumActions),

        const InnerSelf = @This();

        pub fn init() InnerSelf {
            const actions = std.StaticBitSet(NumActions).empty;
            return .{ .actions = actions };
        }

        pub fn up(self: *const InnerSelf, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return !self.actions.isSet(actionIdx);
        }

        pub fn down(self: *const InnerSelf, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return self.actions.isSet(actionIdx);
        }

        pub fn downIdx(self: *const InnerSelf, actionIdx: usize) bool {
            return self.actions.isSet(actionIdx);
        }

        pub fn set(self: *InnerSelf, action: Action, val: bool) void {
            const actionIdx = helpers.getIndexForAction(action);
            self.setIdx(actionIdx, val);
        }

        pub fn setIdx(self: *InnerSelf, actionIdx: usize, val: bool) void {
            if (val) {
                self.actions.set(actionIdx);
            } else {
                self.actions.unset(actionIdx);
            }
        }

        pub fn clear(self: *InnerSelf) void {
            self.actions.setRangeValue(.{ .start = 0, .end = NumActions }, false);
        }
    };

    const AxisActionState = struct {
        axes: [NumAxes]f32,

        const InnerSelf = @This();

        pub fn init() InnerSelf {
            return .{ .axes = std.mem.zeroes([NumAxes]f32) };
        }

        pub fn set(self: *InnerSelf, axis: Axes, val: f32) void {
            const axisIdx = helpers.getIndexForAxis(axis);
            self.setIdx(axisIdx, val);
        }

        pub fn setIdx(self: *InnerSelf, axisIdx: usize, val: f32) void {
            self.axes[axisIdx] = val;
        }

        pub fn clear(self: *InnerSelf) void {
            for (0..NumAxes) |axisIdx| {
                self.axes[axisIdx] = 0;
            }
        }
    };

    return struct {
        alloc: std.mem.Allocator,
        digitalBindings: std.ArrayList(DigitalBinding),
        axisBindings: std.ArrayList(AnalogBinding),
        chordMap: keychord.KeyMap(Action),
        currIdx: usize,
        prevIdx: usize,
        digitalActionBuffers: [2]DigitalActionState,
        axisActionBuffers: [2]AxisActionState,

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator) !*Self {
            var chordMap = try keychord.KeyMap(Action).init(alloc);
            errdefer chordMap.deinit();
            const actions = try alloc.create(Self);
            actions.* = .{
                .alloc = alloc,
                .digitalBindings = .empty,
                .axisBindings = .empty,
                .chordMap = chordMap,
                .prevIdx = 0,
                .currIdx = 1,
                .digitalActionBuffers = .{
                    DigitalActionState.init(),
                    DigitalActionState.init(),
                },
                .axisActionBuffers = .{
                    AxisActionState.init(),
                    AxisActionState.init(),
                },
            };
            return actions;
        }

        pub fn deinit(self: *Self) void {
            self.digitalBindings.deinit(self.alloc);
            self.axisBindings.deinit(self.alloc);
            self.chordMap.deinit();
            self.alloc.destroy(self);
        }

        /// Reads bindings from a Lua table stored in the global `global_name`.
        /// Each entry is a table with an `action` or `axis` string key and a `type` field.
        /// Supported types: `"key"`, `"mouse_button"`, `"gamepad_button"`, `"touch_button"`, `"chord"`,
        /// `"buttons"`, `"gamepad_axis"`, `"mouse_axis"`, `"touch_stick"`, `"touch_drag"`.
        pub fn loadFromLua(self: *Self, script: *const ScriptEngine, global_name: []const u8) !void {
            const lua = script.lua;

            _ = script.getGlobal(global_name);
            defer lua.pop(1);

            if (!lua.isTable(-1)) return error.InvalidBindingsTable;

            const table_abs = lua.absIndex(-1);
            const len = lua.rawLen(table_abs);

            for (0..len) |raw_i| {
                const i: ziglua.Integer = @intCast(raw_i + 1);
                _ = lua.rawGetIndex(table_abs, i);
                defer lua.pop(1);

                if (!lua.isTable(-1)) return error.InvalidBindingEntry;
                const entry_abs = lua.absIndex(-1);

                _ = lua.getField(entry_abs, "action");
                const has_action = !lua.isNil(-1);
                lua.pop(1);

                if (has_action) {
                    _ = lua.getField(entry_abs, "action");
                    const action_str = try lua.toString(-1);
                    const act = std.meta.stringToEnum(Action, action_str) orelse {
                        lua.pop(1);
                        return error.UnknownAction;
                    };
                    lua.pop(1);

                    _ = lua.getField(entry_abs, "type");
                    const type_str = try lua.toString(-1);
                    const is_chord = std.mem.eql(u8, type_str, "chord");
                    lua.pop(1);

                    if (is_chord) {
                        _ = lua.getField(entry_abs, "key");
                        defer lua.pop(1);
                        const chord_str = try lua.toString(-1);

                        var pieces: [2]KeyChordPiece = undefined;
                        var num_pieces: usize = 0;
                        var piece_it = std.mem.splitScalar(u8, chord_str, ' ');
                        while (piece_it.next()) |piece_str| {
                            if (piece_str.len == 0) continue;
                            if (num_pieces >= 2) return error.InvalidChordPieceCount;
                            pieces[num_pieces] = try parseChordPieceFromString(piece_str);
                            num_pieces += 1;
                        }

                        if (num_pieces == 0) return error.InvalidChordPieceCount;
                        if (num_pieces == 1) {
                            try self.bindChord(pieces[0], act);
                        } else {
                            try self.bindChord2(pieces[0], pieces[1], act);
                        }
                    } else {
                        const source = try parseSource(lua, entry_abs);
                        try self.bind(act, source);
                    }
                } else {
                    _ = lua.getField(entry_abs, "axis");
                    if (lua.isNil(-1)) {
                        lua.pop(1);
                        return error.MissingActionOrAxis;
                    }
                    const axis_str = try lua.toString(-1);
                    const ax = std.meta.stringToEnum(Axes, axis_str) orelse {
                        lua.pop(1);
                        return error.UnknownAxis;
                    };
                    lua.pop(1);

                    const axis_source = try parseAxisSource(lua, entry_abs);
                    try self.bindAxis(ax, axis_source);
                }
            }
        }

        pub fn currDigital(self: *const Self) *const DigitalActionState {
            return &self.digitalActionBuffers[self.currIdx];
        }

        pub fn currDigitalPtr(self: *Self) *DigitalActionState {
            return &self.digitalActionBuffers[self.currIdx];
        }

        pub fn prevDigital(self: *const Self) *const DigitalActionState {
            return &self.digitalActionBuffers[self.prevIdx];
        }

        pub fn currAxis(self: *const Self) *const AxisActionState {
            return &self.axisActionBuffers[self.currIdx];
        }

        pub fn currAxisPtr(self: *Self) *AxisActionState {
            return &self.axisActionBuffers[self.currIdx];
        }

        /// Binds a digital action to a physical input source.  Multiple bindings for the
        /// same action are OR-ed together each tick.
        pub fn bind(self: *Self, action: Action, source: Source) !void {
            try self.digitalBindings.append(self.alloc, .{ .source = source, .action = action });
        }

        /// Binds a continuous axis to an analog source.
        pub fn bindAxis(self: *Self, ax: Axes, source: AxisSource) !void {
            try self.axisBindings.append(self.alloc, .{ .source = source, .axis = ax });
        }

        /// Binds a single-key chord to an action.
        pub fn bindChord(self: *Self, piece: KeyChordPiece, action: Action) !void {
            _ = try self.chordMap.addKeyChord(piece.mod, piece.key, action, null);
        }

        /// Binds a two-key chord to an action.
        pub fn bindChord2(self: *Self, piece1: KeyChordPiece, piece2: KeyChordPiece, action: Action) !void {
            _ = try self.chordMap.addComplexChord(piece1, piece2, action, null);
        }

        fn isSourceDown(source: Source, inputs: *const InputManager) bool {
            switch (source) {
                .key => |k| return inputs.keyboard.down(k),
                .mouse_button => |m| {
                    if (!inputs.mouseEnabled) return false;
                    return inputs.mouse.down(m);
                },
                .gamepad_button => |btn| {
                    if (inputs.numGamepads == 0) return false;
                    return inputs.gamepads[0].down(btn);
                },
                .touch_button => |name| return inputs.touch.buttonDown(name.slice()),
            }
        }

        fn swapBuffers(self: *Self) void {
            const temp = self.currIdx;
            self.currIdx = self.prevIdx;
            self.prevIdx = temp;
        }

        /// Advances the action state by one tick, reading from `inputs`.
        /// `deltaMs` is used for chord timeout and repeat tracking; pass 0 if not using chords.
        pub fn update(self: *Self, inputs: *const InputManager, deltaMs: f64) void {
            self.swapBuffers();

            var curr = self.currDigitalPtr();
            curr.clear();

            for (self.digitalBindings.items) |binding| {
                if (isSourceDown(binding.source, inputs)) {
                    curr.set(binding.action, true);
                }
            }

            _ = self.chordMap.update(inputs.keyboard.currKeys(), deltaMs);
            if (self.chordMap.chords.downKey != .unknown) {
                if (self.chordMap.chords.currChord) |chord| {
                    if (chord.func) |action| {
                        curr.set(action, true);
                    }
                }
            }

            var currAxes = self.currAxisPtr();
            currAxes.clear();

            for (self.axisBindings.items) |binding| {
                var val: f32 = 0.0;
                switch (binding.source) {
                    .buttons => |b| {
                        const neg = isSourceDown(b.negative, inputs);
                        const pos = isSourceDown(b.positive, inputs);
                        if (neg and !pos) {
                            val = -1.0;
                        } else if (!neg and pos) {
                            val = 1.0;
                        }
                    },
                    .gamepad_axis => |ga| {
                        if (inputs.numGamepads > 0) {
                            val = inputs.gamepads[0].axis(ga.axis);
                            if (@abs(val) < ga.deadzone) val = 0;
                        }
                    },
                    .mouse_axis => |ma| {
                        if (inputs.mouseEnabled) {
                            const motion = inputs.mouse.delta();
                            const delta: f32 = switch (ma.axis) {
                                .x => motion.x,
                                .y => motion.y,
                            };
                            val = std.math.clamp(delta * ma.sensitivity, -ma.clamp, ma.clamp);
                        }
                    },
                    .touch_stick => |ts| {
                        const v = inputs.touch.stick(ts.stick.slice());
                        val = switch (ts.component) {
                            .x => v.x,
                            .y => v.y,
                        };
                        if (@abs(val) < ts.deadzone) val = 0;
                        if (ts.invert) val = -val;
                    },
                    .touch_drag => |td| {
                        const d = inputs.touch.drag(td.region);
                        const delta: f32 = switch (td.component) {
                            .x => d.x,
                            .y => d.y,
                        };
                        val = std.math.clamp(delta * td.sensitivity, -td.clamp, td.clamp);
                    },
                }
                // Multiple bindings on the same axis (e.g. arrow keys and
                // WASD both bound to "turn", or keyboard turning combined
                // with mouse look) accumulate rather than overwrite one
                // another -- each contributes its own value for the frame.
                const axisIdx = helpers.getIndexForAxis(binding.axis);
                currAxes.axes[axisIdx] += val;
            }
        }

        /// Advances one tick as if nothing were held: every action is up,
        /// every axis is 0 and any partial chord is dropped. Actions held on
        /// the previous tick report `released`. The engine calls this instead
        /// of `update` while its console is open.
        pub fn updateSuppressed(self: *Self) void {
            self.swapBuffers();
            self.currDigitalPtr().clear();
            self.currAxisPtr().clear();
            self.chordMap.reset();
        }

        /// True when the action is not held this tick.
        pub fn up(self: *const Self, action: Action) bool {
            return self.currDigital().up(action);
        }

        /// True while the action is held this tick.
        pub fn down(self: *const Self, action: Action) bool {
            return self.currDigital().down(action);
        }

        /// Returns the current value of an analog axis in [-1, +1].
        pub fn axis(self: *const Self, ax: Axes) f32 {
            const axisIdx = helpers.getIndexForAxis(ax);
            return self.currAxis().axes[axisIdx];
        }

        /// True on the first tick the action becomes held (rising edge).
        pub fn pressed(self: *const Self, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return (self.currDigital().downIdx(actionIdx) and !self.prevDigital().downIdx(actionIdx));
        }

        /// True on the first tick the action is no longer held (falling edge).
        pub fn released(self: *const Self, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return (!self.currDigital().downIdx(actionIdx) and self.prevDigital().downIdx(actionIdx));
        }
    };
}
