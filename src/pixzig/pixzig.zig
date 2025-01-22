// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("zsdl");
const glfw = @import("zglfw");
const stbi = @import("zstbi");

const zopengl = @import("zopengl");

const zgui = @import("zgui");

pub const common = @import("./common.zig");
pub const sprites = @import("./sprites.zig");
pub const input = @import("./input.zig");
pub const tile = @import("./tile.zig");
pub const shaders = @import("./shaders.zig");
pub const textures= @import("./textures.zig");
pub const renderer = @import("./renderer.zig");
pub const utils = @import("./utils.zig");
pub const gamestate = @import("./gamestate.zig");
pub const scripting = @import("./scripting.zig");
pub const console = @import("./console.zig");
pub const collision = @import("./collision.zig");
pub const a_star = @import("./a_star.zig");

pub const Texture = textures.Texture;
const TextureManager = textures.TextureManager;

pub const Vec2I = common.Vec2I;
pub const RectF = common.RectF;
pub const Color = common.Color;
pub const Color8 = common.Color8;


pub const PixzigEngineOptions = struct {
    withGui: bool = false,
    fullscreen: bool = false,
    windowSize: Vec2I = .{ .x = 800, .y = 600 },
};

extern fn emscripten_err([*c]const u8) void;
extern fn emscripten_console_error([*c]const u8) void;
extern fn emscripten_console_warn([*c]const u8) void;
extern fn emscripten_console_log([*c]const u8) void;

pub const MainLoopCallback = *const fn () callconv(.C) void;
extern fn emscripten_set_main_loop(MainLoopCallback, c_int, c_int) void;
pub fn setMainLoop(cb: MainLoopCallback, maybe_fps: ?i16, simulate_infinite_loop: bool) void {
    std.debug.print("Setting main loop internal.\n", .{});
    emscripten_set_main_loop(cb, if (maybe_fps) |fps| fps else -1, @intFromBool(simulate_infinite_loop));
}

/// std.panic impl
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;

    var buf: [1024]u8 = undefined;
    const error_msg: [:0]u8 = std.fmt.bufPrintZ(&buf, "PANIC! {s}", .{msg}) catch unreachable;
    emscripten_err(error_msg.ptr);

    while (true) {
        @breakpoint();
    }
}

/// std.log impl
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const prefix = level_txt ++ prefix2;

    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrintZ(buf[0 .. buf.len - 1], prefix ++ format, args) catch |err| {
        switch (err) {
            error.NoSpaceLeft => {
                emscripten_console_error("log message too long, skipped.");
                return;
            },
        }
    };
    switch (level) {
        .err => emscripten_console_error(@ptrCast(msg.ptr)),
        .warn => emscripten_console_warn(@ptrCast(msg.ptr)),
        else => emscripten_console_log(@ptrCast(msg.ptr)),
    }
}

pub fn PixzigApp(comptime T: type) type {
    const AppStruct = struct {
        const AppUpdateFunc = fn (*T, *PixzigEngine, f64) bool;
        const AppRenderFunc = fn (*T, *PixzigEngine) void;
        
        const UpdateStepUs: f64 = 1.0 / 120.0;

        lag: f64 = 0,
        currTime: f64 = 0,

        const Self = @This();

        pub fn begin(self: *Self) void {
            self.currTime = glfw.getTime();
        }

        pub fn gameLoopCore(self: *Self, app: *T, eng: *PixzigEngine) bool {
            const newCurrTime = glfw.getTime();
            const delta = newCurrTime - self.currTime;
            self.lag += delta;
            self.currTime = newCurrTime;

            glfw.pollEvents();


            while(self.lag > UpdateStepUs) {
                self.lag -= UpdateStepUs;

                if(!app.update(eng, UpdateStepUs)) {
                    return false;
                }
            }

            app.render(eng);
            eng.window.swapBuffers();
            return true;
        }

        pub fn gameLoop(self: *Self, app: *T, eng: *PixzigEngine) void {
            // Main loop
            while (!eng.window.shouldClose()) {
                if(!self.gameLoopCore(app, eng)) return;
            }
        }
    };

    return AppStruct;
}

pub const PixzigEngine = struct {
    window: *glfw.Window,
    options: PixzigEngineOptions,
    scaleFactor: f32,
    allocator: std.mem.Allocator,
    textures: TextureManager,
    keyboard: input.Keyboard,

    pub fn init(title: [:0]const u8, 
                allocator: std.mem.Allocator,
                options: PixzigEngineOptions) !PixzigEngine {
        try glfw.init();

        // // Change current working directory to where the executable is located.
        // {
        //     var buffer: [1024]u8 = undefined;
        //     const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        //     std.os.chdir(path) catch {};
        // }

        std.debug.print("GLFW initialized.\n", .{});

        const gl_minor = 0;
        const gl_major = blk: {
            if(builtin.target.os.tag == .emscripten) {
                break :blk 2;
            }
            else {
                break :blk 4;
            }
        };

        glfw.windowHintTyped(.context_version_major, gl_major);
        glfw.windowHintTyped(.context_version_minor, gl_minor);

        glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
        glfw.windowHintTyped(.opengl_forward_compat, true);
        glfw.windowHintTyped(.client_api, .opengl_api);
        glfw.windowHintTyped(.doublebuffer, true);
        glfw.windowHintTyped(.resizable, false);

        const monitor = blk: {
            if(options.fullscreen) {
                break :blk glfw.Monitor.getPrimary();
            }
            else {
                break :blk  null;
            }
        };
        const window = try glfw.Window.create(
                options.windowSize.x,
                options.windowSize.y,
                title,
                monitor
            );
        window.setSizeLimits(400, 400, -1, -1);

        glfw.makeContextCurrent(window);
        glfw.swapInterval(1);

        if(builtin.target.os.tag == .emscripten) {
            try zopengl.loadEsProfile(glfw.getProcAddress, gl_major, gl_minor);
        } else {
            try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);
        }
        
        
        const scale_factor = scale_factor: {
            const scale = window.getContentScale();
            break :scale_factor @max(scale[0], scale[1]);
        };

        if(options.withGui) {
            zgui.init(allocator);
            zgui.getStyle().scaleAllSizes(scale_factor);
            zgui.backend.init(window);
        }

        stbi.init(allocator);
        return .{
            .window = window,
            .options = options,
            .scaleFactor = scale_factor,
            .allocator = allocator,
            .textures = TextureManager.init(allocator),
            .keyboard = input.Keyboard.init(window, allocator),
        };
    }

    pub fn deinit(self: *PixzigEngine) void {
        stbi.deinit();
        self.textures.destroy();

        if(self.options.withGui) {
            zgui.backend.deinit();
            zgui.deinit();
        }

        self.window.destroy();
        glfw.terminate();
        
    }
};
