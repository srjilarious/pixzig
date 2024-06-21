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
    opts: ConsoleOpts,
    enabled: bool,
    inputBuffer: [:0]u8,

    pub fn init(alloc: std.mem.Allocator, scriptEng: *ScriptEngine, opts: ConsoleOpts) !*Console {
        const console: *Console = try alloc.create(Console);
        console.* = .{ 
            .alloc = alloc, 
            .scriptEng = scriptEng, 
            .history = std.ArrayList([]u8).init(alloc), 
            .opts = opts, 
            .enabled = true,
            .inputBuffer = try alloc.allocSentinel(u8, 256, 0),
        };

        @memset(console.inputBuffer, 0);

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
            // Free the log entries we allocated in our log func.
            self.alloc.free(entry);
        }

        self.history.deinit();
        self.alloc.free(self.inputBuffer);
        self.alloc.destroy(self);
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
        const msg = utils.cStrToSlice(msgC);

        // Allocate a copy of the message to add to our log entries.
        const new_msg = console.alloc.dupe(u8, msg) catch {
            std.debug.print("log(): Couldn't allocate for console history!\n", .{});
            return 0;
        };

        console.history.append(new_msg) catch {
            std.debug.print("Error adding message to history!\n", .{});
            return 0;
        };

        std.debug.print("CONSOLE: {s}\n", .{msg});
        return 0;
    }

    pub fn draw(self: *Console) void {
        if (zgui.begin("Console", .{})) {
            _ = zgui.beginChild("ConsoleTest", .{});
            for(0..self.history.items.len) |idx| {
                zgui.pushIntId(@intCast(idx));
                zgui.textWrapped("{s}", .{self.history.items[idx]});
                zgui.popId();
            }

            if(zgui.inputText("Input", .{ 
                .buf = self.inputBuffer, 
                .flags = .{ 
                    .enter_returns_true = true, 
                    .callback_history = true 
                },
                .callback = inputCallback,
                .user_data = self
            })) {
                std.debug.print("Returned true from console!", .{});
            }
            zgui.endChild();
        }
        zgui.end();
    }

    fn inputCallback(data: *zgui.InputTextCallbackData) i32 {
        std.debug.print("Callback hit!", .{});
        const console: *Console = @alignCast(@ptrCast(data.user_data));
        _ = console;
        return 0;
    }
};
