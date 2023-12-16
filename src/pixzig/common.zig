// zig fmt: off
const std = @import("std");

pub const Vec2I = struct { x: i32, y: i32 };
pub const Vec2U = struct { x: u32, y: u32 };
pub const RectF = struct {
    l: f32,
    t: f32,
    r: f32,
    b: f32,

    pub fn width(self: *RectF) f32 {
        return self.r - self.l;
    }

    pub fn height(self: *RectF) f32 {
        return self.b - self.t;
    }

    pub fn fromCoords(x: i32, y: i32, w: i32, h: i32, szW:i32, szH:i32) RectF {
        const xF = @as(f32, @floatCast(x));
        const yF = @as(f32, @floatCast(y));
        const wF = @as(f32, @floatCast(w));
        const hF = @as(f32, @floatCast(h));
        const szWF = @as(f32, @floatCast(szW));
        const szHF = @as(f32, @floatCast(szH));
        return .{
            .l = xF/szWF,
            .r = (xF+wF)/szWF,
            .t = yF/szHF,
            .b = (yF+hF)/szHF
        };
    }
};
