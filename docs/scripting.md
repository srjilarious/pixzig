# Scripting

Pixzig embeds Lua 5.3 via the `ziglua` library and exposes it through `ScriptEngine`, a thin wrapper around a Lua state. Scripts can load configuration, drive sequences, or call back into Zig through registered C functions.

## ScriptEngine Basics

```zig
const scripting = pixzig.scripting;

var eng = try scripting.ScriptEngine.init(allocator);
defer eng.deinit();
```

### Running Code

Execute an inline string:

```zig
try eng.run(
    \\x = 42
    \\print("hello from Lua!")
);
```

Execute a file:

```zig
try eng.runScript("assets/config.lua");
```

Both methods print the Lua error to stderr and return `error.ScriptError` on failure — you can catch and log rather than panic.

### Registering Zig Functions

Expose a Zig function to Lua as a global:

```zig
const ziglua = pixzig.ziglua;

fn myLuaFunc(lua: *ziglua.Lua) i32 {
    const n = lua.toInteger(1) catch 0; // first argument
    lua.pushInteger(n * 2);             // return value
    return 1;                           // number of return values
}

try eng.registerFunc("double", myLuaFunc);
// Lua: local result = double(21)  --> 42
```

The function signature is `fn(*ziglua.Lua) i32`. Arguments are read from the stack by index (1-based) using `lua.toInteger`, `lua.toNumber`, `lua.toString`, etc. Return values are pushed onto the stack; the return count is the i32.

### Loading Structs from Lua Tables

Deserialise a Lua table into a Zig struct:

```zig
// config.lua:
// config = { fullscreen = true, scale = 4, title = "My Game" }

const Config = struct {
    fullscreen: bool  = false,
    scale:      i32   = 1,
    title:      ?[]u8 = null,

    pub fn deinit(self: *const Config, alloc: std.mem.Allocator) void {
        if (self.title) |t| alloc.free(t);
    }
};

try eng.runScript("assets/config.lua");
var cfg = try eng.loadStruct(Config, "config");
defer cfg.deinit(allocator);

// cfg.fullscreen == true, cfg.scale == 4, cfg.title == "My Game"
```

Supported field types: `bool`, `int`, `float`, and `?[]u8` (heap-allocated string, caller frees). Unsupported field types return `error.UnsupportedFieldType`.

## Accessing the Raw Lua State

`ScriptEngine.lua` is the underlying `*ziglua.Lua`. Use it to push globals before running a script, or to call any ziglua API directly:

```zig
// Push an entity ID as a Lua global before running a script.
eng.lua.pushInteger(@intCast(entity_id));
eng.lua.setGlobal("player_entity");

eng.lua.pushNumber(sprite_x);
eng.lua.setGlobal("player_x");

try eng.runScript("assets/my_script.lua");
```

## Sequence Scripting

`SeqScriptingContext` wires a `SequencePlayer` to Lua, so scripts can build and queue action sequences without any Zig glue code per script. See the [Sequences](sequences.html) guide for full details.

```zig
var seqCtx = seq.SeqScriptingContext.init(alloc, world, &seqPlayer);
defer seqCtx.deinit();

// Register seq_new / seq_wait / seq_move_to / seq_set_actor_state / seq_play
seqCtx.bindToLua(scriptEng.lua);
```

Then in Lua:

```lua
local h = seq_new()
seq_wait(h, 500)
seq_move_to(h, player_entity, 100, 50, 300)
seq_play(h)
```

## Console Integration

`console2` provides an interactive in-game Lua console that reads lines from the user, executes them against a shared `ScriptEngine`, and renders output as text. See `examples/console2_test.zig` for a complete setup.

## Tips

- Use `runScript` for data-driven config and level scripts that live on disk.
- Use `run` for short, generated, or unit-tested code strings.
- Keep Zig functions registered via `registerFunc` small and stateless; use the `SeqScriptingContext` or a similar context struct for anything that needs to touch engine state.
- Lua 5.3 integers are 64-bit signed. Cast flecs entity IDs with `@intCast(entity_id)` when pushing (entity IDs fit in i64 for reasonable values).
