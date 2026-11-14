//! The game's named controls, and the keys and gamepad buttons bound to
//! them. Game code asks about actions (`eng.actions.pressed(.jump)`), never
//! about keys, so rebinding is a change here only.

const Engine = @import("main.zig").Engine;

pub const Action = enum { left, right, jump, confirm, pause, back };

/// Binds keyboard and gamepad controls for every action.
pub fn bind(eng: *Engine) !void {
    const a = eng.actions;
    try a.bind(.left, .{ .key = .left });
    try a.bind(.left, .{ .key = .a });
    try a.bind(.left, .{ .gamepad_button = .dpad_left });
    try a.bind(.right, .{ .key = .right });
    try a.bind(.right, .{ .key = .d });
    try a.bind(.right, .{ .gamepad_button = .dpad_right });
    try a.bind(.jump, .{ .key = .space });
    try a.bind(.jump, .{ .key = .up });
    try a.bind(.jump, .{ .key = .w });
    try a.bind(.jump, .{ .key = .z });
    try a.bind(.jump, .{ .gamepad_button = .a });
    try a.bind(.confirm, .{ .key = .enter });
    try a.bind(.confirm, .{ .gamepad_button = .start });
    try a.bind(.pause, .{ .key = .p });
    try a.bind(.pause, .{ .gamepad_button = .start });
    try a.bind(.back, .{ .key = .escape });
    try a.bind(.back, .{ .gamepad_button = .back });
}
