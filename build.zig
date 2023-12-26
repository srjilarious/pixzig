// zig fmt: off

const std = @import("std");

const zsdl = @import("libs/zig-gamedev/libs/zsdl/build.zig");
const zglfw = @import("libs/zig-gamedev/libs/zglfw/build.zig");
const zopengl = @import("libs/zig-gamedev/libs/zopengl/build.zig");
const zstbi = @import("libs/zig-gamedev/libs/zstbi/build.zig");
const zmath = @import("libs/zig-gamedev/libs/zmath/build.zig");
const zgui = @import("libs/zig-gamedev/libs/zgui/build.zig");

const assets_dir = "assets/";

pub fn example(b: *std.Build, 
    target: std.zig.CrossTarget, 
    optimize: std.builtin.OptimizeMode, 
    name: []const u8, 
    root_src_path: []const u8) *std.Build.CompileStep 
{
    const exe = b.addExecutable(.{
        .name = name, //"pixzig_test",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = root_src_path }, //"src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Build it
    const zsdl_pkg = zsdl.package(b, target, optimize, .{});
    const zglfw_pkg = zglfw.package(b, target, optimize, .{});
    const zopengl_pkg = zopengl.package(b, target, optimize, .{});
    const zstbi_pkg = zstbi.package(b, target, optimize, .{});
    const zmath_pkg = zmath.package(b, target, optimize, .{});
    const zgui_pkg = zgui.package(b, target, optimize, .{ .options = .{ .backend = . glfw_opengl3}});

    // Link with your app
    zsdl_pkg.link(exe);
    zglfw_pkg.link(exe);
    zopengl_pkg.link(exe);
    zstbi_pkg.link(exe);
    zmath_pkg.link(exe);
    zgui_pkg.link(exe);

    const xml = b.addModule("xml", .{ .source_file = .{ .path = "libs/xml.zig" } });

    const pixeng = b.addModule("pixzig", .{
        // Package root
        .source_file = .{ .path = "src/pixzig/pixzig.zig" },
        .dependencies = &.{
            // Uses SDL for graphics/audio/input
            .{ .name = "zsdl", .module = zsdl_pkg.zsdl },
            // Transitioning to GLFW for more graphics control.
            .{ .name = "zglfw", .module = zglfw_pkg.zglfw },
            // OpenGL
            .{ .name = "zopengl", .module = zopengl_pkg.zopengl },
            // GUI support
            .{ .name = "zgui", .module = zgui_pkg.zgui },
            // STBI for image loading.
            .{ .name = "zstbi", .module = zstbi_pkg.zstbi },
            // Math library
            .{ .name = "zmath", .module = zmath_pkg.zmath },
            // XML for tilemap loading.
            .{ .name = "xml", .module = xml },
        },
    });

    exe.addModule("pixzig", pixeng);
    // zsdl_pkg.link(pixzig);
    // zopengl_pkg.link(pixzig);
    // zstbi_pkg.link(pixzig);

    // exe.linkLibrary(pixzig);

    const install_content_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/" ++ assets_dir },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ assets_dir,
    });
    exe.step.dependOn(&install_content_step.step);

    // ** Wait for package management to be a bit more mature.
    // const zig_gamedev = b.dependency("zig_gamedev", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // // duck has exported itself as duck
    // // now you are re-exporting duck
    // // as a module in your project with the name duck
    // exe.addModule("zig_gamedev", zig_gamedev.module("zig_gamedev"));
    //
    // // you need to link to the output of the build process
    // // that was done by the duck package
    // // in this case, duck is outputting a library
    // // to which your project need to link as well
    // exe.linkLibrary(zig_gamedev.artifact("zig_gamedev"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step(name, "Run example");
    run_step.dependOn(&run_cmd.step);
    return exe;
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    //_ = example(b, target, optimize, "actor_test", "examples/actor_test.zig");
    _ = example(b, target, optimize, "tile_load_test", "examples/tile_load_test.zig");
    _ = example(b, target, optimize, "glfw_test", "examples/glfw_test.zig");
    _ = example(b, target, optimize, "glfw_sprites", "examples/glfw_sprites.zig");

    const tests = example(b, target, optimize, "unit_tests", "tests/main.zig");
    const testzMod = b.dependency("testz", .{});
    tests.addModule("testz", testzMod.module("testz"));

    // // Creates a step for unit testing. This only builds the test executable
    // // but does not run it.
    // const unit_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    //
    // const run_unit_tests = b.addRunArtifact(unit_tests);
    //
    // // Similar to creating the run step earlier, this exposes a `test` step to
    // // the `zig build --help` menu, providing a way for the user to request
    // // running the unit tests.
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_unit_tests.step);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
