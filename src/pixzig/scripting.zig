const std = @import("std");
const io = @import("./io.zig");
const ziglua = @import("ziglua");
const paths = @import("./paths.zig");

const Lua = ziglua.Lua;

/// Signature required by `registerFunc`. Arguments are read off the Lua stack
/// by index (1-based); the return value is the number of values pushed back
/// onto the stack for Lua to receive.
pub const LuaFunc = fn (*Lua) i32;

/// Wraps a Lua 5.3 state (via `ziglua`) with the standard libraries opened.
/// Owns the underlying `*Lua`; call `deinit()` to close it.
pub const ScriptEngine = struct {
    lua: *Lua,
    /// Kept for resolving script paths in `runScript`; the Lua state has its
    /// own copy for its internal allocations.
    alloc: std.mem.Allocator,

    /// Creates a new Lua state and opens the standard libraries (string,
    /// table, math, etc). `require` finds modules through the engine's file
    /// IO, like `runScript`; see `assetSearcher`.
    pub fn init(allocator: std.mem.Allocator) !ScriptEngine {
        var lua = try Lua.init(allocator);
        errdefer lua.deinit();
        lua.openLibs();
        try installAssetSearcher(lua);
        return .{ .lua = lua, .alloc = allocator };
    }

    pub fn deinit(self: *ScriptEngine) void {
        self.lua.deinit();
    }

    /// Registers `func` as a global Lua function named `name`. Prefer
    /// stateless functions here; use a context struct (see
    /// `sequencer.SeqScriptingContext`) when the function needs to touch
    /// engine state.
    pub fn registerFunc(self: *ScriptEngine, name: []const u8, comptime func: LuaFunc) !void {
        self.lua.pushFunction(ziglua.wrap(func));
        self.setGlobal(name);
    }

    /// Registers `method` as a global Lua function named `name` that is
    /// called with `ctx`, so a binding can reach its own state without a
    /// global. `ctx` is stored as a light userdata upvalue and must outlive
    /// the Lua state (or the function must be unregistered first).
    pub fn registerMethod(
        self: *ScriptEngine,
        comptime T: type,
        ctx: *T,
        name: []const u8,
        comptime method: fn (*T, *Lua) i32,
    ) !void {
        const Thunk = struct {
            fn call(lua: *Lua) i32 {
                const self_ptr = lua.toUserdata(T, Lua.upvalueIndex(1)) catch {
                    lua.raiseErrorStr("registerMethod: missing context upvalue", .{});
                };
                return method(self_ptr, lua);
            }
        };
        self.lua.pushLightUserdata(ctx);
        self.lua.pushClosure(ziglua.wrap(Thunk.call), 1);
        self.setGlobal(name);
    }

    /// Pops the value on top of the stack into the global `name`.
    pub fn setGlobal(self: *ScriptEngine, name: []const u8) void {
        self.lua.pushGlobalTable();
        _ = self.lua.pushString(name);
        self.lua.rotate(-3, -1); // value, globals, name -> globals, name, value
        self.lua.setTable(-3);
        self.lua.pop(1);
    }

    /// Pushes the global `name` onto the stack and returns its type.
    pub fn getGlobal(self: *const ScriptEngine, name: []const u8) ziglua.LuaType {
        self.lua.pushGlobalTable();
        _ = self.lua.pushString(name);
        const kind = self.lua.getTable(-2);
        self.lua.remove(-2);
        return kind;
    }

    /// Compiles and runs an inline Lua code string. On a syntax or runtime
    /// error, logs the Lua error message and returns `error.SyntaxError` /
    /// `error.ScriptError`.
    pub fn run(self: *ScriptEngine, code: []const u8) !void {
        const codeZ = try std.mem.concatWithSentinel(self.alloc, u8, &.{code}, 0);
        defer self.alloc.free(codeZ);

        // Compile a line of Lua code
        self.lua.loadString(codeZ) catch {
            // If there was an error, Lua will place an error string on the top of the stack.
            // Here we print out the string to inform the user of the issue.
            std.log.err("{s}\n", .{self.lua.toString(-1) catch unreachable});

            // Remove the error from the stack and go back to the prompt
            self.lua.pop(1);
            return error.SyntaxError;
        };

        // Execute a line of Lua code
        self.lua.protectedCall(.{ .args = 0, .results = 0, .msg_handler = 0 }) catch {
            // Error handling here is the same as above.
            std.log.err("{s}\n", .{self.lua.toString(-1) catch unreachable});
            self.lua.pop(1);
            return error.ScriptError;
        };
    }

    /// Runs a Lua file from disk. A relative path is resolved against the
    /// executable's own directory (see `paths`), so a packaged game finds
    /// its scripts wherever it is launched from. Like `run()`, logs the Lua
    /// error message and returns `error.SyntaxError` / `error.ScriptError`
    /// on syntax or runtime failure, plus `error.ScriptFileError` when the
    /// file can't be opened or read.
    pub fn runScript(self: *ScriptEngine, file: []const u8) !void {
        const resolved = try paths.resolve(self.alloc, file);
        defer self.alloc.free(resolved);

        // Read through `io` rather than `luaL_loadfile`, so a script inside
        // an Android APK loads like any other asset.
        const source = io.readFile(self.alloc, resolved) catch |err| {
            std.log.err("cannot open {s}: {}", .{ resolved, err });
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.ScriptFileError,
            };
        };
        defer self.alloc.free(source);
        // The "@" prefix is Lua's convention for a chunk named after its
        // file, so error messages read "path:line:" as luaL_loadfile's do.
        const chunk_name = try std.fmt.allocPrintSentinel(self.alloc, "@{s}", .{resolved}, 0);
        defer self.alloc.free(chunk_name);

        // Lua leaves an error message on the stack for every load failure.
        self.lua.loadBuffer(source, chunk_name, .binary_text) catch |err| {
            std.log.err("{s}\n", .{self.lua.toString(-1) catch unreachable});
            self.lua.pop(1);
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.SyntaxError,
            };
        };

        self.lua.protectedCall(.{ .args = 0, .results = 0, .msg_handler = 0 }) catch {
            std.log.err("{s}\n", .{self.lua.toString(-1) catch unreachable});
            self.lua.pop(1);
            return error.ScriptError;
        };
    }

    /// Reads the global Lua table named `globalName` into a Zig struct `T`.
    /// `T` must be default-constructible (`.{}`). A field missing from the
    /// Lua table (or set to nil) keeps its Zig default; a field present with
    /// the wrong type returns `error.InvalidFieldType`. Supported field
    /// types: `bool`, `int`, `float`, enums (read from a string naming one
    /// of the enum's fields; any other string returns
    /// `error.InvalidEnumValue`), and `?[]u8` (heap-allocated with the
    /// Lua allocator; caller frees it, e.g. via the struct's own `deinit`).
    /// A field of any other type returns `error.UnsupportedFieldType` when
    /// the table sets it. A missing or non-table global returns
    /// `error.InvalidConfigTable`.
    pub fn loadStruct(
        self: *const ScriptEngine,
        comptime T: type,
        globalName: []const u8,
    ) !T {
        // Push the global `config` table onto the stack
        _ = self.getGlobal(globalName);

        // Ensure the global `config` is a table
        if (!self.lua.isTable(-1)) {
            self.lua.pop(1); // Pop the `config` table
            return error.InvalidConfigTable;
        }

        var myStruct: T = .{};
        // Iterate over fields of the struct at comptime
        inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |field_name, field_type| {

            // Get the value from Lua, pushing `config.<field_name>` onto the
            // stack. A nil (absent) field keeps the struct's default.
            const luaType = self.lua.getField(-1, field_name);

            if (luaType != .nil) switch (@typeInfo(field_type)) {
                // Handle booleans
                .bool => {
                    if (!self.lua.isBoolean(-1)) {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidFieldType;
                    }
                    @field(myStruct, field_name) = self.lua.toBoolean(-1);
                },
                .int => {
                    if (!self.lua.isInteger(-1)) {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidFieldType;
                    }
                    @field(myStruct, field_name) = @intCast(try self.lua.toInteger(-1));
                },
                .float => {
                    if (!self.lua.isNumber(-1)) {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidFieldType;
                    }
                    @field(myStruct, field_name) = @floatCast(try self.lua.toNumber(-1));
                },
                .@"enum" => {
                    if (luaType != .string) {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidFieldType;
                    }
                    const name = try self.lua.toString(-1);
                    @field(myStruct, field_name) = std.meta.stringToEnum(field_type, name) orelse {
                        self.lua.pop(2); // Pop the value and table
                        return error.InvalidEnumValue;
                    };
                },
                .optional => |opt| {
                    switch (@typeInfo(opt.child)) {
                        .pointer => |ptr_info| switch (ptr_info.size) {
                            .slice => {
                                if (ptr_info.child != u8) {
                                    self.lua.pop(2); // Pop the value and table
                                    return error.UnsupportedFieldType;
                                }
                                if (luaType != .string) {
                                    self.lua.pop(2); // Pop the value and table
                                    return error.InvalidFieldType;
                                }

                                const lua_str = try self.lua.toString(-1);
                                const len: usize = self.lua.rawLen(-1);
                                const buffer = try self.lua.allocator().alloc(u8, len);
                                @memcpy(buffer, lua_str[0..len]);
                                @field(myStruct, field_name) = buffer;
                            },
                            else => {
                                self.lua.pop(2); // Pop the value and table
                                return error.UnsupportedFieldType;
                            },
                        },
                        else => {
                            self.lua.pop(2); // Pop the value and table
                            return error.UnsupportedFieldType;
                        },
                    }
                },
                // Add more cases for other types as needed
                else => {
                    self.lua.pop(2); // Pop the value and table
                    return error.UnsupportedFieldType;
                },
            };

            // Pop the value, keep the table
            self.lua.pop(1);
        }

        // Pop the global `config` table
        self.lua.pop(1);

        return myStruct;
    }
};

/// Puts `assetSearcher` into `package.searchers` just after the preload
/// searcher, ahead of Lua's own file searcher, which stays as a fallback
/// for paths relative to the working directory.
fn installAssetSearcher(lua: *Lua) !void {
    _ = lua.getGlobal("package") catch return error.NoLuaPackageLib;
    defer lua.pop(1);
    if (lua.getField(-1, "searchers") != .table) {
        lua.pop(1);
        return error.NoLuaPackageLib;
    }
    defer lua.pop(1);

    // Shift entries 2..n up one to make room at 2.
    var i: i32 = @intCast(lua.rawLen(-1));
    while (i >= 2) : (i -= 1) {
        _ = lua.rawGetIndex(-1, i);
        lua.rawSetIndex(-2, i + 1);
    }
    lua.pushFunction(ziglua.wrap(assetSearcher));
    lua.rawSetIndex(-2, 2);
}

/// A `package.searchers` entry that finds a module the way `runScript`
/// finds a script: each template in `package.path` has its `?` replaced by
/// the module name (dots become `/`), a relative result is resolved against
/// the asset base like every other asset path, and the file is read through
/// `io`. So `require "enemies.boss"` works from inside an Android APK, where
/// Lua's own searcher can't see. Add the game's script folder to the path:
///
/// ```lua
/// package.path = "assets/scripts/?.lua;" .. package.path
/// ```
///
/// Follows Lua's searcher protocol: returns the loaded chunk and the file it
/// came from, or a string listing the files tried. A file that's found but
/// doesn't compile is an error, as with Lua's own searcher.
fn assetSearcher(lua: *Lua) i32 {
    const name = lua.checkString(1);
    _ = lua.getGlobal("package") catch {
        _ = lua.pushString("\n\tno package table");
        return 1;
    };
    _ = lua.getField(-1, "path");
    // Both stay on the stack, so `templates` stays valid.
    const templates = lua.toString(-1) catch {
        _ = lua.pushString("\n\tpackage.path is not a string");
        return 1;
    };

    var mod_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (name.len > mod_buf.len) {
        _ = lua.pushString("\n\tmodule name too long");
        return 1;
    }
    const mod_path = mod_buf[0..name.len];
    for (name, 0..) |ch, i| mod_path[i] = if (ch == '.') '/' else ch;

    const alloc = lua.allocator();
    var tried: i32 = 0;
    var it = std.mem.splitScalar(u8, templates, ';');
    while (it.next()) |template| {
        if (template.len == 0) continue;
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const candidate = expandTemplate(&path_buf, template, mod_path) orelse continue;

        const found = readModule(alloc, candidate) catch |err| {
            _ = lua.pushFString("\n\tcannot read '%s': %s", .{ candidate.ptr, @errorName(err).ptr });
            tried += 1;
            continue;
        } orelse {
            _ = lua.pushFString("\n\tno file '%s'", .{candidate.ptr});
            tried += 1;
            continue;
        };

        // Free the Zig buffers before anything that can raise a Lua error,
        // which would skip a `defer`.
        const load_result = lua.loadBuffer(found.source, found.chunk_name, .binary_text);
        alloc.free(found.source);
        alloc.free(found.chunk_name);
        load_result catch {
            const msg: [:0]const u8 = lua.toString(-1) catch "?";
            lua.raiseErrorStr("error loading module '%s' from file '%s':\n\t%s", .{ name.ptr, candidate.ptr, msg.ptr });
        };
        _ = lua.pushString(candidate);
        return 2;
    }

    if (tried == 0) _ = lua.pushString("");
    if (tried > 1) lua.concat(tried);
    return 1;
}

/// `template` with each `?` replaced by `mod_path`, a leading `./` dropped
/// (SDL can't open that inside an APK, and it means nothing to the asset
/// base), null-terminated in `buf`. Null when it doesn't fit.
fn expandTemplate(buf: []u8, template: []const u8, mod_path: []const u8) ?[:0]const u8 {
    const t = if (std.mem.startsWith(u8, template, "./")) template[2..] else template;
    var len: usize = 0;
    for (t) |ch| {
        const piece: []const u8 = if (ch == '?') mod_path else &.{ch};
        if (len + piece.len + 1 > buf.len) return null;
        @memcpy(buf[len..][0..piece.len], piece);
        len += piece.len;
    }
    buf[len] = 0;
    return buf[0..len :0];
}

const FoundModule = struct {
    source: []u8,
    /// `@` and the resolved path, Lua's chunk name for a file.
    chunk_name: [:0]u8,
};

/// Reads the module file `candidate` (resolved like any asset path), or
/// null when there's no such file. The caller frees both buffers.
fn readModule(alloc: std.mem.Allocator, candidate: []const u8) !?FoundModule {
    const resolved = try paths.resolve(alloc, candidate);
    defer alloc.free(resolved);
    const source = io.readFile(alloc, resolved) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    errdefer alloc.free(source);
    const chunk_name = try std.fmt.allocPrintSentinel(alloc, "@{s}", .{resolved}, 0);
    return .{ .source = source, .chunk_name = chunk_name };
}
