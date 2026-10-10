//! A seeded random number source with the helpers games reach for.
//!
//! The engine owns one as `eng.rng`, seeded from
//! `EngineInitOptions.rngSeed`. Drawing all gameplay randomness from that
//! one seeded source is what makes a run reproducible: the same seed and
//! the same inputs give the same game, which is what replays, bug repros
//! and lockstep networking rely on.

const std = @import("std");
const common = @import("./common.zig");

const Vec2F = common.Vec2F;

pub const Rng = struct {
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) Rng {
        return .{ .prng = std.Random.DefaultPrng.init(seed) };
    }

    /// Restarts the sequence from `seed`.
    pub fn reseed(self: *Rng, seed: u64) void {
        self.prng = std.Random.DefaultPrng.init(seed);
    }

    /// The `std.Random` interface over this source, for the std helpers
    /// not wrapped here (`shuffle`, `weightedIndex`, ...).
    pub fn random(self: *Rng) std.Random {
        return self.prng.random();
    }

    /// A float in [0, 1).
    pub fn float(self: *Rng) f32 {
        return self.random().float(f32);
    }

    /// A float in [min, max).
    pub fn floatRange(self: *Rng, min: f32, max: f32) f32 {
        return min + (max - min) * self.float();
    }

    /// An integer in [min, max], both ends included.
    pub fn intRange(self: *Rng, comptime T: type, min: T, max: T) T {
        return self.random().intRangeAtMost(T, min, max);
    }

    /// True with probability `p` (0 never, 1 always).
    pub fn chance(self: *Rng, p: f32) bool {
        return self.float() < p;
    }

    /// A uniformly chosen element of `items`, or null when it's empty.
    pub fn pick(self: *Rng, comptime T: type, items: []const T) ?T {
        if (items.len == 0) return null;
        return items[self.random().uintLessThan(usize, items.len)];
    }

    /// A unit vector pointing in a uniformly random direction.
    pub fn direction(self: *Rng) Vec2F {
        return Vec2F.fromAngle(self.floatRange(0, 2.0 * std.math.pi));
    }
};
