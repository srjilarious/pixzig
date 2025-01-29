// zig fmt: off

const std = @import("std");
const builtin = std.builtin;

const assets_dir = "assets/";

fn addArchIncludes(b: *std.Build, 
    target: std.Build.ResolvedTarget, 
    optimize: std.builtin.OptimizeMode, 
    dep: *std.Build.Step.Compile) !void
{
    _  = optimize;
    switch (target.result.os.tag) {
        .emscripten => {
            if (b.sysroot == null) {
                @panic("Pass '--sysroot \"~/.cache/emscripten/sysroot\"'");
            }

            // const cache_include = std.fs.path.join(b.allocator, &.{ "/home/jeffdw/.cache/emscripten/sysroot", "include" }) catch @panic("Out of memory");
            const cache_include = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "include" }) catch @panic("Out of memory");
            defer b.allocator.free(cache_include);

            var dir = std.fs.openDirAbsolute(cache_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch @panic("No emscripten cache. Generate it!");
            dir.close();
            dep.addIncludePath(.{ .cwd_relative = cache_include });
        },
        else => {}
    }
}

pub fn example(b: *std.Build, 
    target: std.Build.ResolvedTarget, 
    optimize: std.builtin.OptimizeMode, 
    name: []const u8, 
    root_src_path: []const u8) *std.Build.Step.Compile
{
    const exe = blk: {
        if(target.result.os.tag == .emscripten) {
            break :blk b.addStaticLibrary(.{
                .name = name,
                .root_source_file = b.path(root_src_path),
                .target = target,
                .optimize = optimize,
            });
        }
        else {
            break :blk b.addExecutable(.{
                .name = name,
                .root_source_file = b.path(root_src_path),
                .target = target,
                .optimize = optimize,
            });
        }
    };

    try addArchIncludes(b, target, optimize, exe);

    // Build it
    const zglfw = b.dependency("zglfw", .{ .target = target });
    
    const zopengl = b.dependency("zopengl", .{ .target = target });

    const zflecs = b.dependency("zflecs", .{ .target = target });
    const flecs_dep = zflecs.artifact("flecs");
    try addArchIncludes(b, target, optimize, flecs_dep);

    const zstbi = b.dependency("zstbi", .{ .target = target });
    const stbi_dep = zstbi.artifact("zstbi");
    try addArchIncludes(b, target, optimize, stbi_dep);

    const zmath = b.dependency("zmath", .{ .target = target });
    
    const zgui = blk: {
        if(target.result.os.tag == .emscripten) {
            break :blk b.dependency("zgui", .{ 
                .target = target,
                .backend = .glfw, // emscripten
                // .shared = false,
                // .with_implot = true,
            });
        }
        else {
            break :blk b.dependency("zgui", .{ 
                .target = target,
                .backend = .glfw_opengl3,
                // .shared = false,
                // .with_implot = true,
            });
        }
    };

    const gui_dep = zgui.artifact("imgui");
    try addArchIncludes(b, target, optimize, gui_dep);

    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize
    });
    ziglua.module("ziglua").addIncludePath(.{.cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include"});
    // ziglua.module("ziglua-c").addIncludePath(.{.cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include"});

    const lua_dep = ziglua.artifact("lua");
    try addArchIncludes(b, target, optimize, lua_dep);

    exe.linkLibC();

    const pixeng = b.addModule("pixzig", .{
        .root_source_file = b.path("src/pixzig/pixzig.zig"),
    });

    if(target.result.os.tag != .emscripten) {
        const glfw_dep = zglfw.artifact("glfw");

        // Use mach-freetype
        // const freetype = b.dependency("freetype", .{ 
        //         .target = target, 
        //         .optimize = optimize, 
        //         .enable_brotli=false
        //     });
        // const freetype_dep = freetype.artifact("freetype");
        // try addArchIncludes(b, target, optimize, freetype_dep);

        // const mach_freetype = b.dependency("mach_freetype", .{
        //     .target = target,
        //     .optimize = optimize,
        //     .enable_brotli = false,
        // });
    
        // Link with your app
    
        exe.linkLibrary(flecs_dep);
        exe.linkLibrary(glfw_dep);
        exe.linkLibrary(lua_dep);
        exe.linkLibrary(gui_dep);
        exe.linkLibrary(stbi_dep);
        // exe.linkLibrary(freetype_dep);

        // const freetype_mod = mach_freetype.module("mach-freetype");
        // exe.root_module.addImport("freetype",freetype_mod);
        // pixeng.addImport("freetype", freetype_mod);
    }


    // Use GLFW for GL context, windowing, input, etc.
    const zglfw_mod = zglfw.module("root");
    pixeng.addImport("zglfw", zglfw_mod);
    exe.root_module.addImport("zglfw", zglfw_mod);
    
    // OpenGL
    const gl_mod = zopengl.module("root");
    exe.root_module.addImport("zopengl", gl_mod);
    pixeng.addImport("zopengl", gl_mod);
    
    // // GUI support
    const zgui_mod = zgui.module("root");
    exe.root_module.addImport("zgui",zgui_mod );
    pixeng.addImport("zgui", zgui_mod);
    // std.debug.print("zgui mod has {} include dirs.\n", .{zgui_mod.include_dirs.items.len});
    
    // // STBI for image loading.
    const zstbi_mod = zstbi.module("root");
    pixeng.addImport("zstbi", zstbi_mod);
    
    // // Math library
    const math_mod = zmath.module("root");
    pixeng.addImport("zmath", math_mod);
    exe.root_module.addImport("zmath", math_mod);
    
    // // ECS library.
    const zflecs_mod = zflecs.module("root");
    exe.root_module.addImport("zflecs", zflecs_mod);
    pixeng.addImport("zflecs", zflecs_mod);

    //  // XML for tilemap loading.
    const xml = b.addModule("xml", .{ .root_source_file = b.path("libs/xml.zig")});
    pixeng.addImport("xml", xml);
    
    

    // add the ziglua module and lua artifact
    const ziglua_mod = ziglua.module("ziglua");
    exe.root_module.addImport("ziglua", ziglua_mod);
    pixeng.addImport("ziglua", ziglua.module("ziglua"));

    exe.root_module.addImport("pixzig", pixeng);

    std.debug.print("Steps: {}\n", .{exe.step.dependencies.items.len});
    for(exe.step.dependencies.items, 0..) |step, idx| {
        std.debug.print("Step {}: {s}\n", .{idx, step.name});
    }
        
    const install_content_step = b.addInstallDirectory(.{
        .source_dir = b.path(assets_dir),
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


    // const emcc_exe = switch (builtin.os.tag) { // TODO bundle emcc as a build dependency
    //     .windows => "emcc.bat",
    //     else => "emcc",
    // };

    switch (target.result.os.tag) {
        .emscripten => {
            const emcc_exe_path = "/usr/lib/emscripten/emcc";
            const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});
            emcc_command.addArgs(&[_][]const u8{
                "-o",
                "zig-out/web/index.html",
                "-sFULL-ES3=1",
                "-sUSE_GLFW=3",
                "-O3",

                // "-sAUDIO_WORKLET=1",
                // "-sWASM_WORKERS=1",

                "-sASYNCIFY",
                // TODO currently deactivated because it seems as if it doesn't work with local hosting debug workflow
                // "-pthread",
                // "-sPTHREAD_POOL_SIZE=4",

                "-sMIN_WEBGL_VERSION=2",
                "-sINITIAL_MEMORY=167772160",
                "-sALLOW_MEMORY_GROWTH=1",
                "-sMALLOC=emmalloc",
                "--export=_mainLoop",
                "-sEXPORTED_FUNCTIONS=_mainLoop,_main",
                //"-sEXPORTED_FUNCTIONS=_main,__builtin_return_address",

                // USE_OFFSET_CONVERTER required for @returnAddress used in
                // std.mem.Allocator interface
                "-sUSE_OFFSET_CONVERTER",
                "-sERROR_ON_UNDEFINED_SYMBOLS=0",

                // Test embedding some graphics
                "--preload-file", "assets/mario_grassish2.png",
                // "--preload-file assets/digcraft_sprites.png",
                // "--embed-file assets/digcraft_sprites.json",
                "--preload-file", "assets/digconf.lua",
                "--preload-file", "assets/level1a.tmx",

                "--shell-file",
                b.path("src/shell.html").getPath(b),
            });

            const link_items: []const *std.Build.Step.Compile = &.{
                stbi_dep,
                gui_dep,
                //freetype_dep,
                flecs_dep,
                exe,
            };
            for (link_items) |item| {
                emcc_command.addFileArg(item.getEmittedBin());
                emcc_command.step.dependOn(&item.step);
            }

            const install = emcc_command;
            b.default_step.dependOn(&install.step);
        },
        else => {}
    }

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


    _ = example(b, target, optimize, "grid_render", "examples/grid_render.zig");
    if(target.result.os.tag != .emscripten) {
        _ = example(b, target, optimize, "actor_test", "examples/actor_test.zig");
        _ = example(b, target, optimize, "collision_test", "examples/collision_test.zig");
        _ = example(b, target, optimize, "create_texture", "examples/create_texture.zig");
        _ = example(b, target, optimize, "flecs_test", "examples/flecs_test.zig");
        _ = example(b, target, optimize, "game_state_test", "examples/game_state_test.zig");
        _ = example(b, target, optimize, "glfw_sprites", "examples/glfw_sprites.zig");
        _ = example(b, target, optimize, "mouse_test", "examples/mouse_test.zig");
        _ = example(b, target, optimize, "tile_load_test", "examples/tile_load_test.zig");
        // _ = example(b, target, optimize, "gameloop_test", "examples/gameloop_test.zig");
        // _ = example(b, target, optimize, "a_star_path", "examples/a_star_path.zig");
        // _ = example(b, target, optimize, "console_test", "examples/console_test.zig");
        // _ = example(b, target, optimize, "lua_test", "examples/lua_test.zig");
    //     _ = example(b, target, optimize, "text_rendering", "examples/text_rendering.zig");

        // _ = example(b, target, optimize, "natetris", "games/natetris/natetris.zig");
        // _ = example(b, target, optimize, "digcraft", "games/digcraft/digcraft.zig");

        // const spack = example(b, target, optimize, "spack", "tools/spack/spack.zig");
        // const zargs = b.dependency("zargunaught", .{});
        // spack.root_module.addImport("zargunaught", zargs.module("zargunaught"));

        // const zstbi = b.dependency("zstbi", .{ .target = target });
        // spack.root_module.addImport("zstbi", zstbi.module("root"));

    //     const tests = example(b, target, optimize, "tests", "tests/main.zig");
    //     const testzMod = b.dependency("testz", .{});
    //     tests.root_module.addImport("testz", testzMod.module("testz"));
    }
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
