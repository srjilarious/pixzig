// A console using only my engine for rendering.

const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

const utils = @import("./utils.zig");

const scripting = @import("./scripting.zig");
const ScriptEngine = scripting.ScriptEngine;
const TextRenderer = @import("./renderer/text.zig").TextRenderer;
const ShapeBatchQueue = @import("./renderer/shape.zig").ShapeBatchQueue;
const common = @import("./common.zig");
const Vec2I = common.Vec2I;
const Color = common.Color;
const RectF = common.RectF;
const Keyboard = @import("./input.zig").Keyboard;

pub const ConsoleOpts = struct {
    numLogLines: usize = 2000,
    enabledByDefault: bool = true,
};

pub const Console = struct {
    alloc: std.mem.Allocator,
    scriptEng: *ScriptEngine,
    history: std.ArrayList([]u8),
    historyIndex: i32,
    logBuffer: std.ArrayList([]u8),
    opts: ConsoleOpts,
    enabled: bool,
    shouldFocus: bool,
    inputBuffer: [:0]u8,
    cursor: usize,
    inputMax: usize,
    storedCommandBuffer: [:0]u8,

    // Rendering members
    shapeRenderer: *ShapeBatchQueue,
    textRenderer: *TextRenderer,

    pub fn init(
        alloc: std.mem.Allocator,
        scriptEng: *ScriptEngine,
        textRenderer: *TextRenderer,
        shapeRenderer: *ShapeBatchQueue,
        opts: ConsoleOpts,
    ) !*Console {
        const console: *Console = try alloc.create(Console);
        console.* = .{
            .alloc = alloc,
            .scriptEng = scriptEng,
            .shapeRenderer = shapeRenderer,
            .textRenderer = textRenderer,
            .history = .{},
            .historyIndex = -1,
            .logBuffer = .{},
            .opts = opts,
            .enabled = opts.enabledByDefault,
            .shouldFocus = true,
            .inputBuffer = try alloc.allocSentinel(u8, 256, 0),
            .cursor = 0,
            .inputMax = 0,
            .storedCommandBuffer = try alloc.allocSentinel(u8, 256, 0),
        };

        @memset(console.inputBuffer, 0);
        @memset(console.storedCommandBuffer, 0);

        // Create a console object in lua.
        var lua = scriptEng.lua;
        // Push the light userdata onto the Lua stack
        lua.pushLightUserdata(console);

        // Create a new table to represent the Console object
        lua.newTable();

        // Set the light userdata as a field in the Console table
        _ = lua.pushString("userdata");
        _ = lua.pushValue(-3); // Copy light userdata
        lua.setTable(-3);

        // Define the log method
        _ = lua.pushString("log");
        _ = lua.pushFunction(ziglua.wrap(log));
        lua.setTable(-3);

        // Set the Console object as a global variable named "my_console"
        lua.setGlobal("con");

        // Pop the light userdata from the stack
        lua.pop(1);
        return console;
    }

    pub fn deinit(self: *Console) void {
        for (self.history.items) |entry| {
            // Free the history entries we allocated in our run command func.
            self.alloc.free(entry);
        }

        self.history.deinit(self.alloc);

        for (self.logBuffer.items) |entry| {
            // Free the log entries we allocated in our log func.
            self.alloc.free(entry);
        }

        self.logBuffer.deinit(self.alloc);
        self.alloc.free(self.inputBuffer);
        self.alloc.free(self.storedCommandBuffer);
        self.alloc.destroy(self);
    }

    fn addMessageToHistoryZ(self: *Console, msgC: [:0]const u8) !void {
        const newMsgC = try self.alloc.dupe(u8, msgC);
        try self.history.append(self.alloc, newMsgC[0..]);
    }

    const AddMessageOpts = struct { prepend: ?[]const u8 = null };

    fn addMessageToLogZ(self: *Console, msgC: [:0]const u8, opts: AddMessageOpts) !void {
        const msg = utils.cStrToSlice(msgC);
        try self.addMessageToLog(msg, opts);
    }

    fn addMessageToLog(self: *Console, msg: []const u8, opts: AddMessageOpts) !void {

        // Allocate a copy of the message to add to our log entries.
        var spaceNeeded: usize = msg.len;
        if (opts.prepend != null) {
            spaceNeeded += opts.prepend.?.len;
        }

        const new_msg = try self.alloc.alloc(u8, spaceNeeded);
        if (opts.prepend != null) {
            const startLen = opts.prepend.?.len;
            @memcpy(new_msg[0..startLen], opts.prepend.?);
            @memcpy(new_msg[startLen..], msg);
        } else {
            @memcpy(new_msg, msg);
        }

        try self.logBuffer.append(self.alloc, new_msg);
    }

    fn log(lua: *Lua) i32 {
        _ = lua.getField(1, "userdata");
        const console = lua.toUserdata(Console, -1) catch {
            std.debug.print("Couldn't get console userdata ptr!\n", .{});
            return 0;
        };
        lua.pop(1);

        // Get the message paramter.
        const msgC = lua.toString(2) catch {
            std.debug.print("log(): Bad msg parameter.\n", .{});
            return 0;
        };

        console.addMessageToLogZ(msgC, .{}) catch {
            std.debug.print("Error adding message to history!\n", .{});
            return 0;
        };

        return 0;
    }

    fn runCurrentInput(self: *Console) !void {
        // Make sure to null terminate the input buffer.
        self.inputBuffer[self.inputMax] = 0;

        std.debug.print("Running: {s}\n", .{self.inputBuffer});

        var addToHistory: bool = false;
        if (self.history.items.len != 0) {
            if (!std.mem.eql(u8, self.inputBuffer, self.history.items[self.history.items.len - 1])) {
                addToHistory = true;
            }
        } else {
            addToHistory = true;
        }

        if (addToHistory) {
            try self.addMessageToHistoryZ(self.inputBuffer);
        }

        self.historyIndex = -1;

        try self.addMessageToLogZ(self.inputBuffer, .{ .prepend = ">> " });

        self.scriptEng.run(self.inputBuffer) catch |err| {
            const msg = try std.fmt.allocPrint(self.alloc, "ERROR: {any}\n", .{err});
            try self.addMessageToLog(msg, .{});
            self.alloc.free(msg);
        };

        // Clear the current input buffer.
        @memset(self.inputBuffer, 0);
        self.cursor = 0;
        self.inputMax = 0;
    }

    pub fn update(self: *Console, kb: *Keyboard) void {
        var buf: [4]u8 = undefined;
        const num = kb.text(&buf);
        for (0..num) |idx| {
            // TODO: handle cursor in middle of string
            self.inputBuffer[self.cursor] = buf[idx];
            self.cursor += 1;
            self.inputMax += 1;
        }

        // TODO: Handle left/right to move cursor
        if (kb.pressed(.left)) {
            if (self.cursor > 0) {
                self.cursor -= 1;
            }
        } else if (kb.pressed(.right)) {
            if (self.cursor < self.inputMax - 1) {
                self.cursor += 1;
            }
        }

        // TODO: Handle backspace and delete

        // Handle moving through history
        if (kb.pressed(.up)) {
            if (self.historyIndex == -1) {
                @memcpy(self.storedCommandBuffer, self.inputBuffer);
                self.historyIndex = @intCast(self.history.items.len - 1);
            } else if (self.historyIndex > 0) {
                self.historyIndex -= 1;
            }

            const histIndex: usize = @intCast(self.historyIndex);
            @memcpy(self.inputBuffer, self.history.items[histIndex]);
        } else if (kb.pressed(.down)) {
            if (self.historyIndex != -1) {
                self.historyIndex += 1;

                if (self.historyIndex >= self.history.items.len) {
                    self.historyIndex = -1;
                    @memcpy(self.inputBuffer, self.storedCommandBuffer);
                } else {
                    const histIndex: usize = @intCast(self.historyIndex);
                    @memcpy(self.inputBuffer, self.history.items[histIndex]);
                }
            }
        }

        // Handle running command.
        if (kb.pressed(.enter)) {
            self.runCurrentInput() catch {};
        }
    }

    pub fn draw(self: *Console) void {
        self.shapeRenderer.drawFilledRect(
            .fromPosSize(10, 10, 640, 400),
            Color.from(0, 0, 0, 200),
        );

        var pos: Vec2I = .{ .x = 20, .y = 20 };
        for (0..self.logBuffer.items.len) |idx| {
            const sz = self.textRenderer.drawString(
                self.logBuffer.items[idx],
                pos,
                //Color.from(255, 255, 255, 255),
            );
            pos.y += sz.y;
        }

        pos.y += 50;
        const pSz = self.textRenderer.drawString(
            ">> ",
            pos,
            // Color.from(200, 255, 200, 255),
        );
        pos.x += pSz.x;
        _ = self.textRenderer.drawString(
            self.inputBuffer[0..self.inputMax],
            pos,
            // Color.from(255, 255, 255, 255),
        );

        const preSize = self.textRenderer.measureString(self.inputBuffer[0..self.cursor]);
        self.shapeRenderer.drawFilledRect(RectF.fromPosSize(pos.x + preSize.x, pos.y + self.textRenderer.atlas.?.maxY, 10, 3), Color.from(255, 255, 100, 255));
    }

    // fn inputCallback(data: *zgui.InputTextCallbackData) i32 {
    //     const console: *Console = @ptrCast(@alignCast(data.user_data));

    //     if (data.event_flag.callback_history) {
    //         var updateText: bool = false;
    //         if (console.history.items.len > 0) {
    //             if (data.event_key == .up_arrow) {
    //                 if (console.historyIndex == -1) {
    //                     @memcpy(console.storedCommandBuffer, console.inputBuffer);
    //                     console.historyIndex = @intCast(console.history.items.len - 1);
    //                     updateText = true;
    //                 } else if (console.historyIndex > 0) {
    //                     console.historyIndex -= 1;
    //                     updateText = true;
    //                 }

    //                 const histIndex: usize = @intCast(console.historyIndex);
    //                 @memcpy(console.inputBuffer, console.history.items[histIndex]);
    //             } else if (data.event_key == .down_arrow) {
    //                 if (console.historyIndex != -1) {
    //                     console.historyIndex += 1;

    //                     if (console.historyIndex >= console.history.items.len) {
    //                         console.historyIndex = -1;
    //                         @memcpy(console.inputBuffer, console.storedCommandBuffer);
    //                     } else {
    //                         const histIndex: usize = @intCast(console.historyIndex);
    //                         @memcpy(console.inputBuffer, console.history.items[histIndex]);
    //                     }

    //                     updateText = true;
    //                 }
    //             }

    //             if (updateText) {
    //                 data.deleteChars(0, data.buf_text_len);
    //                 const msg = utils.cStrToSlice(console.inputBuffer);
    //                 data.insertChars(0, msg);
    //             }
    //         }
    //     }
    //     return 0;
    // }
};
