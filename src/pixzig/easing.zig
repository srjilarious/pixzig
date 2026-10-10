//! Easing curves for tweens. Each maps a progress `t` in [0, 1] to an eased
//! value that starts at 0 and ends at 1; `back` and `elastic` overshoot in
//! between. `_in` curves start slow, `_out` curves end slow, `_in_out`
//! do both.
//!
//! The formulas follow https://easings.net.

const std = @import("std");

pub const Ease = enum {
    linear,
    quad_in,
    quad_out,
    quad_in_out,
    cubic_in,
    cubic_out,
    cubic_in_out,
    sine_in,
    sine_out,
    sine_in_out,
    back_in,
    back_out,
    elastic_out,
    bounce_out,

    /// Applies the curve to `t`, which is clamped to [0, 1] first.
    pub fn apply(self: Ease, t: f32) f32 {
        const x = std.math.clamp(t, 0.0, 1.0);
        return switch (self) {
            .linear => x,
            .quad_in => x * x,
            .quad_out => 1 - (1 - x) * (1 - x),
            .quad_in_out => if (x < 0.5) 2 * x * x else 1 - std.math.pow(f32, -2 * x + 2, 2) / 2,
            .cubic_in => x * x * x,
            .cubic_out => 1 - std.math.pow(f32, 1 - x, 3),
            .cubic_in_out => if (x < 0.5) 4 * x * x * x else 1 - std.math.pow(f32, -2 * x + 2, 3) / 2,
            .sine_in => 1 - @cos(x * std.math.pi / 2),
            .sine_out => @sin(x * std.math.pi / 2),
            .sine_in_out => -(@cos(std.math.pi * x) - 1) / 2,
            .back_in => back_c3 * x * x * x - back_c1 * x * x,
            .back_out => 1 + back_c3 * std.math.pow(f32, x - 1, 3) + back_c1 * std.math.pow(f32, x - 1, 2),
            .elastic_out => elasticOut(x),
            .bounce_out => bounceOut(x),
        };
    }
};

/// How far `back_*` overshoots (about 10%).
const back_c1: f32 = 1.70158;
const back_c3: f32 = back_c1 + 1;

fn elasticOut(x: f32) f32 {
    if (x == 0 or x == 1) return x;
    const c4: f32 = (2 * std.math.pi) / 3.0;
    return std.math.pow(f32, 2, -10 * x) * @sin((x * 10 - 0.75) * c4) + 1;
}

fn bounceOut(x: f32) f32 {
    const n1: f32 = 7.5625;
    const d1: f32 = 2.75;
    if (x < 1 / d1) {
        return n1 * x * x;
    } else if (x < 2 / d1) {
        const y = x - 1.5 / d1;
        return n1 * y * y + 0.75;
    } else if (x < 2.5 / d1) {
        const y = x - 2.25 / d1;
        return n1 * y * y + 0.9375;
    } else {
        const y = x - 2.625 / d1;
        return n1 * y * y + 0.984375;
    }
}

/// Interpolates from `a` to `b` along `ease` at progress `t`.
pub fn tween(ease: Ease, a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * ease.apply(t);
}
