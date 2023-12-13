// zig fmt: off
const std = @import("std");
const sdl = @import("zsdl");
const glfw = @import("zglfw");
const stbi = @import("zstbi");

const gl = @import("zopengl");

const zgui = @import("zgui");

pub const common = @import("./common.zig");
pub const sprites = @import("./sprites.zig");
pub const input = @import("./input.zig");
pub const tile = @import("./tile.zig");

pub const Vec2I = common.Vec2I;

pub const Texture = struct {
    texture: *sdl.Texture,
    name: ?[]u8,
};

pub const TextureManager = struct {
    textures: std.ArrayList(Texture),
    renderer: *sdl.Renderer,
    allocator: std.mem.Allocator,

    pub fn init(renderer: *sdl.Renderer, alloc: std.mem.Allocator) TextureManager {
        const textures = std.ArrayList(Texture).init(alloc);
        return .{ .textures = textures, .renderer = renderer, .allocator = alloc };
    }

    pub fn destroy(self: *TextureManager) void {
        for (self.textures.items) |t| {
            t.texture.destroy();
            self.allocator.free(t.name.?);
        }
        self.textures.clearAndFree();
    }

    // TODO: Add error handler.
    pub fn loadTexture(self: *TextureManager, name: []const u8, file_path: []const u8) !*Texture {

        // Convert our string slice to a null terminated string
        var nt_str = try self.allocator.alloc(u8, file_path.len + 1);
        defer self.allocator.free(nt_str);
        @memcpy(nt_str, file_path);
        nt_str[file_path.len] = 0;
        const nt_file_path = nt_str[0..file_path.len :0];

        // Try to load an image
        var image = try stbi.Image.loadFromFile(nt_file_path, 0);
        defer image.deinit();

        std.debug.print("Loaded image '{s}', width={}, height={}\n", .{ name, image.width, image.height });

        var surf = try sdl.Surface.createRGBSurfaceFrom(
            image.data, 
            image.width, 
            image.height, 
            32, 
            image.width * 4, 
            0x000000FF, // red mask
            0x0000FF00, // green mask
            0x00FF0000, // blue mask
            0xFF000000 // alpha mask
        );

        const tex = try self.renderer.createTextureFromSurface(surf);
        surf.free();

        const copied_name = try self.allocator.alloc(u8, name.len);
        @memcpy(copied_name, name);
        try self.textures.append(.{
            .texture = tex,
            .name = copied_name,
        });

        return &self.textures.items[self.textures.items.len - 1];
    }
};


pub const PixzigEngine = struct {
    window: *sdl.Window,
    renderer: *sdl.Renderer,
    textures: TextureManager,
    keyboard: input.Keyboard,

    pub fn create(title: [:0]const u8, allocator: std.mem.Allocator) !PixzigEngine {
        _ = sdl.setHint(sdl.hint_windows_dpi_awareness, "system");
        try sdl.init(.{ .audio = true, .video = true });
        stbi.init(std.heap.page_allocator);

        const win = try sdl.Window.create(
            title,
            sdl.Window.pos_undefined,
            sdl.Window.pos_undefined,
            600,
            600,
            .{
                .opengl = true,
                .allow_highdpi = true,
            },
        );

        const render = try sdl.Renderer.create(win, -1, .{ .accelerated = true });

        const texMgr = TextureManager.init(render, allocator);
        return .{ 
            .window = win, 
            .renderer = render, 
            .textures = texMgr,
            .keyboard = input.Keyboard.init(allocator),
        };
    }

    pub fn destroy(self: *PixzigEngine) void {
        self.textures.destroy();
        self.renderer.destroy();
        self.window.destroy();
        stbi.deinit();
        sdl.quit();
    }
};

pub const PixzigEngineGlfwOptions = struct {
    withGui: bool = true,
    windowSize: Vec2I = .{ .x = 800, .y = 600 },
};

pub const PixzigEngineGlfw = struct {
    window: *glfw.Window,
    options: PixzigEngineGlfwOptions,
    scaleFactor: f32,
    allocator: std.mem.Allocator,
    // textures: TextureManager,
    // keyboard: input.Keyboard,

    pub fn init(title: [:0]const u8, 
                allocator: std.mem.Allocator,
                options: PixzigEngineGlfwOptions) !PixzigEngineGlfw {
        try glfw.init();

        // // Change current working directory to where the executable is located.
        // {
        //     var buffer: [1024]u8 = undefined;
        //     const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        //     std.os.chdir(path) catch {};
        // }

        const gl_major = 4;
        const gl_minor = 0;
        glfw.windowHintTyped(.context_version_major, gl_major);
        glfw.windowHintTyped(.context_version_minor, gl_minor);
        glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
        glfw.windowHintTyped(.opengl_forward_compat, true);
        glfw.windowHintTyped(.client_api, .opengl_api);
        glfw.windowHintTyped(.doublebuffer, true);

        const window = try glfw.Window.create(
                options.windowSize.x, 
                options.windowSize.y, 
                title, 
                null
            );
        window.setSizeLimits(400, 400, -1, -1);

        glfw.makeContextCurrent(window);
        glfw.swapInterval(1);

        try gl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);
        
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
            .allocator = allocator
        };
    }

    pub fn deinit(self: *PixzigEngineGlfw) void {
        stbi.deinit();
        if(self.options.withGui) {
            zgui.backend.deinit();
            zgui.deinit();
        }

        self.window.destroy();
        glfw.terminate();
        
    }
};
