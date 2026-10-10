const std = @import("std");
const pixzig_build = @import("pixzig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pixzig_dep = b.dependency("pixzig", .{ .target = target, .build_examples = false });

    // No assets yet. List textures, atlases, fonts and the like here (see
    // pixzig's docs/assets.md) and they are loaded at startup, and copied
    // next to the executable by `zig build -Dpackage=true`.
    const manifest = pixzig_build.manifestFromDef(b, .{});

    // Builds and installs zig-out/bin/my_game/my_game, and adds a
    // `zig build my_game` step that runs it.
    _ = pixzig_build.buildGame(b, .{
        .target = target,
        .optimize = optimize,
        .engine_dep = pixzig_dep,
        .name = "my_game",
        .root_source_file = b.path("src/main.zig"),
        .manifest = manifest,
    });
}
