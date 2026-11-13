const std = @import("std");
const pixzig_build = @import("pixzig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pixzig_dep = b.dependency("pixzig", .{ .target = target, .build_examples = false });

    // Every file the game loads, by id. The "boot" group is loaded before
    // App.init runs (see `.manifestOpts` in src/main.zig). Paths are
    // relative to assets/. Add a level by adding its .tmx here and to
    // `levels` in src/play.zig.
    const manifest = pixzig_build.manifestFromDef(b, .{
        .groups = &.{.{ .name = "boot", .assets = &.{ "hopper", "level1", "tuning" } }},
        .assets = &.{
            .{ .id = "hopper", .kind = "texture", .path = "hopper.png" },
            .{ .id = "level1", .kind = "tilemap", .path = "level1.tmx" },
            .{ .id = "tuning", .kind = "raw", .path = "tuning.json" },
        },
    });

    // Builds and installs zig-out/bin/hopper/hopper, and adds a
    // `zig build hopper` step that runs it. `-Dpackage=true` copies assets/
    // next to the executable.
    _ = pixzig_build.buildGame(b, .{
        .target = target,
        .optimize = optimize,
        .engine_dep = pixzig_dep,
        .name = "hopper",
        .root_source_file = b.path("src/main.zig"),
        .manifest = manifest,
    });
}
