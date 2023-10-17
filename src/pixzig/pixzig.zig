const std = @import("std");
const sdl = @import("zsdl");
const stbi = @import("zstbi");

// pub const Texture = struct {
//     pub var texture: *sdl.Texture;
//     pub var name: [*]u8;
// };
// pub const TextureManager = struct {
//     var textures: std.ArrayList(Texture);
//     pub fn init() TextureManager {
//
//     }
// };

pub fn create(title: [:0]const u8) !PixzigEngine {
    _ = sdl.setHint(sdl.hint_windows_dpi_awareness, "system");
    try sdl.init(.{ .audio = true, .video = true });
    stbi.init(std.heap.page_allocator);

    var win = try sdl.Window.create(
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

    var render = try sdl.Renderer.create(win, -1, .{ .accelerated = true });

    return .{ .window = win, .renderer = render };
}

pub const PixzigEngine = struct {
    window: *sdl.Window,
    renderer: *sdl.Renderer,

    pub fn destroy(self: *PixzigEngine) void {
        self.renderer.destroy();
        self.window.destroy();
        stbi.deinit();
        sdl.quit();
    }
};

pub fn hi() void {
    std.debug.print("Hi!", .{});
}
