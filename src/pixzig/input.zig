const std = @import("std");

pub const keyboard = @import("./input/keyboard.zig");
pub const charFromKey = keyboard.charFromKey;
pub const KeyModifier = keyboard.KeyModifier;
pub const KeyboardState = keyboard.KeyboardState;
pub const Keyboard = keyboard.Keyboard;

pub const mouse = @import("./input/mouse.zig");
pub const MouseState = mouse.MouseState;
pub const Mouse = mouse.Mouse;

pub const gamepad = @import("./input/gamepad.zig");
pub const GamepadState = gamepad.GamepadState;
pub const Gamepad = gamepad.Gamepad;

pub const keychord = @import("./input/keychord.zig");
pub const KeyChord = keychord.KeyChord;
pub const KeyChordPiece = keychord.KeyChordPiece;
pub const ChordUpdateResult = keychord.ChordUpdateResult;
pub const ChordTree = keychord.ChordTree;
pub const KeyMap = keychord.KeyMap;
