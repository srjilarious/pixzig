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
        const xF = @as(f32, @floatFromInt(x));
        const yF = @as(f32, @floatFromInt(y));
        const wF = @as(f32, @floatFromInt(w));
        const hF = @as(f32, @floatFromInt(h));
        const szWF = @as(f32, @floatFromInt(szW));
        const szHF = @as(f32, @floatFromInt(szH));
        return .{
            .l = xF/szWF,
            .r = (xF+wF)/szWF,
            .t = yF/szHF,
            .b = (yF+hF)/szHF
        };
    }

    pub fn fromPosSize(x: i32, y: i32, w: i32, h: i32) RectF {
        const xF = @as(f32, @floatFromInt(x));
        const yF = @as(f32, @floatFromInt(y));
        const wF = @as(f32, @floatFromInt(w));
        const hF = @as(f32, @floatFromInt(h));
        return .{
            .l = xF,
            .r = xF + wF,
            .t = yF,
            .b = yF + hF
        };
    }
};

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn from(_r: u8, _g: u8, _b: u8, _a: u8) Color {
        const r = @as(f32, @floatFromInt(_r)) / 255;
        const g = @as(f32, @floatFromInt(_g)) / 255;
        const b = @as(f32, @floatFromInt(_b)) / 255;
        const a = @as(f32, @floatFromInt(_a)) / 255;
        return Color{
            .r = r,
            .g = g,
            .b = b,
            .a = a
        };
    }
};

