// zig fmt: off
const std = @import("std");
const ziglua = @import("ziglua");
const zgui = @import("zgui");

const Lua = ziglua.Lua;

const utils = @import("./utils.zig");

const scripting = @import("./scripting.zig");
const ScriptEngine = scripting.ScriptEngine;

pub const ConsoleOpts = struct {
    numLogLines: usize = 2000,
};

pub const Console = struct {
    alloc: std.mem.Allocator,
    scriptEng: *ScriptEngine,
    history: std.ArrayList([]u8),
    historyIndex: i32,
    log: std.ArrayList([]u8),
    opts: ConsoleOpts,
    enabled: bool,
    shouldFocus: bool,
    inputBuffer: [:0]u8,
    storedCommandBuffer: [:0]u8,

    pub fn init(alloc: std.mem.Allocator, scriptEng: *ScriptEngine, opts: ConsoleOpts) !*Console {
        const console: *Console = try alloc.create(Console);
        console.* = .{
            .alloc = alloc,
            .scriptEng = scriptEng,
            .history = std.ArrayList([]u8).init(alloc),
            .historyIndex = -1,
            .log = std.ArrayList([]u8).init(alloc),
            .opts = opts,
            .enabled = true,
            .shouldFocus = true,
            .inputBuffer = try alloc.allocSentinel(u8, 256, 0),
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
        lua.setGlobal("my_console");

        // Pop the light userdata from the stack
        lua.pop(1);
        return console;
    }

    pub fn deinit(self: *Console) void {
        for (self.history.items) |entry| {
            // Free the history entries we allocated in our run command func.
            self.alloc.free(entry);
        }

        self.history.deinit();

        for (self.log.items) |entry| {
            // Free the log entries we allocated in our log func.
            self.alloc.free(entry);
        }

        self.log.deinit();
        self.alloc.free(self.inputBuffer);
        self.alloc.free(self.storedCommandBuffer);
        self.alloc.destroy(self);
    }

    fn addMessageToHistoryZ(self: *Console, msgC: [:0]const u8) !void {
        const newMsgC = try self.alloc.dupe(u8, msgC);
        try self.history.append(newMsgC[0..]);
    }

    const AddMessageOpts = struct {
        prepend: ?[]const u8 = null
    };

    fn addMessageToLogZ(self: *Console, msgC: [:0]const u8, opts: AddMessageOpts) !void {
        const msg = utils.cStrToSlice(msgC);
        try self.addMessageToLog(msg, opts);
    }

    fn addMessageToLog(self: *Console, msg: []const u8, opts: AddMessageOpts) !void {

        // Allocate a copy of the message to add to our log entries.
        var spaceNeeded: usize = msg.len;
        if(opts.prepend != null) {
            spaceNeeded += opts.prepend.?.len;
        }

        const new_msg = try self.alloc.alloc(u8, spaceNeeded);
        if(opts.prepend != null) {
            const startLen = opts.prepend.?.len;
            @memcpy(new_msg[0..startLen], opts.prepend.?);
            @memcpy(new_msg[startLen..], msg);
        }
        else {
            @memcpy(new_msg, msg);
        }

        try self.log.append(new_msg);
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
        std.debug.print("Running: {s}\n", .{self.inputBuffer});

        var addToHistory: bool = false;
        if( self.history.items.len != 0) {
            if(!std.mem.eql(u8, self.inputBuffer, self.history.items[self.history.items.len-1])) {
                addToHistory = true;
            }
        }
        else {
            addToHistory = true;
        }

        if(addToHistory) {
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

    }

    pub fn draw(self: *Console) void {
        if (zgui.begin("Console", .{ .flags = .{ .no_scrollbar = true }})) {
            const currSize = zgui.getWindowSize();
            const fontSize = zgui.getFontSize();
            _ = zgui.beginChild("ConsoleTest", .{
                .w = currSize[0] - 25, 
                .h = currSize[1] - 3*fontSize - 5,
                .window_flags = .{ .always_vertical_scrollbar = true }
            });
            
            for(0..self.log.items.len) |idx| {
                zgui.pushIntId(@intCast(idx));
                zgui.textWrapped("{s}", .{self.log.items[idx]});
                zgui.popId();
            }

            if(self.shouldFocus) {
                zgui.setScrollHereY(.{});
            }

            zgui.endChild();

            const historyLen = self.history.items.len;
            if(self.historyIndex == -1 or historyLen == 0) {
                zgui.text(">> ", .{});
            } 
            else {
                const currIdx = @as(i32, @intCast(historyLen)) - self.historyIndex;
                zgui.text("[{}/{}] >> ", .{currIdx, historyLen});
            }


            zgui.sameLine(.{});
            if(self.shouldFocus) {
                zgui.setKeyboardFocusHere(0);
                self.shouldFocus = false;
            }
            
            zgui.pushItemWidth(-1);
            if(zgui.inputText("##", .{ 
                .buf = self.inputBuffer, 
                .flags = .{ 
                    .enter_returns_true = true, 
                    .callback_history = true 
                },
                .callback = inputCallback,
                .user_data = self
            })) {
                self.runCurrentInput() catch {
                };
                self.shouldFocus = true;
            }
            zgui.popItemWidth();
        }
        zgui.end();
    }

    fn inputCallback(data: *zgui.InputTextCallbackData) i32 {
        const console: *Console = @alignCast(@ptrCast(data.user_data));

        if(data.event_flag.callback_history) {
            var updateText: bool = false;
            if(console.history.items.len > 0) {
                if(data.event_key == .up_arrow) {
                    if(console.historyIndex == -1) {
                        @memcpy(console.storedCommandBuffer, console.inputBuffer);
                        console.historyIndex = @intCast(console.history.items.len - 1);
                        updateText = true;
                    }
                    else if(console.historyIndex > 0) {
                        console.historyIndex -= 1;
                        updateText = true;
                    }

                    const histIndex: usize = @intCast(console.historyIndex);
                    @memcpy(console.inputBuffer, console.history.items[histIndex]);
                }
                else if(data.event_key == .down_arrow) {
                    if(console.historyIndex != -1) {
                        console.historyIndex += 1;

                        if(console.historyIndex >= console.history.items.len) {
                            console.historyIndex = -1;
                            @memcpy(console.inputBuffer, console.storedCommandBuffer);
                        }
                        else {
                            const histIndex: usize = @intCast(console.historyIndex);
                            @memcpy(console.inputBuffer, console.history.items[histIndex]);
                        }

                        updateText = true;
                    }
                }

                if(updateText) {
                    data.deleteChars(0, data.buf_text_len);
                    const msg = utils.cStrToSlice(console.inputBuffer);
                    data.insertChars(0, msg);
                }
            }
        }
        return 0;
    }
};
