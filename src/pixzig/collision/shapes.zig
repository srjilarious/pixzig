//! Narrow-phase collision tests between simple shapes: circles, rects,
//! segments and polygons. Pure functions with no state, for use after a
//! broad phase (`CollisionGrid`) has picked the candidate pairs.
//!
//! Coordinates follow the rest of pixzig: y grows downward, and a `RectF`
//! is axis-aligned. Shapes that only touch (zero overlap) do not collide.
const std = @import("std");
const common = @import("../common.zig");

const Vec2F = common.Vec2F;
const RectF = common.RectF;

pub const Circle = struct {
    center: Vec2F,
    radius: f32,

    /// The smallest rect containing the circle, e.g. for a broad phase
    /// insert.
    pub fn bounds(self: Circle) RectF {
        return .{
            .l = self.center.x - self.radius,
            .t = self.center.y - self.radius,
            .r = self.center.x + self.radius,
            .b = self.center.y + self.radius,
        };
    }
};

/// A line segment from `a` to `b`, e.g. a bullet's path over one tick.
pub const Segment = struct {
    a: Vec2F,
    b: Vec2F,

    /// The point `t` of the way along the segment (0 is `a`, 1 is `b`).
    pub fn at(self: Segment, t: f32) Vec2F {
        return self.a.lerp(self.b, t);
    }
};

/// How two overlapping shapes collide. `normal` is a unit vector pointing
/// from the second shape toward the first, and `depth` is how far they
/// overlap along it, so moving the first shape by `mtv()` (the minimum
/// translation vector) separates them.
pub const Overlap = struct {
    normal: Vec2F,
    depth: f32,

    pub fn mtv(self: Overlap) Vec2F {
        return self.normal.scale(self.depth);
    }
};

/// Where a segment first enters a shape. `t` is how far along the segment
/// (0 to 1), `point` the position there, and `normal` the shape's outward
/// surface normal at that point. A segment that starts inside the shape
/// hits at `t = 0` with a zero `normal`.
pub const SegmentHit = struct {
    t: f32,
    point: Vec2F,
    normal: Vec2F,
};

/// Whether `p` is inside the circle (its edge counts as inside).
pub fn pointInCircle(p: Vec2F, c: Circle) bool {
    return p.sub(c.center).lengthSq() <= c.radius * c.radius;
}

/// Whether `p` is inside the polygon `poly`, given as its corners in order
/// (either winding; the last corner joins back to the first). Works for
/// concave polygons. A point exactly on an edge may land either way.
pub fn pointInPolygon(p: Vec2F, poly: []const Vec2F) bool {
    if (poly.len < 3) return false;
    var inside = false;
    var j = poly.len - 1;
    for (poly, 0..) |pi, i| {
        const pj = poly[j];
        // Count crossings of a ray from `p` toward +x.
        if ((pi.y > p.y) != (pj.y > p.y)) {
            const crossX = pj.x + (p.y - pj.y) * (pi.x - pj.x) / (pi.y - pj.y);
            if (p.x < crossX) inside = !inside;
        }
        j = i;
    }
    return inside;
}

/// Overlap of circles `a` and `b`, or null when they don't overlap. When
/// the centers coincide the normal is chosen as up (0, -1).
pub fn circleCircle(a: Circle, b: Circle) ?Overlap {
    const d = a.center.sub(b.center);
    const radii = a.radius + b.radius;
    const distSq = d.lengthSq();
    if (distSq >= radii * radii) return null;
    const dist = @sqrt(distSq);
    if (dist == 0) return .{ .normal = .{ .x = 0, .y = -1 }, .depth = radii };
    return .{ .normal = d.scale(1 / dist), .depth = radii - dist };
}

/// Overlap of circle `c` and rect `r`, or null when they don't overlap.
/// The normal points from the rect toward the circle. A circle whose
/// center is inside the rect is pushed out through the nearest edge.
pub fn circleRect(c: Circle, r: RectF) ?Overlap {
    const closest: Vec2F = .{
        .x = std.math.clamp(c.center.x, r.l, r.r),
        .y = std.math.clamp(c.center.y, r.t, r.b),
    };
    const d = c.center.sub(closest);
    const distSq = d.lengthSq();

    if (distSq > 0) {
        if (distSq >= c.radius * c.radius) return null;
        const dist = @sqrt(distSq);
        return .{ .normal = d.scale(1 / dist), .depth = c.radius - dist };
    }

    // The center is inside (or on the edge of) the rect: leave through the
    // closest edge.
    const edge = nearestEdge(c.center, r);
    return .{ .normal = edge.normal, .depth = edge.dist + c.radius };
}

/// Overlap of rects `a` and `b`, or null when they don't overlap. The
/// normal is along whichever axis overlaps least, pointing from `b`
/// toward `a`.
pub fn rectRect(a: RectF, b: RectF) ?Overlap {
    const overlapX = @min(a.r, b.r) - @max(a.l, b.l);
    const overlapY = @min(a.b, b.b) - @max(a.t, b.t);
    if (overlapX <= 0 or overlapY <= 0) return null;

    const ac = a.centerF();
    const bc = b.centerF();
    if (overlapX < overlapY) {
        const sign: f32 = if (ac.x < bc.x) -1 else 1;
        return .{ .normal = .{ .x = sign, .y = 0 }, .depth = overlapX };
    }
    const sign: f32 = if (ac.y < bc.y) -1 else 1;
    return .{ .normal = .{ .x = 0, .y = sign }, .depth = overlapY };
}

/// Where segment `s` first enters circle `c`, or null if it never does.
pub fn segmentCircle(s: Segment, c: Circle) ?SegmentHit {
    if (pointInCircle(s.a, c)) return .{ .t = 0, .point = s.a, .normal = Vec2F.zero };

    // Solve |a + t*d - center|^2 = r^2 for the smaller root.
    const d = s.b.sub(s.a);
    const f = s.a.sub(c.center);
    const qa = d.lengthSq();
    if (qa == 0) return null;
    const qb = 2 * f.dot(d);
    const qc = f.lengthSq() - c.radius * c.radius;
    const disc = qb * qb - 4 * qa * qc;
    if (disc < 0) return null;

    const t = (-qb - @sqrt(disc)) / (2 * qa);
    if (t < 0 or t > 1) return null;
    const point = s.at(t);
    return .{ .t = t, .point = point, .normal = point.sub(c.center).normalize() };
}

/// Where segment `s` first enters rect `r`, or null if it never does.
pub fn segmentRect(s: Segment, r: RectF) ?SegmentHit {
    if (s.a.x > r.l and s.a.x < r.r and s.a.y > r.t and s.a.y < r.b) {
        return .{ .t = 0, .point = s.a, .normal = Vec2F.zero };
    }

    // Slab test: clip t to where the segment is inside both axis bands,
    // remembering which face it entered through last.
    const d = s.b.sub(s.a);
    var tEnter: f32 = 0;
    var tExit: f32 = 1;
    var normal = Vec2F.zero;

    const axes = [_]struct { start: f32, delta: f32, lo: f32, hi: f32, unit: Vec2F }{
        .{ .start = s.a.x, .delta = d.x, .lo = r.l, .hi = r.r, .unit = .{ .x = 1, .y = 0 } },
        .{ .start = s.a.y, .delta = d.y, .lo = r.t, .hi = r.b, .unit = .{ .x = 0, .y = 1 } },
    };
    for (axes) |ax| {
        if (ax.delta == 0) {
            // Parallel to this slab: inside it for the whole segment, or never.
            if (ax.start <= ax.lo or ax.start >= ax.hi) return null;
            continue;
        }
        var t0 = (ax.lo - ax.start) / ax.delta;
        var t1 = (ax.hi - ax.start) / ax.delta;
        // Entering through the low face means the outward normal is -unit.
        var faceNormal = ax.unit.neg();
        if (t0 > t1) {
            std.mem.swap(f32, &t0, &t1);
            faceNormal = ax.unit;
        }
        if (t0 > tEnter) {
            tEnter = t0;
            normal = faceNormal;
        }
        tExit = @min(tExit, t1);
        if (tEnter >= tExit) return null;
    }

    return .{ .t = tEnter, .point = s.at(tEnter), .normal = normal };
}

const Edge = struct { normal: Vec2F, dist: f32 };

/// The edge of `r` closest to `p` (which is inside `r`), with its outward
/// normal and how far `p` is from it.
fn nearestEdge(p: Vec2F, r: RectF) Edge {
    var best: Edge = .{ .normal = .{ .x = -1, .y = 0 }, .dist = p.x - r.l };
    const candidates = [_]Edge{
        .{ .normal = .{ .x = 1, .y = 0 }, .dist = r.r - p.x },
        .{ .normal = .{ .x = 0, .y = -1 }, .dist = p.y - r.t },
        .{ .normal = .{ .x = 0, .y = 1 }, .dist = r.b - p.y },
    };
    for (candidates) |e| {
        if (e.dist < best.dist) best = e;
    }
    return best;
}
