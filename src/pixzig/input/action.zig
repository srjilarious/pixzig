const std = @import("std");
const glfw = @import("zglfw");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const comp = @import("../comp.zig");
const gamepad = @import("./gamepad.zig");
const keyboard = @import("./keyboard.zig");
const KeyModifier = keyboard.KeyModifier;
const Mouse = @import("./mouse.zig").Mouse;
const InputManager = @import("./manager.zig").InputManager;
const ScriptEngine = @import("../scripting.zig").ScriptEngine;

pub const Source = union(enum) {
    key: glfw.Key,
    // key_with_mods: struct {
    //     key: glfw.Key,
    //     mods: KeyModifier,
    // },
    // chord: []const KeyChordPiece,
    mouse_button: glfw.MouseButton,
    // mouse_axis: MouseAxis,
    gamepad_button: glfw.Gamepad.Button,
    // gamepad_axis: struct {
    //     // id: GamepadId = .any,
    //     axis: glfw.Gamepad.Axis,
    //     deadzone: f32 = 0.18,
    //     scale: f32 = 1.0,
    //     invert: bool = false,
    // },
};

pub const AxisSource = union(enum) {
    buttons: struct {
        negative: Source,
        positive: Source,
    },
    gamepad_axis: struct {
        axis: glfw.Gamepad.Axis,
        deadzone: f32 = 0.18,
    },
};

fn parseSource(lua: *Lua, entry_abs: i32) !Source {
    _ = lua.getField(entry_abs, "type");
    const type_str = try lua.toString(-1);
    const is_key = std.mem.eql(u8, type_str, "key");
    const is_mouse = std.mem.eql(u8, type_str, "mouse_button");
    const is_gpad = std.mem.eql(u8, type_str, "gamepad_button");
    lua.pop(1);

    if (is_key) {
        _ = lua.getField(entry_abs, "key");
        defer lua.pop(1);
        const key_str = try lua.toString(-1);
        const key = std.meta.stringToEnum(glfw.Key, key_str) orelse return error.UnknownKey;
        return .{ .key = key };
    } else if (is_mouse) {
        _ = lua.getField(entry_abs, "button");
        defer lua.pop(1);
        const btn_str = try lua.toString(-1);
        const btn = std.meta.stringToEnum(glfw.MouseButton, btn_str) orelse return error.UnknownMouseButton;
        return .{ .mouse_button = btn };
    } else if (is_gpad) {
        _ = lua.getField(entry_abs, "button");
        defer lua.pop(1);
        const btn_str = try lua.toString(-1);
        const btn = std.meta.stringToEnum(glfw.Gamepad.Button, btn_str) orelse return error.UnknownGamepadButton;
        return .{ .gamepad_button = btn };
    } else {
        return error.UnknownSourceType;
    }
}

fn parseAxisSource(lua: *Lua, entry_abs: i32) !AxisSource {
    _ = lua.getField(entry_abs, "type");
    const type_str = try lua.toString(-1);
    const is_buttons = std.mem.eql(u8, type_str, "buttons");
    const is_gpad_axis = std.mem.eql(u8, type_str, "gamepad_axis");
    lua.pop(1);

    if (is_buttons) {
        _ = lua.getField(entry_abs, "neg");
        const neg_str = try lua.toString(-1);
        const neg_key = std.meta.stringToEnum(glfw.Key, neg_str) orelse {
            lua.pop(1);
            return error.UnknownKey;
        };
        lua.pop(1);

        _ = lua.getField(entry_abs, "pos");
        const pos_str = try lua.toString(-1);
        const pos_key = std.meta.stringToEnum(glfw.Key, pos_str) orelse {
            lua.pop(1);
            return error.UnknownKey;
        };
        lua.pop(1);

        return .{ .buttons = .{
            .negative = .{ .key = neg_key },
            .positive = .{ .key = pos_key },
        } };
    } else if (is_gpad_axis) {
        _ = lua.getField(entry_abs, "axis");
        const axis_str = try lua.toString(-1);
        const ax = std.meta.stringToEnum(glfw.Gamepad.Axis, axis_str) orelse {
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
    } else {
        return error.UnknownAxisSourceType;
    }
}

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
            inline for (enumTypeInfo.fields) |field| {
                const fieldKey = @field(Action, field.name);
                if (action == fieldKey) return keyIdx;
                keyIdx += 1;
            }

            return 0;
        }

        fn getIndexForAxis(ax: Axes) usize {
            const enumTypeInfo = @typeInfo(Axes).@"enum";
            comptime var keyIdx: usize = 0;
            inline for (enumTypeInfo.fields) |field| {
                const fieldKey = @field(Axes, field.name);
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
            const actions = std.StaticBitSet(NumActions).initEmpty();
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
        currIdx: usize,
        prevIdx: usize,
        digitalActionBuffers: [2]DigitalActionState,
        axisActionBuffers: [2]AxisActionState,

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator) !*Self {
            const actions = try alloc.create(Self);
            actions.* = .{
                .alloc = alloc,
                .digitalBindings = .empty,
                .axisBindings = .empty,
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
            self.alloc.destroy(self);
        }

        pub fn loadFromLua(self: *Self, script: *const ScriptEngine, global_name: [:0]const u8) !void {
            const lua = script.lua;

            _ = try lua.getGlobal(global_name);
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

                    const source = try parseSource(lua, entry_abs);
                    try self.bind(act, source);
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

        pub fn currDigital_mut(self: *Self) *DigitalActionState {
            return &self.digitalActionBuffers[self.currIdx];
        }

        pub fn prevDigital(self: *const Self) *const DigitalActionState {
            return &self.digitalActionBuffers[self.prevIdx];
        }

        pub fn currAnalog(self: *const Self) *const AxisActionState {
            return &self.axisActionBuffers[self.currIdx];
        }

        pub fn currAxis_mut(self: *Self) *AxisActionState {
            return &self.axisActionBuffers[self.currIdx];
        }

        pub fn bind(self: *Self, action: Action, source: Source) !void {
            try self.digitalBindings.append(self.alloc, .{ .source = source, .action = action });
        }

        pub fn bindAxis(self: *Self, ax: Axes, source: AxisSource) !void {
            try self.axisBindings.append(self.alloc, .{ .source = source, .axis = ax });
        }

        fn isSourceDown(source: Source, inputs: *const InputManager) bool {
            switch (source) {
                .key => |k| return inputs.keyboard.down(k),
                .mouse_button => |m| {
                    if (!inputs.mouse_enabled) return false;
                    return inputs.mouse.down(m);
                },
                .gamepad_button => |btn| {
                    if (inputs.num_gamepads == 0) return false;
                    return inputs.gamepads[0].down(btn);
                },
            }
        }

        /// Advances the action state by one tick, reading from `inputs`.
        pub fn update(self: *Self, inputs: *const InputManager) bool {
            const temp = self.currIdx;
            self.currIdx = self.prevIdx;
            self.prevIdx = temp;

            var curr = self.currDigital_mut();
            curr.clear();

            for (self.digitalBindings.items) |binding| {
                if (isSourceDown(binding.source, inputs)) {
                    curr.set(binding.action, true);
                }
            }

            var currAxes = self.currAxis_mut();
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
                        if (inputs.num_gamepads > 0) {
                            val = inputs.gamepads[0].axis(ga.axis);
                            if (@abs(val) < ga.deadzone) val = 0;
                        }
                    },
                }
                currAxes.set(binding.axis, val);
            }

            return false;
        }

        pub fn up(self: *const Self, action: Action) bool {
            return self.currDigital().up(action) == false;
        }

        pub fn down(self: *const Self, action: Action) bool {
            return self.currDigital().down(action);
        }

        pub fn axis(self: *const Self, ax: Axes) f32 {
            const axisIdx = helpers.getIndexForAxis(ax);
            return self.currAnalog().axes[axisIdx];
        }

        pub fn pressed(self: *const Self, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return (self.currDigital().downIdx(actionIdx) and !self.prevDigital().downIdx(actionIdx));
        }

        pub fn released(self: *const Self, action: Action) bool {
            const actionIdx = helpers.getIndexForAction(action);
            return (!self.currDigital().downIdx(actionIdx) and self.prevDigital().downIdx(actionIdx));
        }
    };
}
