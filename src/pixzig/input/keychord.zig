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

pub fn KeyChord(comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        func: ?T,
        piece: KeyChordPiece,
        children: std.AutoHashMap(KeyChordPiece, *KeyChord(T)),

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator, piece: KeyChordPiece, func: ?T) !Self {
            return .{
                .alloc = alloc,
                .func = func,
                .piece = piece,
                .children = std.AutoHashMap(KeyChordPiece, *KeyChord(T)).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.children.valueIterator();
            while (it.next()) |child| {
                child.*.deinit();
                self.alloc.destroy(child.*);
            }
            self.children.deinit();
        }

        pub fn print(self: *Self, buff: []u8) !usize {
            var len: usize = 0;

            if (self.func != null) {
                len = try self.piece.print(buff);
                // Use {s} for string slices, {} for everything else (enums, etc.)
                const sl = if (comptime T == []const u8 or T == []u8)
                    try std.fmt.bufPrint(buff[len..], ": {s}", .{self.func.?})
                else
                    try std.fmt.bufPrint(buff[len..], ": {}", .{self.func.?});
                len += sl.len;
            }

            var it = self.children.keyIterator();
            while (it.next()) |k| {
                len += try self.piece.print(buff[len..]);
                _ = try std.fmt.bufPrint(buff[len..], ", ", .{});
                len += 2;
                len += try self.children.getPtr(k.*).?.*.print(buff[len..]);
            }

            return len;
        }
    };
}

pub fn ChordUpdateResult(comptime T: type) type {
    return union(enum) { none: void, reset: void, triggered: *KeyChord(T) };
}

pub fn ChordTree(comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        context: ?[]const u8,
        downKey: glfw.Key,
        currChord: ?*KeyChord(T),
        rootChord: *KeyChord(T),
        elapsedUsCounter: f64,
        repeatCounter: f64,

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator, context: ?[]const u8) !Self {
            const ctxt: ?[]const u8 = if (context) |c| try alloc.dupe(u8, c) else null;
            errdefer if (ctxt) |c| alloc.free(c);

            const root = try alloc.create(KeyChord(T));
            errdefer alloc.destroy(root);
            root.* = try KeyChord(T).init(alloc, KeyChordPiece.from(.{}, .unknown), null);

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

        pub fn deinit(self: *Self) void {
            if (self.context != null) {
                self.alloc.free(self.context.?);
            }

            self.rootChord.deinit();
            self.alloc.destroy(self.rootChord);
        }

        pub fn reset(self: *Self) void {
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

        pub fn update(self: *Self, kbState: *const KeyboardState, elapsedUs: f64) ChordUpdateResult(T) {
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
}

pub fn KeyMap(comptime T: type) type {
    return struct {
        chords: ChordTree(T),
        alloc: std.mem.Allocator,

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator) !Self {
            return .{
                .chords = try ChordTree(T).init(alloc, null),
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.chords.deinit();
        }

        pub fn addKeyChord(self: *Self, mods: KeyModifier, key: glfw.Key, func: T, context: ?[]const u8) !bool {
            _ = context;
            const kcp = KeyChordPiece.from(mods, key);
            if (self.chords.rootChord.children.contains(kcp)) return false;

            const chord = try self.alloc.create(KeyChord(T));
            errdefer self.alloc.destroy(chord);
            chord.* = try KeyChord(T).init(self.alloc, kcp, func);
            errdefer chord.deinit();
            try self.chords.rootChord.children.put(kcp, chord);
            return true;
        }

        pub fn addTwoKeyChord(self: *Self, mods: KeyModifier, key1: glfw.Key, key2: glfw.Key, func: T, context: ?[]const u8) !bool {
            _ = context;
            const kcp1 = KeyChordPiece.from(mods, key1);

            var chord1: *KeyChord(T) = undefined;
            if (!self.chords.rootChord.children.contains(kcp1)) {
                chord1 = try self.alloc.create(KeyChord(T));
                var chord1Committed = false;
                errdefer if (!chord1Committed) self.alloc.destroy(chord1);
                chord1.* = try KeyChord(T).init(self.alloc, kcp1, null);
                errdefer if (!chord1Committed) chord1.deinit();
                try self.chords.rootChord.children.put(kcp1, chord1);
                chord1Committed = true;
            } else {
                chord1 = self.chords.rootChord.children.get(kcp1).?;
            }

            const kcp2 = KeyChordPiece.from(mods, key2);
            if (chord1.children.contains(kcp2)) return false;

            const chord2 = try self.alloc.create(KeyChord(T));
            errdefer self.alloc.destroy(chord2);
            chord2.* = try KeyChord(T).init(self.alloc, kcp2, func);
            errdefer chord2.deinit();
            try chord1.children.put(kcp2, chord2);
            return true;
        }

        pub fn addComplexChord(self: *Self, kcp1: KeyChordPiece, kcp2: KeyChordPiece, func: T, context: ?[]const u8) !bool {
            _ = context;
            var chord1: *KeyChord(T) = undefined;
            if (!self.chords.rootChord.children.contains(kcp1)) {
                chord1 = try self.alloc.create(KeyChord(T));
                var chord1Committed = false;
                errdefer if (!chord1Committed) self.alloc.destroy(chord1);
                chord1.* = try KeyChord(T).init(self.alloc, kcp1, null);
                errdefer if (!chord1Committed) chord1.deinit();
                try self.chords.rootChord.children.put(kcp1, chord1);
                chord1Committed = true;
            } else {
                chord1 = self.chords.rootChord.children.get(kcp1).?;
            }

            if (chord1.children.contains(kcp2)) return false;

            const chord2 = try self.alloc.create(KeyChord(T));
            errdefer self.alloc.destroy(chord2);
            chord2.* = try KeyChord(T).init(self.alloc, kcp2, func);
            errdefer chord2.deinit();
            try chord1.children.put(kcp2, chord2);
            return true;
        }

        pub fn update(self: *Self, kbState: *const KeyboardState, elapsedUs: f64) ChordUpdateResult(T) {
            return self.chords.update(kbState, elapsedUs);
        }

        pub fn reset(self: *Self) void {
            self.chords.reset();
        }
    };
}
