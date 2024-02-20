// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const common = @import("./common.zig");

const Vec2U = common.Vec2U;

pub const Texture = struct {
    // GL Texture ID once loaded.
    texture: c_uint,
    size: Vec2U,
    name: ?[]u8,
};

pub const TextureManager = struct {
    textures: std.ArrayList(Texture),
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) TextureManager{
        const textures = std.ArrayList(Texture).init(alloc);
        return .{ .textures = textures, .allocator = alloc };
    }

    pub fn destroy(self: *TextureManager) void {
        for (self.textures.items) |t| {
            gl.deleteTextures(1, &t.texture);
            self.allocator.free(t.name.?);
        }
        self.textures.clearAndFree();
    }

    // TODO: Add error handler.
    pub fn loadTexture(self: *TextureManager, name: []const u8, file_path: []const u8) !*Texture{

        // Convert our string slice to a null terminated string
        var nt_str = try self.allocator.alloc(u8, file_path.len + 1);
        defer self.allocator.free(nt_str);
        @memcpy(nt_str[0..file_path.len], file_path);
        nt_str[file_path.len] = 0;
        const nt_file_path = nt_str[0..file_path.len :0];

        // Try to load an image
        var image = try stbi.Image.loadFromFile(nt_file_path, 0);
        defer image.deinit();

        std.debug.print("Loaded image '{s}', width={}, height={}\n", .{ name, image.width, image.height });

        var texture: c_uint = undefined;
        gl.genTextures(1, &texture);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        const format = gl.RGBA;
        gl.texImage2D(gl.TEXTURE_2D, 0, format, @intCast(image.width), @intCast(image.height), 0, format, gl.UNSIGNED_BYTE, @ptrCast(image.data));

        const copied_name = try self.allocator.alloc(u8, name.len);
        @memcpy(copied_name, name);
        try self.textures.append(.{
            .texture = texture,
            .size = .{ .x = image.width, .y = image.height },
            .name = copied_name,
        });

        return &self.textures.items[self.textures.items.len - 1];
    }
};


