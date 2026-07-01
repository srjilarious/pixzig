// A script console rendered with pixzig imgui.

const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;

const imgui = @import("./imgui.zig");
const scripting = @import("./scripting.zig");
const utils = @import("./utils.zig");
const common = @import("./common.zig");

const ScriptEngine = scripting.ScriptEngine;
const RectF = common.RectF;
const Vec2I = common.Vec2I;
const Vec2U = common.Vec2U;

/// Console initialization options.
pub const ConsoleOpts = struct {
    /// The max number of log lines to keep in in the console buffer.
    numLogLines: usize = 2000,

    /// Whether the console is enabled by default.
    enabledByDefault: bool = true,

    /// Pixel width of the display area, less offset on either side.
    displaySize: Vec2U = .{ .x = 800, .y = 600 },

    /// Padding in pixels between the text and the edge of the console window.
    padding: Vec2I = .{ .x = 10, .y = 10 },

    /// Offset in pixels from the top-left edge of the screen to the console.
    offs: Vec2I = .{ .x = 10, .y = 10 },

    /// Initial capacity of the editable command buffer.
    inputBufferLen: usize = 256,

    /// Imgui window ID and title.
    windowId: []const u8 = "pixzig_console",
    title: []const u8 = "Console",
};

pub const Console = struct {
    const InputId = "pixzig_console_input";
    const LogId = "pixzig_console_log";

    alloc: std.mem.Allocator,
    scriptEng: *ScriptEngine,
    history: std.ArrayList([]u8),
    historyIndex: i32,
    logBuffer: std.ArrayList([]u8),
    opts: ConsoleOpts,
    enabled: bool,
    shouldFocus: bool,
    inputBuffer: [:0]u8,
    inputMax: usize,
    storedCommandBuffer: [:0]u8,
    storedCommandLen: usize,
    lineOffs: usize,
    windowRect: RectF,
    scrollToBottom: bool,

    pub fn init(
        alloc: std.mem.Allocator,
        scriptEng: *ScriptEngine,
        opts: ConsoleOpts,
    ) !*Console {
        const console: *Console = try alloc.create(Console);
        errdefer alloc.destroy(console);

        const input_len = @max(1, opts.inputBufferLen);
        const input_buffer = try alloc.allocSentinel(u8, input_len, 0);
        errdefer alloc.free(input_buffer);
        const stored_command_buffer = try alloc.allocSentinel(u8, input_len, 0);
        errdefer alloc.free(stored_command_buffer);

        const right: f32 = @floatFromInt(opts.displaySize.x - @as(usize, @intCast(opts.offs.x)));
        const bottom: f32 = @floatFromInt(opts.displaySize.y - @as(usize, @intCast(opts.offs.y)));

        console.* = .{
            .alloc = alloc,
            .scriptEng = scriptEng,
            .history = .empty,
            .historyIndex = -1,
            .logBuffer = .empty,
            .opts = opts,
            .enabled = opts.enabledByDefault,
            .shouldFocus = true,
            .inputBuffer = input_buffer,
            .inputMax = 0,
            .storedCommandBuffer = stored_command_buffer,
            .storedCommandLen = 0,
            .lineOffs = 0,
            .windowRect = .{
                .l = @floatFromInt(opts.offs.x),
                .t = @floatFromInt(opts.offs.y),
                .r = right,
                .b = bottom,
            },
            .scrollToBottom = true,
        };

        @memset(console.inputBuffer, 0);
        @memset(console.storedCommandBuffer, 0);

        console.bindToLua();
        return console;
    }

    pub fn deinit(self: *Console) void {
        for (self.history.items) |entry| {
            self.alloc.free(entry);
        }
        self.history.deinit(self.alloc);

        for (self.logBuffer.items) |entry| {
            self.alloc.free(entry);
        }
        self.logBuffer.deinit(self.alloc);

        self.alloc.free(self.inputBuffer);
        self.alloc.free(self.storedCommandBuffer);
        self.alloc.destroy(self);
    }

    pub fn setEnabled(self: *Console, enabled: bool) void {
        self.enabled = enabled;
        self.shouldFocus = enabled;
    }

    pub fn toggle(self: *Console) void {
        self.setEnabled(!self.enabled);
    }

    fn bindToLua(self: *Console) void {
        var lua = self.scriptEng.lua;

        lua.pushLightUserdata(self);
        lua.newTable();

        _ = lua.pushString("userdata");
        _ = lua.pushValue(-3);
        lua.setTable(-3);

        _ = lua.pushString("log");
        _ = lua.pushFunction(ziglua.wrap(log));
        lua.setTable(-3);

        lua.setGlobal("con");
        lua.pop(1);
    }

    fn addMessageToHistoryZ(self: *Console, msgC: [:0]const u8) !void {
        try self.addMessageToHistory(utils.cStrToSlice(msgC));
    }

    fn addMessageToHistory(self: *Console, msg: []const u8) !void {
        const new_msg = try self.alloc.dupe(u8, msg);
        try self.history.append(self.alloc, new_msg);
    }

    const AddMessageOpts = struct { prepend: ?[]const u8 = null };

    fn addMessageToLogZ(self: *Console, msgC: [:0]const u8, opts: AddMessageOpts) !void {
        try self.addMessageToLog(utils.cStrToSlice(msgC), opts);
    }

    fn addMessageToLog(self: *Console, msg: []const u8, opts: AddMessageOpts) !void {
        var space_needed: usize = msg.len;
        if (opts.prepend) |prepend| space_needed += prepend.len;

        const new_msg = try self.alloc.alloc(u8, space_needed);
        if (opts.prepend) |prepend| {
            @memcpy(new_msg[0..prepend.len], prepend);
            @memcpy(new_msg[prepend.len..], msg);
        } else {
            @memcpy(new_msg, msg);
        }

        try self.logBuffer.append(self.alloc, new_msg);

        while (self.logBuffer.items.len > self.opts.numLogLines) {
            const old = self.logBuffer.orderedRemove(0);
            self.alloc.free(old);
            if (self.lineOffs > 0) self.lineOffs -= 1;
        }

        self.scrollToBottom = true;
    }

    fn log(lua: *Lua) i32 {
        _ = lua.getField(1, "userdata");
        const console = lua.toUserdata(Console, -1) catch {
            std.log.err("Couldn't get console userdata ptr!\n", .{});
            return 0;
        };
        lua.pop(1);

        const msgC = lua.toString(2) catch {
            std.log.err("log(): Bad msg parameter.\n", .{});
            return 0;
        };

        console.addMessageToLogZ(msgC, .{}) catch {
            std.log.err("Error adding message to log!\n", .{});
            return 0;
        };

        return 0;
    }

    fn runCurrentInput(self: *Console) !void {
        self.inputBuffer[self.inputMax] = 0;

        std.log.debug("Running: {s}\n", .{self.inputBuffer});

        var add_to_history = false;
        if (self.history.items.len != 0) {
            add_to_history = !std.mem.eql(u8, self.inputBuffer[0..self.inputMax], self.history.items[self.history.items.len - 1]);
        } else {
            add_to_history = true;
        }

        if (add_to_history) {
            try self.addMessageToHistoryZ(self.inputBuffer[0..self.inputMax :0]);
        }

        self.historyIndex = -1;
        self.storedCommandLen = 0;
        self.storedCommandBuffer[0] = 0;

        try self.addMessageToLogZ(self.inputBuffer[0..self.inputMax :0], .{ .prepend = ">> " });

        self.scriptEng.run(self.inputBuffer[0..self.inputMax :0]) catch |err| {
            const msg = try std.fmt.allocPrint(self.alloc, "ERROR: {any}\n", .{err});
            defer self.alloc.free(msg);
            try self.addMessageToLog(msg, .{});
        };

        self.clearInput();
    }

    fn clearInput(self: *Console) void {
        @memset(self.inputBuffer, 0);
        self.inputMax = 0;
        self.shouldFocus = true;
    }

    fn copyInputFrom(self: *Console, msg: []const u8) void {
        const copy_len = @min(msg.len, self.inputBuffer.len - 1);
        @memset(self.inputBuffer, 0);
        @memcpy(self.inputBuffer[0..copy_len], msg[0..copy_len]);
        self.inputMax = copy_len;
    }

    fn copyStoredFromInput(self: *Console) void {
        const copy_len = @min(self.inputMax, self.storedCommandBuffer.len - 1);
        @memset(self.storedCommandBuffer, 0);
        @memcpy(self.storedCommandBuffer[0..copy_len], self.inputBuffer[0..copy_len]);
        self.storedCommandLen = copy_len;
    }

    fn historyPrev(self: *Console) bool {
        if (self.history.items.len == 0) return false;

        if (self.historyIndex == -1) {
            self.copyStoredFromInput();
            self.historyIndex = @intCast(self.history.items.len - 1);
        } else if (self.historyIndex > 0) {
            self.historyIndex -= 1;
        }

        const hist_index: usize = @intCast(self.historyIndex);
        self.copyInputFrom(self.history.items[hist_index]);
        self.shouldFocus = true;
        return true;
    }

    fn historyNext(self: *Console) bool {
        if (self.history.items.len == 0 or self.historyIndex == -1) return false;

        self.historyIndex += 1;
        if (self.historyIndex >= self.history.items.len) {
            self.historyIndex = -1;
            self.copyInputFrom(self.storedCommandBuffer[0..self.storedCommandLen]);
        } else {
            const hist_index: usize = @intCast(self.historyIndex);
            self.copyInputFrom(self.history.items[hist_index]);
        }

        self.shouldFocus = true;
        return true;
    }

    fn scrollToBottomForArea(self: *Console, ui: *imgui.UiContext, area_height: f32) void {
        const line_h: f32 = if (ui.text.font_handle) |h| @floatFromInt(h.val.maxY) else 16;
        const pad_y: f32 = @floatFromInt(ui.style.padding.y);
        const usable_h = @max(0.0, area_height - pad_y * 2.0);
        const visible: usize = @max(1, @as(usize, @intFromFloat(@floor(usable_h / line_h))));
        self.lineOffs = if (self.logBuffer.items.len > visible)
            self.logBuffer.items.len - visible
        else
            0;
    }

    /// Emits the console window and widgets into the current imgui frame.
    pub fn draw(self: *Console, ui: *imgui.UiContext) void {
        if (!self.enabled) return;

        const old_padding = ui.style.padding;
        ui.style.padding = self.opts.padding;
        defer ui.style.padding = old_padding;

        ui.beginWindow(self.opts.windowId, self.opts.title, &self.windowRect);
        defer ui.endWindow();

        if (self.shouldFocus) {
            ui.focusWidget(InputId);
            ui.setInputCursor(InputId, self.inputMax);
            self.shouldFocus = false;
        }

        const input_h: f32 = @floatFromInt(ui.style.input_height);
        const item_spacing: f32 = @floatFromInt(ui.style.item_spacing);
        const log_h = @max(input_h, ui.remainingHeight() - input_h - item_spacing);

        if (self.scrollToBottom) {
            self.scrollToBottomForArea(ui, log_h);
            self.scrollToBottom = false;
        }

        ui.textArea(LogId, self.logBuffer.items, &self.lineOffs, log_h);

        const input_res = ui.inputTextEx(InputId, self.inputBuffer, &self.inputMax, .{
            .submit_on_enter = true,
            .history_keys = true,
        });

        if (input_res.history_prev) {
            if (self.historyPrev()) ui.setInputCursor(InputId, self.inputMax);
        } else if (input_res.history_next) {
            if (self.historyNext()) ui.setInputCursor(InputId, self.inputMax);
        }

        if (input_res.submitted) {
            self.runCurrentInput() catch {};
            ui.setInputCursor(InputId, self.inputMax);
        }
    }
};
