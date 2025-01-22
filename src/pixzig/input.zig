// zig fmt: off
const std = @import("std");
const glfw = @import("zglfw");
const comp = @import("./comp.zig");
const common = @import("./common.zig");
const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;

const NumKeys = comp.numEnumFields(glfw.Key);

fn getIndexForKey(key: glfw.Key) usize {
   const enumTypeInfo = @typeInfo(glfw.Key).Enum;
    comptime var keyIdx: usize = 0;
    inline for (enumTypeInfo.fields) |field| {
        const fieldKey = @field(glfw.Key, field.name);
        if (key == fieldKey) return keyIdx;
        keyIdx += 1;
    }

    return 0;
}

pub const KeyboardState = struct {
    keys: std.StaticBitSet(NumKeys),

    pub fn init() KeyboardState {
        const keys = std.StaticBitSet(NumKeys).initEmpty();
        return .{ 
            .keys = keys
        };
    }

    pub fn down(self: *KeyboardState, keyIdx: usize) bool {
        const res = self.keys.isSet(keyIdx);
        return res;
    }

    pub fn set(self: *KeyboardState, keyIdx: usize, val: bool) void {
        if(val) {
            self.keys.set(keyIdx);
        }
        else {
            self.keys.unset(keyIdx);
        }
    }
};

pub const Keyboard = struct {
    currIdx: usize,
    prevIdx: usize,
    keyBuffers: [2]KeyboardState,
    window: *glfw.Window,
    allocator: std.mem.Allocator,

    pub fn init(win: *glfw.Window, alloc: std.mem.Allocator) Keyboard {
        const res: Keyboard = .{
            .currIdx = 0, 
            .prevIdx = 1,
            .keyBuffers = .{
                KeyboardState.init(),
                KeyboardState.init()
            },
            .window = win,
            .allocator = alloc
        };

        return res;
    }

    fn currKeys(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.currIdx];
    }
    fn prevKeys(self: *Keyboard) *KeyboardState {
        return &self.keyBuffers[self.prevIdx];
    }

    pub fn update(self: *Keyboard) void { //deltaUs: i64) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        var curr = self.currKeys();
        //const prev = self.prevKeys();
        // curr.keys.setRangeValue(.{.start=0, .end=NumKeys}, false);
       

        // Update the current keys
        const enumTypeInfo = @typeInfo(glfw.Key).Enum;
        comptime var keyIdx = 0;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.Key, field.name);
            curr.set(keyIdx, self.window.getKey(enumValue) == .press);
            keyIdx += 1;
        }

        // curr.keys.setUnion(prev.keys);
    }

    pub fn up(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return self.currKeys().down(keyIdx) == false;
    }

    pub fn down(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return self.currKeys().down(keyIdx);
    }

    pub fn pressed(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (self.currKeys().down(keyIdx) and !self.prevKeys().down(keyIdx));
    }

    pub fn released(self: *Keyboard, key: glfw.Key) bool {
        const keyIdx = getIndexForKey(key);
        return (!self.currKeys().down(keyIdx) and self.prevKeys().down(keyIdx));
    }
};


// ----------------------------------------------------------------------------
// Mouse functionality
const NumMouseButtons = comp.numEnumFields(glfw.MouseButton);

fn getIndexForMouseButton(key: glfw.MouseButton) usize {
   const enumTypeInfo = @typeInfo(glfw.MouseButton).Enum;
    comptime var keyIdx: usize = 0;
    inline for (enumTypeInfo.fields) |field| {
        const fieldKey = @field(glfw.MouseButton, field.name);
        if (key == fieldKey) return keyIdx;
        keyIdx += 1;
    }

    return 0;
}

pub const MouseState = struct {
    buttons: std.StaticBitSet(NumMouseButtons),
    pos: Vec2F,

    pub fn init() MouseState {
        const buttons = std.StaticBitSet(NumMouseButtons).initEmpty();
        return .{ 
            .buttons = buttons,
            .pos = .{ .x = 0, .y = 0 }
        };
    }

    pub fn down(self: *MouseState, keyIdx: usize) bool {
        const res = self.buttons.isSet(keyIdx);
        return res;
    }

    pub fn set(self: *MouseState, btnIdx: usize, val: bool) void {
        if(val) {
            self.buttons.set(btnIdx);
        }
        else {
            self.buttons.unset(btnIdx);
        }
    }

    pub fn setPos(self: *MouseState, pos: [2]f64) void {
        self.pos = .{ .x = @floatCast(pos[0]), .y = @floatCast(pos[1]) };
    }
};

pub const Mouse = struct {
    currIdx: usize,
    prevIdx: usize,
    mouseBuffers: [2]MouseState,
    window: *glfw.Window,
    allocator: std.mem.Allocator,

    pub fn init(win: *glfw.Window, alloc: std.mem.Allocator) Mouse {
        const res: Mouse = .{
            .currIdx = 0, 
            .prevIdx = 1,
            .mouseBuffers = .{
                MouseState.init(),
                MouseState.init()
            },
            .window = win,
            .allocator = alloc
        };

        return res;
    }

    pub fn update(self: *Mouse) void { //deltaUs: i64) void {
        const temp = self.currIdx;
        self.currIdx = self.prevIdx;
        self.prevIdx = temp;

        var state = self.curr();
        //const prev = self.prevKeys();
        // curr.keys.setRangeValue(.{.start=0, .end=NumKeys}, false);
       
        // Update the current keys
        const enumTypeInfo = @typeInfo(glfw.MouseButton).Enum;
        comptime var btnIdx = 0;
        inline for (enumTypeInfo.fields) |field| {
            const enumValue = @field(glfw.MouseButton, field.name);
            state.set(btnIdx, self.window.getMouseButton(enumValue) == .press);
            btnIdx += 1;
        }

        state.setPos(self.window.getCursorPos());
    }


    fn curr(self: *Mouse) *MouseState {
        return &self.mouseBuffers[self.currIdx];
    }

    fn prev(self: *Mouse) *MouseState {
        return &self.mouseBuffers[self.prevIdx];
    }


    pub fn up(self: *Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return self.curr().down(btnIdx) == false;
    }

    pub fn down(self: *Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return self.curr().down(btnIdx);
    }

    pub fn pressed(self: *Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return (self.curr().down(btnIdx) and !self.prev().down(btnIdx));
    }

    pub fn released(self: *Mouse, btn: glfw.MouseButton) bool {
        const btnIdx = getIndexForMouseButton(btn);
        return (!self.curr().down(btnIdx) and self.prev().down(btnIdx));
    }

    pub fn pos(self: *Mouse) Vec2F {
        return self.curr().pos;
    }

    pub fn lastPos(self: *Mouse) Vec2F {
        return self.prev().pos;
    }
};


pub const KeyModifier = enum(u8) {
    none = 0x0,
    ctrl = 0x1,
    alt = 0x2,
    ctrl_alt = 0x3,
    shift = 0x4,
    ctrl_shift = 0x5,
    alt_shift = 0x6,
    ctrl_alt_shift = 0x7,
    super = 0x8,
    ctrl_super = 0x9,
    alt_super = 0xa,
    ctrl_alt_super = 0xb,
    shift_super = 0xc,
    ctrl_shift_super = 0xd,
    alt_shift_super = 0xe,
    ctrl_alt_shift_super = 0xf
};

const DefaultChordTimeoutUs: i64 = 2e6;
const InitialRepeatRate: i64 = 1e5;
const DownRepeatRate: i64 = 2e4;

pub const KeyChordPiece = struct {
    // GLFW keys go up to 348, so we use the lower 24 bits for the key
    // and the top 8 bits for the modifiers.
    value: u32,

    pub fn from(mod: KeyModifier, k: glfw.Key) KeyChordPiece 
    {
        const modValue = @as(u32, @intCast(@intFromEnum(mod))) << 24;
        const keyValue = @as(u32, @bitCast(@intFromEnum(k))) & 0xffffff;
        return .{
            .value = modValue | keyValue,
        };
    }

    pub fn key(self: *const KeyChordPiece) glfw.Key
    {
        return @enumFromInt(self.value & 0xffffff);
    }

    pub fn modifier(self: *const KeyChordPiece) KeyModifier
    {
       return @enumFromInt(self.modVal());
    }

    fn modVal(self: *const KeyChordPiece) u8 {
        return @as(u8, @intCast((self.value >> 24) & 0xff));
    }

    pub fn print(self: *const KeyChordPiece, buf: []u8) !usize {
        const mod = self.modVal();
        const k = self.key();
        var len: usize = 0;
        if((mod & @intFromEnum(KeyModifier.ctrl)) != 0) {
            const sl = try std.fmt.bufPrint(buf[len..], "Ctrl+", .{});
            len += sl.len;
        }
        if((mod & @intFromEnum(KeyModifier.alt)) != 0) {
            const sl = try std.fmt.bufPrint(buf[len..], "Alt+", .{});
            len += sl.len;
        }
        if((mod & @intFromEnum(KeyModifier.shift)) != 0) {
            const sl = try std.fmt.bufPrint(buf[len..], "Shift+", .{});
            len += sl.len;
        }
        if((mod & @intFromEnum(KeyModifier.super)) != 0) {
            const sl = try std.fmt.bufPrint(buf[len..], "Super+", .{});
            len += sl.len;
        }

        const keyNames: [111][]const u8 = .{
            "space", "'", ",", "-", ".", "/",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            ";", "=", 
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
            "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X",
            "Y", "Z", "[", "\\", "]", "`", "world_1", "world_2",
            "escape", "enter", "tab", "backspace", "insert", "delete",
            "right", "left", "down", "up",
            "page_up", "page_down", "home", "end",
            "caps_lock", "scroll_lock", "num_lock", "print_screen",
            "pause", 
            "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9",
            "F10", "F11", "F12", "F13", "F14", "F15", "F16", "F17",
            "F18", "F19", "F20", "F21", "F22", "F23", "F24", "F25",
            "kp_0", "kp_1", "kp_2", "kp_3", "kp_4", "kp_5", "kp_6",
            "kp_7", "kp_8", "kp_9", "kp_decimal", "kp_divide", 
            "kp_multiply", "kp_subtract", "kp_add", "kp_enter", "kp_equal",
        };

        const kIdx = getIndexForKey(k) - 1;
        if(kIdx < keyNames.len) {
            const sl = try std.fmt.bufPrint(buf[len..], "{s}", .{keyNames[kIdx]});
            len += sl.len;
        }
        else {
            const sl = try std.fmt.bufPrint(buf[len..], "Unknown ({any})", .{k});
            len += sl.len;
        }
        // inline for(0..keyNames.len) |knIdx| {
        //     if(kIdx == )
        // }
        
        return len;
    }
};

pub const KeyChord = struct {
    alloc: std.mem.Allocator,
    // The script func to call, can be straight lua code.
    func: ?[]const u8, // Change to ArrayList of context/func.
    piece: KeyChordPiece,
    children: std.AutoHashMap(KeyChordPiece, KeyChord),

    pub fn init(alloc: std.mem.Allocator, piece: KeyChordPiece, func: ?[]const u8) !KeyChord {
        var fnc: ?[]const u8 = null;
        if(fnc != null) {
            fnc = try alloc.dupe(u8, func.?);
        }
        return .{
            .alloc = alloc,
            .func = fnc,
            .piece = piece,
            .children = std.AutoHashMap(KeyChordPiece, KeyChord).init(alloc)
        };
    }

    pub fn deinit(self: *KeyChord) void {
        if(self.func != null) {
            self.alloc.free(self.func.?);
        }

        self.children.deinit();
    }

    pub fn print(self: *KeyChord, buff: []u8) !usize {
        var len: usize = 0;
        if(self.func != null) {
            len = try self.piece.print(buff);
            const sl = try std.fmt.bufPrint(buff[len..], ": {s}\n", .{self.func.?});
            len += sl.len;
        }

        var it = self.children.keyIterator();
        while(it.next()) |k| {
            len += try self.piece.print(buff[len..]);
            _= try std.fmt.bufPrint(buff[len..], ", ", .{});
            len += 2;

            len += try k.print(buff[len..]);
            len += try self.children.getPtr(k.*).?.print(buff[len..]);
        }

        return len;
    }
};

const ChordTree = struct {
    alloc: std.mem.Allocator,
    context: ?[]const u8,
    downKey: glfw.Key,
    currChord: ?*KeyChord,
    rootChord: KeyChord,
    elapsedUsCounter: i64,
    repeatCounter: i64,
    
    pub fn init(alloc: std.mem.Allocator, context: ?[]const u8) !ChordTree {
        var ctxt: ?[]const u8 = null;
        if(ctxt != null) {
            ctxt = try alloc.dupe(u8, context.?);
        }

        return .{
            .alloc = alloc,
            .context = ctxt,
            .downKey = .unknown,
            .currChord = null,
            .rootChord = try KeyChord.init(alloc, KeyChordPiece.from(.none, .unknown), null),
            .elapsedUsCounter = 0,
            .repeatCounter = 0,
        };
    }

    pub fn deinit(self: *ChordTree) void {
        if(self.context != null) {
            self.alloc.free(self.context);
        }

        self.rootChord.deinit();
    }

    pub fn reset(self: *ChordTree) void {
        self.currChord = &self.rootChord;
        self.elapsedUsCounter = 0;
        self.downKey = .unknown;
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
       _ = self;
       _ = context;
       _ = func;
       _ = key;
       _ = mods;
        return false;
    }

    pub fn addTwoKeyChord(self: *KeyMap, mods: KeyModifier, key1: glfw.Key, key2: glfw.Key, func: []const u8, context: ?[]const u8) !bool {
       _ = self;
       _ = key2;
       _ = context;
       _ = func;
       _ = key1;
       _ = mods;
        return false;
    }

    pub fn addComplexChord(self: *KeyMap, pkp1: KeyChordPiece, kp2: KeyChordPiece, func: []const u8, context: ?[]const u8) !bool {
       _ = pkp1;
       _ = self;
       _ = context;
       _ = func;
       _ = kp2;
        return false;
    }

    // pub fn printKeyMap(self: *KeyMap) void {
    //
    // }
};
