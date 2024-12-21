// zig fmt: off
const std = @import("std");

pub const Vec2I = struct { 
    x: i32, 
    y: i32,

    pub fn asVec2F(self: *const Vec2I) Vec2F {
        return .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) };
    } 
};

pub const Vec2U = struct { x: u32, y: u32 };
pub const Vec2F = struct { 
    x: f32, 
    y: f32,

    pub fn asVec2I(self: *const Vec2F) Vec2I {
        return .{ .x = @intFromFloat(self.x), .y = @intFromFloat(self.y) };
    } 
};

pub const RectF = struct {
    l: f32,
    t: f32,
    r: f32,
    b: f32,

    pub fn width(self: *const RectF) f32 {
        return self.r - self.l;
    }

    pub fn height(self: *const RectF) f32 {
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

    pub fn ensureSize(self: *RectF, w: i32, h: i32) void {
        const wF = @as(f32, @floatFromInt(w));
        const hF = @as(f32, @floatFromInt(h));
        self.r = self.l + wF;
        self.b = self.t + hF;
    }

    pub fn size2U(self: *const RectF) Vec2U {
        const w: usize = @intFromFloat(self.width());
        const h: usize = @intFromFloat(self.height());
        return .{ .x = w, .y = h };
    }
};

pub const RectI = struct {
    l: i32,
    t: i32,
    r: i32,
    b: i32,

    pub fn init(l: i32, t: i32, w: i32, h:i32) RectI {
        return RectI{
            .l = l,
            .t = t,
            .r = l + w,
            .b = t + h,
        };
    }

    pub fn width(self: *const RectI) i32 {
        return self.r - self.l;
    }

    pub fn height(self: *const RectI) i32 {
        return self.b - self.t;
    }

    pub fn size2U(self: *const RectI) Vec2U {
        const w: usize = @intCast(self.width());
        const h: usize = @intCast(self.height());
        return .{ .x = w, .y = h };
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

pub const Color8 = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn from(r: u8, g: u8, b: u8, a:u8) Color8 {
        return .{ .r=r, .g=g, .b=b, .a=a };
    }
};

pub const Rotate = enum {
    none,
    rot90,
    rot180,
    rot270,
    flipHorz,
    flipVert,
};
