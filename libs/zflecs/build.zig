const std = @import("std");
const builtin = @import("builtin");
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const opt_use_shared = b.option(bool, "shared", "Make shared (default: false)") orelse false;
    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/zflecs.zig"),
        .target = target,
        .optimize = optimize,
    });

    const flecs = if (opt_use_shared) b.addLibrary(.{
        .name = "flecs",
        .linkage = .dynamic,
        .root_module = mod,
    }) else b.addLibrary(.{
        .name = "flecs",
        .linkage = .static,
        .root_module = mod,
    });
    flecs.linkLibC();
    flecs.addIncludePath(b.path("libs/flecs"));
    flecs.addCSourceFile(.{
        .file = b.path("libs/flecs/flecs.c"),
        .flags = &.{
            "-fno-sanitize=undefined",
            "-DFLECS_NO_CPP",
            "-DFLECS_USE_OS_ALLOC",
            if (builtin.mode == .Debug) "-DFLECS_SANITIZE" else "",
            if (opt_use_shared) "-DFLECS_SHARED" else "",
        },
    });
    b.installArtifact(flecs);

    if (target.result.os.tag == .windows) {
        flecs.linkSystemLibrary("ws2_32");
    }
    const test_step = b.step("test", "Run zflecs tests");

    const tests = b.addTest(.{
        .name = "zflecs-tests",
        .root_module = b.addModule("tests", .{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.linkLibC();
    tests.addIncludePath(b.path("libs/flecs"));
    b.installArtifact(tests);

    tests.linkLibrary(flecs);

    test_step.dependOn(&b.addRunArtifact(tests).step);
}
