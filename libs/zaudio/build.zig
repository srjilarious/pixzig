const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("root", .{
        .root_source_file = b.path("src/zaudio.zig"),
    });

    const miniaudio = b.addModule("miniaudio", .{
        .target = target,
        .optimize = optimize,
    });

    const miniaudio_lib = b.addLibrary(.{
        .name = "miniaudio",
        .root_module = miniaudio,
        .linkage = .static,
    });

    b.installArtifact(miniaudio_lib);

    miniaudio.addIncludePath(b.path("libs/miniaudio"));
    miniaudio_lib.root_module.link_libc = true;

    if (target.result.os.tag == .macos) {
        if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
            miniaudio_lib.root_module.addFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
            miniaudio_lib.root_module.addSystemIncludePath(system_sdk.path("macos12/usr/include"));
            miniaudio_lib.root_module.addLibraryPath(system_sdk.path("macos12/usr/lib"));
        }
        miniaudio_lib.root_module.linkFramework("CoreAudio", .{});
        miniaudio_lib.root_module.linkFramework("CoreFoundation", .{});
        miniaudio_lib.root_module.linkFramework("AudioUnit", .{});
        miniaudio_lib.root_module.linkFramework("AudioToolbox", .{});
    } else if (target.result.os.tag == .linux) {
        miniaudio_lib.root_module.linkSystemLibrary("pthread", .{});
        miniaudio_lib.root_module.linkSystemLibrary("m", .{});
        miniaudio_lib.root_module.linkSystemLibrary("dl", .{});
    }

    const is_emscripten = target.result.os.tag == .emscripten;

    miniaudio.addCSourceFile(.{
        .file = b.path("src/zaudio.c"),
        .flags = &.{
            if (is_emscripten) "" else "-std=c99",
            "-fno-sanitize=undefined",
        },
    });
    miniaudio.addCSourceFile(.{
        .file = b.path("libs/miniaudio/miniaudio.c"),
        .flags = &.{
            // "-DMA_NO_WEBAUDIO",
            "-DMA_NO_NULL",
            "-DMA_NO_JACK",
            "-DMA_NO_DSOUND",
            "-DMA_NO_WINMM",
            "-fno-sanitize=undefined",
            if (is_emscripten) "" else "-std=c99",
            // if (is_emscripten) "-DMA_ENABLE_AUDIO_WORKLETS" else "",
            if (target.result.os.tag == .macos) "-DMA_NO_RUNTIME_LINKING" else "",
        },
    });

    // PIXZIG addition for emscripten
    // Need to figure out how to access TranslateC step from top-level build.zig.
    switch (target.result.os.tag) {
        .emscripten => {
            if (b.sysroot == null) {
                @panic("Pass '--sysroot \"~/.cache/emscripten/sysroot\"'");
            }

            const cache_include = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "include" }) catch @panic("Out of memory");
            defer b.allocator.free(cache_include);

            // TODO: Add this check back in.
            // var dir = std.fs.openDirAbsolute(cache_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch @panic("No emscripten cache. Generate it!");
            // dir.close();
            //lib.addIncludePath(.{ .cwd_relative = cache_include });
            miniaudio.addIncludePath(.{ .cwd_relative = cache_include });
        },
        else => {},
    }
    // END PIXZIG

    const test_step = b.step("test", "Run zaudio tests");

    const test_module = b.addModule("test", .{
        .root_source_file = b.path("src/zaudio.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .name = "zaudio-tests",
        .root_module = test_module,
    });
    b.installArtifact(tests);

    tests.root_module.linkLibrary(miniaudio_lib);

    test_step.dependOn(&b.addRunArtifact(tests).step);
}
