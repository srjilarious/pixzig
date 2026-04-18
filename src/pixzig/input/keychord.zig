const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("../comp.zig");
const common = @import("../common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

const keyboard = @import("./keyboard.zig");
const getIndexForKey = keyboard.getIndexForKey;
const KeyModifier = keyboard.KeyModifier;
const KeyboardState = keyboard.KeyboardState;

pub const DefaultChordTimeoutUs: f64 = 2e6;
pub const InitialRepeatRate: f64 = 1e5;
pub const DownRepeatRate: f64 = 2e4;

pub const KeyChordPiece = struct {
    key: glfw.Key,
    mod: KeyModifier,

    pub fn from(mod: KeyModifier, k: glfw.Key) KeyChordPiece {
        return .{
            .key = k,
            .mod = mod,
        };
    }

    pub fn print(self: *const KeyChordPiece, buf: []u8) !usize {
        var len: usize = 0;
        if (self.mod.ctrl) {
            const sl = try std.fmt.bufPrint(buf[len..], "Ctrl+", .{});
            len += sl.len;
        }
        if (self.mod.alt) {
            const sl = try std.fmt.bufPrint(buf[len..], "Alt+", .{});
            len += sl.len;
        }
        if (self.mod.shift) {
            const sl = try std.fmt.bufPrint(buf[len..], "Shift+", .{});
            len += sl.len;
        }
        if (self.mod.super) {
            const sl = try std.fmt.bufPrint(buf[len..], "Super+", .{});
            len += sl.len;
        }

        const keyNames: [111][]const u8 = .{
            "space",    "'",            ",",          "-",         ".",           "/",
            "0",        "1",            "2",          "3",         "4",           "5",
            "6",        "7",            "8",          "9",         ";",           "=",
            "A",        "B",            "C",          "D",         "E",           "F",
            "G",        "H",            "I",          "J",         "K",           "L",
            "M",        "N",            "O",          "P",         "Q",           "R",
            "S",        "T",            "U",          "V",         "W",           "X",
            "Y",        "Z",            "[",          "\\",        "]",           "`",
            "world_1",  "world_2",      "escape",     "enter",     "tab",         "backspace",
            "insert",   "delete",       "right",      "left",      "down",        "up",
            "page_up",  "page_down",    "home",       "end",       "caps_lock",   "scroll_lock",
            "num_lock", "print_screen", "pause",      "F1",        "F2",          "F3",
            "F4",       "F5",           "F6",         "F7",        "F8",          "F9",
            "F10",      "F11",          "F12",        "F13",       "F14",         "F15",
            "F16",      "F17",          "F18",        "F19",       "F20",         "F21",
            "F22",      "F23",          "F24",        "F25",       "kp_0",        "kp_1",
            "kp_2",     "kp_3",         "kp_4",       "kp_5",      "kp_6",        "kp_7",
            "kp_8",     "kp_9",         "kp_decimal", "kp_divide", "kp_multiply", "kp_subtract",
            "kp_add",   "kp_enter",     "kp_equal",
        };

        const kIdx = getIndexForKey(self.key) - 1;
        if (kIdx < keyNames.len) {
            const sl = try std.fmt.bufPrint(buf[len..], "{s}", .{keyNames[kIdx]});
            len += sl.len;
        } else {
            const sl = try std.fmt.bufPrint(buf[len..], "Unknown ({any})", .{self.key});
            len += sl.len;
        }

        return len;
    }
};

pub const KeyChord = struct {
    alloc: std.mem.Allocator,
    // The script func to call, can be straight lua code.
    func: ?[]const u8, // Change to ArrayList of context/func.
    piece: KeyChordPiece,
    children: std.AutoHashMap(KeyChordPiece, *KeyChord),

    pub fn init(alloc: std.mem.Allocator, piece: KeyChordPiece, func: ?[]const u8) !KeyChord {
        var fnc: ?[]const u8 = null;
        if (func != null) {
            fnc = try alloc.dupe(u8, func.?);
        }
        return .{
            .alloc = alloc,
            .func = fnc,
            .piece = piece,
            .children = std.AutoHashMap(KeyChordPiece, *KeyChord).init(alloc),
        };
    }

    pub fn deinit(self: *KeyChord) void {
        if (self.func != null) {
            self.alloc.free(self.func.?);
        }

        self.children.deinit();
    }

    pub fn print(self: *KeyChord, buff: []u8) !usize {
        var len: usize = 0;
        if (self.func != null) {
            len = try self.piece.print(buff);
            const sl = try std.fmt.bufPrint(buff[len..], ": {s}", .{self.func.?});
            len += sl.len;
        }

        var it = self.children.keyIterator();
        while (it.next()) |k| {
            len += try self.piece.print(buff[len..]);
            _ = try std.fmt.bufPrint(buff[len..], ", ", .{});
            len += 2;

            // len += try k.print(buff[len..]);
            len += try self.children.getPtr(k.*).?.*.print(buff[len..]);
        }

        return len;
    }
};

pub const ChordUpdateResult = union(enum) { none: void, reset: void, triggered: *KeyChord };

pub const ChordTree = struct {
    alloc: std.mem.Allocator,
    context: ?[]const u8,
    downKey: glfw.Key,
    currChord: ?*KeyChord,
    rootChord: *KeyChord,
    elapsedUsCounter: f64,
    repeatCounter: f64,

    pub fn init(alloc: std.mem.Allocator, context: ?[]const u8) !ChordTree {
        var ctxt: ?[]const u8 = null;
        if (context != null) {
            ctxt = try alloc.dupe(u8, context.?);
        }

        const root = try alloc.create(KeyChord);
        root.* = try KeyChord.init(alloc, KeyChordPiece.from(.{}, .unknown), null);

        return .{
            .alloc = alloc,
            .context = ctxt,
            .downKey = .unknown,
            .currChord = root,
            .rootChord = root,
            .elapsedUsCounter = 0,
            .repeatCounter = 0,
        };
    }

    pub fn deinit(self: *ChordTree) void {
        if (self.context != null) {
            self.alloc.free(self.context.?);
        }

        self.rootChord.deinit();
    }

    pub fn reset(self: *ChordTree) void {
        self.currChord = self.rootChord;
        self.elapsedUsCounter = 0;
        self.downKey = .unknown;
    }

    fn checkExpectedModsDown(chordMods: KeyModifier, kbMods: KeyModifier) bool {
        return chordMods.alt == kbMods.alt and
            chordMods.ctrl == kbMods.ctrl and
            chordMods.shift == kbMods.shift and
            chordMods.super == kbMods.super;
    }

    pub fn update(self: *ChordTree, kbState: *const KeyboardState, elapsedUs: f64) ChordUpdateResult {
        if (self.downKey != .unknown) {
            if (!checkExpectedModsDown(self.currChord.?.piece.mod, kbState.modifiers()) or kbState.up(self.downKey)) {
                self.reset();
                return .reset;
            } else {
                self.repeatCounter -= elapsedUs;
                if (self.repeatCounter <= 0) {
                    self.repeatCounter = DownRepeatRate;
                    return .{ .triggered = self.currChord.? };
                }
            }
        } else {
            self.elapsedUsCounter += elapsedUs;
            if (self.elapsedUsCounter > DefaultChordTimeoutUs) {
                self.reset();
                return .reset;
            }

            var it = self.currChord.?.children.keyIterator();
            while (it.next()) |k| {
                if (kbState.down(k.key)) {
                    if (checkExpectedModsDown(k.mod, kbState.modifiers())) {
                        self.elapsedUsCounter = 0.0;
                        self.currChord = self.currChord.?.children.get(k.*).?;
                        if (self.currChord.?.children.count() == 0) {
                            self.downKey = k.key;
                            self.repeatCounter = InitialRepeatRate;
                            return .{ .triggered = self.currChord.? };
                        }
                    }
                }
            }
        }
        return .none;
    }
};

pub const KeyMap = struct {
    chords: ChordTree,
    //currentContext: ?*ChordTree,
    // current context name?
    //contexts: std.StringHashMap(*ChordTree),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !KeyMap {
        return .{
            .chords = try ChordTree.init(alloc, null),
            .alloc = alloc,
            // .contexts = try std.StringHashMap(*ChordTree).init(alloc),
        };
    }

    pub fn deinit(self: *KeyMap) void {
        _ = self;
    }

    pub fn addKeyChord(self: *KeyMap, mods: KeyModifier, key: glfw.Key, func: []const u8, context: ?[]const u8) !bool {
        _ = context;
        const kcp = KeyChordPiece.from(mods, key);
        if (self.chords.rootChord.children.contains(kcp)) return false;

        const chord = try self.alloc.create(KeyChord);
        chord.* = try KeyChord.init(self.alloc, kcp, func);
        try self.chords.rootChord.children.put(kcp, chord);
        return true;
    }

    pub fn addTwoKeyChord(self: *KeyMap, mods: KeyModifier, key1: glfw.Key, key2: glfw.Key, func: []const u8, context: ?[]const u8) !bool {
        _ = context;
        const kcp1 = KeyChordPiece.from(mods, key1);

        var chord1: *KeyChord = undefined;
        if (!self.chords.rootChord.children.contains(kcp1)) {
            chord1 = try self.alloc.create(KeyChord);
            chord1.* = try KeyChord.init(self.alloc, kcp1, "");
            try self.chords.rootChord.children.put(kcp1, chord1);
        } else {
            chord1 = self.chords.rootChord.children.get(kcp1).?;
        }

        // Second key portion.
        const kcp2 = KeyChordPiece.from(mods, key2);
        if (chord1.children.contains(kcp2)) return false;

        const chord2 = try self.alloc.create(KeyChord);
        chord2.* = try KeyChord.init(self.alloc, kcp2, func);
        try chord1.children.put(kcp2, chord2);
        return true;
    }

    pub fn addComplexChord(self: *KeyMap, kcp1: KeyChordPiece, kcp2: KeyChordPiece, func: []const u8, context: ?[]const u8) !bool {
        _ = context;
        var chord1: *KeyChord = undefined;
        if (!self.chords.rootChord.children.contains(kcp1)) {
            chord1 = try self.alloc.create(KeyChord);
            chord1.* = try KeyChord.init(self.alloc, kcp1, "");
            try self.chords.rootChord.children.put(kcp1, chord1);
        } else {
            chord1 = self.chords.rootChord.children.get(kcp1).?;
        }

        // Second key portion.
        if (chord1.children.contains(kcp2)) return false;

        const chord2 = try self.alloc.create(KeyChord);
        chord2.* = try KeyChord.init(self.alloc, kcp2, func);
        try chord1.children.put(kcp2, chord2);
        return true;
    }

    pub fn update(self: *KeyMap, kbState: *const KeyboardState, elapsedUs: f64) ChordUpdateResult {
        return self.chords.update(kbState, elapsedUs);
    }

    pub fn reset(self: *KeyMap) void {
        self.chords.reset();
    }

    // pub fn printKeyMap(self: *KeyMap) void {
    //
    // }
};
