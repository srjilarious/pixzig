// zig fmt: off

const std = @import("std");

// const zsdl = @import("libs/zig-gamedev/libs/zsdl/build.zig");
// const zflecs = @import("libs/zig-gamedev/libs/zflecs/build.zig");
// const zglfw = @import("libs/zig-gamedev/libs/zglfw/build.zig");
// const zopengl = @import("libs/zig-gamedev/libs/zopengl/build.zig");
// const zstbi = @import("libs/zig-gamedev/libs/zstbi/build.zig");
// const zmath = @import("libs/zig-gamedev/libs/zmath/build.zig");
// const zgui = @import("libs/zig-gamedev/libs/zgui/build.zig");
// const system_sdk = @import("libs/zig-gamedev/libs/system-sdk/build.zig");

const assets_dir = "assets/";

pub fn example(b: *std.Build, 
    target: std.Build.ResolvedTarget, 
    optimize: std.builtin.OptimizeMode, 
    name: []const u8, 
    root_src_path: []const u8) *std.Build.Step.Compile
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
    // const system_sdk_pkg = system_sdk.package(b, target, optimize, .{});
    const zglfw = b.dependency("zglfw", .{ .target = target });
    const zflecs = b.dependency("zflecs", .{ .target = target });
    const zopengl = b.dependency("zopengl", .{ .target = target });
    const zstbi = b.dependency("zstbi", .{ .target = target });
    const zmath = b.dependency("zmath", .{ .target = target });
    const zgui = b.dependency("zgui", .{ 
        .target = target,
        .backend = .glfw_opengl3,
        // .shared = false,
        // .with_implot = true,
    });

    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
    });

    // Use mach-freetype
    const mach_freetype_dep = b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    });

    // Link with your app
    exe.linkLibrary(zflecs.artifact("flecs"));
    exe.linkLibrary(zglfw.artifact("glfw"));
    exe.linkLibrary(zgui.artifact("imgui"));
    exe.linkLibrary(zstbi.artifact("zstbi"));
    
    const xml = b.addModule("xml", .{ .root_source_file = .{ .path = "libs/xml.zig" } });

    const pixeng = b.addModule("pixzig", .{
        // Package root
        .root_source_file = .{ .path = "src/pixzig/pixzig.zig" },
        // .dependencies = &.{
        // },
    });
    // pixeng.addImport("system-sdk", system_sdk_pkg.system_sdk);
    
    // Use GLFW for GL context, windowing, input, etc.
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    pixeng.addImport("zglfw", zglfw.module("root"));
    
    // OpenGL
    exe.root_module.addImport("zopengl", zopengl.module("root"));
    pixeng.addImport("zopengl", zopengl.module("root"));
    
    // GUI support
    exe.root_module.addImport("zgui", zgui.module("root"));
    pixeng.addImport("zgui", zgui.module("root"));
    
    // STBI for image loading.
    pixeng.addImport("zstbi", zstbi.module("root"));
    
    // Math library
    exe.root_module.addImport("zmath", zmath.module("root"));
    pixeng.addImport("zmath", zmath.module("root"));
    
    // ECS library.
    exe.root_module.addImport("zflecs", zflecs.module("root"));
    pixeng.addImport("zflecs", zflecs.module("root"));
    
    // XML for tilemap loading.
    pixeng.addImport("xml", xml);
    
    exe.root_module.addImport("ziglua", ziglua.module("ziglua"));
    pixeng.addImport("ziglua", ziglua.module("ziglua"));

    pixeng.addImport("freetype", mach_freetype_dep.module("mach-freetype"));
    exe.root_module.addImport("freetype", mach_freetype_dep.module("mach-freetype"));

    // add the ziglua module and lua artifact
    exe.root_module.addImport("ziglua", ziglua.module("ziglua"));
    // exe.linkLibrary(ziglua.artifact("lua"));

    exe.root_module.addImport("pixzig", pixeng);
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

    _ = example(b, target, optimize, "actor_test", "examples/actor_test.zig");
    _ = example(b, target, optimize, "create_texture", "examples/create_texture.zig");
    _ = example(b, target, optimize, "tile_load_test", "examples/tile_load_test.zig");
    _ = example(b, target, optimize, "flecs_test", "examples/flecs_test.zig");
    _ = example(b, target, optimize, "game_state_test", "examples/game_state_test.zig");
    _ = example(b, target, optimize, "glfw_test", "examples/glfw_test.zig");
    _ = example(b, target, optimize, "glfw_sprites", "examples/glfw_sprites.zig");
    _ = example(b, target, optimize, "lua_test", "examples/lua_test.zig");
    _ = example(b, target, optimize, "gameloop_test", "examples/gameloop_test.zig");
    _ = example(b, target, optimize, "mouse_test", "examples/mouse_test.zig");
     _ = example(b, target, optimize, "text_rendering", "examples/text_rendering.zig");

    // const tests = example(b, target, optimize, "unit_tests", "tests/main.zig");
    // const testzMod = b.dependency("testz", .{});
    // tests.root_module.addImport("testz", testzMod.module("testz"));
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
