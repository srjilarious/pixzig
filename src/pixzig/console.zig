const std = @import("std");
const ziglua = @import("ziglua");

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

    pub fn init(alloc: std.mem.Allocator, scriptEng: *ScriptEngine, opts: ConsoleOpts) !*Console {
        const console: *Console = try alloc.create(Console);
        console.* = .{ .alloc = alloc, .scriptEng = scriptEng, .history = std.ArrayList([]u8).init(alloc), .opts = opts };

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
};
