const std = @import("std");
const sdl = @import("zsdl");

pub const Sprite = struct {
    texture: *sdl.Texture,
    src_coords: sdl.Rect,
    dest: sdl.Rect,

    pub fn create(tex: *sdl.Texture, scoords: sdl.Rect) Sprite {
        return Sprite{ .texture = tex, .src_coords = scoords, .dest = .{ .x = 0, .y = 0, .w = scoords.w, .h = scoords.h } };
    }

    pub fn setPos(self: *Sprite, x: i32, y: i32) void {
        self.dest.x = x;
        self.dest.y = y;
    }

    pub fn draw(self: *Sprite, renderer: *sdl.Renderer) !void {
        try renderer.copy(self.texture, &self.src_coords, &self.dest);
    }
};
