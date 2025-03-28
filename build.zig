const std = @import("std");
const builtin = std.builtin;

const assets_dir = "assets";

fn addArchIncludes(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, dep: *std.Build.Step.Compile) !void {
    _ = optimize;
    switch (target.result.os.tag) {
        .emscripten => {
            if (b.sysroot == null) {
                @panic("Pass '--sysroot \"~/.cache/emscripten/sysroot\"'");
            }

            // const cache_include = std.fs.path.join(b.allocator, &.{ "/home/jeffdw/.cache/emscripten/sysroot", "include" }) catch @panic("Out of memory");
            const cache_include = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "include" }) catch @panic("Out of memory");
            defer b.allocator.free(cache_include);

            var dir = std.fs.openDirAbsolute(cache_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch {
                @panic("No emscripten cache. Generate it!");
            };

            dir.close();
            dep.addIncludePath(.{ .cwd_relative = cache_include });
        },
        else => {},
    }
}

// pub const AppMod = struct {
//     name: []const u8,
//     module: *std.Build.Module,
// };

// pub const EngData = struct {
//     eng: *std.Build.Module,
//     mods: std.ArrayList(AppMod),
//     deps: std.ArrayList(*std.Build.Step.Compile),
// };

// pub fn engine(
//     b: *std.Build,
//     target: std.Build.ResolvedTarget,
//     optimize: std.builtin.OptimizeMode,
// ) !EngData {
//     const pixeng = b.addModule("pixzig", .{
//         .root_source_file = b.path("src/pixzig/pixzig.zig"),
//         .target = target,
//         .optimize = optimize,
//     });

//     // Create the engine library artifact
//     const engineLib = b.addStaticLibrary(.{
//         .name = "pixzig",
//         .root_module = pixeng,
//     });
//     engineLib.linkLibC();

//     var engData = EngData{
//         .eng = pixeng,
//         .mods = std.ArrayList(AppMod).init(b.allocator),
//         .deps = std.ArrayList(*std.Build.Step.Compile).init(b.allocator),
//     };

//     engData.eng = pixeng;

//     // GLFW.
//     const zglfw = b.dependency("zglfw", .{ .target = target });
//     const zglfw_mod = zglfw.module("root");
//     try engData.mods.append(.{ .name = "zglfw", .module = zglfw_mod });
//     if (target.result.os.tag != .emscripten) {
//         const glfw_dep = zglfw.artifact("glfw");
//         try engData.deps.append(glfw_dep);
//     }

//     // OpenGL bindings.
//     const zopengl = b.dependency("zopengl", .{ .target = target });
//     const gl_mod = zopengl.module("root");
//     try engData.mods.append(.{ .name = "zopengl", .module = gl_mod });

//     // Flecs
//     const zflecs = b.dependency("zflecs", .{ .target = target });
//     const zflecs_mod = zflecs.module("root");
//     try engData.mods.append(.{ .name = "zflecs", .module = zflecs_mod });

//     const flecs_dep = zflecs.artifact("flecs");
//     b.installArtifact(flecs_dep);
//     try addArchIncludes(b, target, optimize, flecs_dep);
//     try engData.deps.append(flecs_dep);

//     // Stbi
//     const zstbi = b.dependency("zstbi", .{ .target = target });
//     const zstbi_mod = zstbi.module("root");
//     try engData.mods.append(.{ .name = "zstbi", .module = zstbi_mod });

//     const stbi_dep = zstbi.artifact("zstbi");
//     try addArchIncludes(b, target, optimize, stbi_dep);
//     try engData.deps.append(stbi_dep);

//     // Math
//     const zmath = b.dependency("zmath", .{ .target = target });
//     const math_mod = zmath.module("root");
//     try engData.mods.append(.{ .name = "zmath", .module = math_mod });

//     const zgui = b.dependency("zgui", .{
//         .target = target,
//         .backend = .glfw_opengl3,
//         // .shared = false,
//         // .with_implot = true,
//     });
//     const zgui_mod = zgui.module("root");
//     try engData.mods.append(.{ .name = "zgui", .module = zgui_mod });

//     const gui_dep = zgui.artifact("imgui");
//     try addArchIncludes(b, target, optimize, gui_dep);
//     try engData.deps.append(gui_dep);

//     // Lua
//     const ziglua = b.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
//     ziglua.module("ziglua").addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
//     ziglua.module("ziglua-c").addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
//     const ziglua_mod = ziglua.module("ziglua");
//     const ziglua_c_mod = ziglua.module("ziglua-c");

//     const lua_dep = ziglua.artifact("lua");
//     try addArchIncludes(b, target, optimize, lua_dep);
//     try engData.mods.append(.{ .name = "ziglua", .module = ziglua_mod });
//     try engData.mods.append(.{ .name = "ziglua-c", .module = ziglua_c_mod });
//     try engData.deps.append(lua_dep);

//     if (target.result.os.tag != .emscripten) {

//         // Use mach-freetype
//         // const freetype = b.dependency("freetype", .{
//         //         .target = target,
//         //         .optimize = optimize,
//         //         .enable_brotli=false
//         //     });
//         // const freetype_dep = freetype.artifact("freetype");
//         // try addArchIncludes(b, target, optimize, freetype_dep);

//         // const mach_freetype = b.dependency("mach_freetype", .{
//         //     .target = target,
//         //     .optimize = optimize,
//         //     .enable_brotli = false,
//         // });

//         // exe.linkLibrary(freetype_dep);

//         // const freetype_mod = mach_freetype.module("mach-freetype");
//         // exe.root_module.addImport("freetype",freetype_mod);
//         // pixeng.addImport("freetype", freetype_mod);
//     }

//     // XML for tilemap loading.
//     const xml = b.addModule("xml", .{ .root_source_file = b.path("libs/xml.zig") });
//     pixeng.addImport("xml", xml);

//     // Add all of our inputs as modules to the engine.
//     for (engData.mods.items) |modData| {
//         pixeng.addImport(modData.name, modData.module);
//     }

//     return engData;
// }

// // Each example links in multiple different libraries, so this function sets that up for each one.
// pub fn example(
//     b: *std.Build,
//     target: std.Build.ResolvedTarget,
//     optimize: std.builtin.OptimizeMode,
//     engData: *const EngData,
//     name: []const u8,
//     root_src_path: []const u8,
//     assets: []const []const u8,
// ) *std.Build.Step.Compile {
//     const exe = blk: {
//         if (target.result.os.tag == .emscripten) {
//             break :blk b.addStaticLibrary(.{
//                 .name = name,
//                 .root_source_file = b.path(root_src_path),
//                 .target = target,
//                 .optimize = optimize,
//             });
//         } else {
//             break :blk b.addExecutable(.{
//                 .name = name,
//                 .root_source_file = b.path(root_src_path),
//                 .target = target,
//                 .optimize = optimize,
//             });
//         }
//     };

//     try addArchIncludes(b, target, optimize, exe);

//     exe.root_module.addImport("pixzig", engData.eng);
//     exe.linkLibC();

//     // Add dependencies from engine to exe too, so it can also import libs like zmath, zopengl, etc.
//     for (engData.mods.items) |item| {
//         exe.root_module.addImport(item.name, item.module);
//     }

//     // const emcc_exe = switch (builtin.os.tag) { // TODO bundle emcc as a build dependency
//     //     .windows => "emcc.bat",
//     //     else => "emcc",
//     // };

//     switch (target.result.os.tag) {
//         .emscripten => {
//             const path = b.pathJoin(&.{ b.install_prefix, "web", name });
//             std.debug.print("Installing to: {s}\n", .{path});

//             const index_path = b.pathJoin(&.{ path, "index.html" });

//             const mkdir_command = b.addSystemCommand(&[_][]const u8{"mkdir"});
//             mkdir_command.addArgs(&.{ "-p", path });

//             const emcc_exe_path = "/usr/lib/emscripten/em++";
//             const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});

//             // We need our web subdirectory to exist for em++ to be able to run.
//             emcc_command.step.dependOn(&mkdir_command.step);
//             emcc_command.addArgs(&[_][]const u8{
//                 "-o",
//                 index_path,
//                 "-sFULL-ES3=1",
//                 "-sUSE_GLFW=3",
//                 "-O3",
//                 "-g",

//                 // "-sAUDIO_WORKLET=1",
//                 // "-sWASM_WORKERS=1",

//                 "-sASYNCIFY",
//                 // TODO currently deactivated because it seems as if it doesn't work with local hosting debug workflow
//                 // "-pthread",
//                 // "-sPTHREAD_POOL_SIZE=4",

//                 "-sMIN_WEBGL_VERSION=2",
//                 // "-DIMGUI_IMPL_OPENGL_ES3=1",
//                 "-sINITIAL_MEMORY=167772160",
//                 "-sALLOW_MEMORY_GROWTH=1",
//                 "-sMALLOC=emmalloc",

//                 // USE_OFFSET_CONVERTER required for @returnAddress used in
//                 // std.mem.Allocator interface
//                 "-sUSE_OFFSET_CONVERTER",
//                 "-sSUPPORT_LONGJMP=1",
//                 "-sERROR_ON_UNDEFINED_SYMBOLS=1",
//                 "-sSTACK_SIZE=2mb",

//                 "--shell-file",
//                 b.path("src/shell.html").getPath(b),
//             });

//             // Add all of the specified assets.
//             for (assets) |asset| {
//                 emcc_command.addArgs(&[_][]const u8{ "--preload-file", b.pathJoin(&.{ assets_dir, asset }) });
//             }

//             for (engData.deps.items) |item| {
//                 emcc_command.addFileArg(item.getEmittedBin());
//                 emcc_command.step.dependOn(&item.step);
//             }

//             emcc_command.addFileArg(exe.getEmittedBin());
//             emcc_command.step.dependOn(&exe.step);

//             const install = emcc_command;
//             b.default_step.dependOn(&install.step);
//         },
//         else => {
//             // Link against dependent artifacts
//             // for (engData.deps.items) |dep| {
//             //     exe.linkLibrary(dep);
//             // }

//             const path = b.pathJoin(&.{ "bin", name });

//             const install_content_step = b.addInstallDirectory(.{
//                 .source_dir = b.path(assets_dir),
//                 .install_dir = .{ .custom = path },
//                 .install_subdir = "assets",
//                 .include_extensions = assets,
//             });
//             exe.step.dependOn(&install_content_step.step);

//             //b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = path } } }).step);

//             // This *creates* a Run step in the build graph, to be executed when another
//             // step is evaluated that depends on it. The next line below will establish
//             // such a dependency.
//             const run_cmd = b.addRunArtifact(exe);

//             run_cmd.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.install_prefix, path }) });

//             // By making the run step depend on the install step, it will be run from the
//             // installation directory rather than directly from within the cache directory.
//             // This is not necessary, however, if the application depends on other installed
//             // files, this ensures they will be present and in the expected location.
//             run_cmd.step.dependOn(b.getInstallStep());

//             // This allows the user to pass arguments to the application in the build
//             // command itself, like this: `zig build run -- arg1 arg2 etc`
//             if (b.args) |args| {
//                 run_cmd.addArgs(args);
//             }

//             // This creates a build step. It will be visible in the `zig build --help` menu,
//             // and can be selected like this: `zig build run`
//             // This will evaluate the `run` step rather than the default, which is "install".
//             const run_step = b.step(name, "Run example");
//             run_step.dependOn(&run_cmd.step);
//         },
//     }

//     return exe;
// }

// // Construct the build graph
// pub fn build(b: *std.Build) void {
//     // Standard target options allows the person running `zig build` to choose
//     // what target to build for. Here we do not override the defaults, which
//     // means any target is allowed, and the default is native. Other options
//     // for restricting supported target set are available.
//     const target = b.standardTargetOptions(.{});

//     // Standard optimization options allow the person running `zig build` to select
//     // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
//     // set a preferred release mode, allowing the user to decide how to optimize.
//     const optimize = b.standardOptimizeOption(.{});

//     const engData = engine(b, target, optimize) catch unreachable;

//     // Digcraft.
//     _ = example(
//         b,
//         target,
//         optimize,
//         &engData,
//         "digcraft",
//         "games/digcraft/digcraft.zig",
//         &.{
//             "digcraft_sprites.png",
//             "digcraft_sprites.json",
//             "digconf.lua",
//             "level1a.tmx",
//         },
//     );

//     // Tile map test.
//     _ = example(
//         b,
//         target,
//         optimize,
//         &engData,
//         "tile_load_test",
//         "examples/tile_load_test.zig",
//         &.{
//             "mario_grassish2.png",
//             "level1a.tmx",
//         },
//     );

//     _ = example(b, target, optimize, &engData, "natetris", "games/natetris/natetris.zig", &.{});

//     _ = example(b, target, optimize, &engData, "actor_test", "examples/actor_test.zig", &.{
//         "pac-tiles.png",
//     });

//     _ = example(b, target, optimize, &engData, "collision_test", "examples/collision_test.zig", &.{
//         "mario_grassish2.png",
//         "level1a.tmx",
//         "pac-tiles.png",
//     });
//     // _ = example(b, target, optimize, "create_texture", "examples/create_texture.zig", &.{});
//     _ = example(b, target, optimize, &engData, "flecs_test", "examples/flecs_test.zig", &.{
//         "mario_grassish2.png",
//     });
//     _ = example(b, target, optimize, &engData, "a_star_path", "examples/a_star_path.zig", &.{});
//     _ = example(b, target, optimize, &engData, "gameloop_test", "examples/gameloop_test.zig", &.{});
//     _ = example(b, target, optimize, &engData, "game_state_test", "examples/game_state_test.zig", &.{});
//     _ = example(b, target, optimize, &engData, "glfw_sprites", "examples/glfw_sprites.zig", &.{
//         "mario_grassish2.png",
//     });
//     _ = example(b, target, optimize, &engData, "grid_render", "examples/grid_render.zig", &.{});

//     // _ = example(b, target, optimize, "mouse_test", "examples/mouse_test.zig", &.{
//     //     "mario_grassish2.png",
//     // });

//     _ = example(b, target, optimize, &engData, "console_test", "examples/console_test.zig", &.{"Roboto-Medium.ttf"});

//     if (target.result.os.tag != .emscripten) {
//         // _ = example(b, target, optimize, "lua_test", "examples/lua_test.zig", &.{
//         //     "test.lua",
//         // });
//         // // _ = example(b, target, optimize, "a_star_path", "examples/a_star_path.zig");
//         //     _ = example(b, target, optimize, "text_rendering", "examples/text_rendering.zig");

//         // Sprite packer tool
//         const spack = example(b, target, optimize, &engData, "spack", "tools/spack/spack.zig", &.{});
//         const zargs = b.dependency("zargunaught", .{});
//         spack.root_module.addImport("zargunaught", zargs.module("zargunaught"));

//         const zstbi = b.dependency("zstbi", .{ .target = target });
//         spack.root_module.addImport("zstbi", zstbi.module("root"));

//         // Spritez - sprite editor tool
//         _ = example(b, target, optimize, &engData, "spritez", "tools/spritez/spritez.zig", &.{});

//         // Unit tests
//         const tests = example(b, target, optimize, &engData, "tests", "tests/main.zig", &.{});
//         const testzMod = b.dependency("testz", .{});
//         tests.root_module.addImport("testz", testzMod.module("testz"));
//     }
// }

// inline fn thisDir() []const u8 {
//     return comptime std.fs.path.dirname(@src().file) orelse ".";
// }

pub const EngineData = struct {
    engine_lib: *std.Build.Step.Compile,
    pixeng_mod: *std.Build.Module,
};
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the engine as a static library
    const engDat = buildEngine(b, target, optimize);

    // Define examples
    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        assets: []const []const u8,
    }{
        .{ .name = "digcraft", .path = "games/digcraft/digcraft.zig", .assets = &.{
            "digcraft_sprites.png",
            "digcraft_sprites.json",
            "digconf.lua",
            "level1a.tmx",
        } },
        .{ .name = "tile_load_test", .path = "examples/tile_load_test.zig", .assets = &.{
            "mario_grassish2.png",
            "level1a.tmx",
        } },
        .{ .name = "natetris", .path = "games/natetris/natetris.zig", .assets = &.{} },
        .{ .name = "actor_test", .path = "examples/actor_test.zig", .assets = &.{
            "pac-tiles.png",
        } },
        .{ .name = "collision_test", .path = "examples/collision_test.zig", .assets = &.{
            "mario_grassish2.png",
            "level1a.tmx",
            "pac-tiles.png",
        } },
        .{ .name = "flecs_test", .path = "examples/flecs_test.zig", .assets = &.{
            "mario_grassish2.png",
        } },
        .{ .name = "a_star_path", .path = "examples/a_star_path.zig", .assets = &.{} },
        .{ .name = "gameloop_test", .path = "examples/gameloop_test.zig", .assets = &.{} },
        .{ .name = "game_state_test", .path = "examples/game_state_test.zig", .assets = &.{} },
        .{ .name = "glfw_sprites", .path = "examples/glfw_sprites.zig", .assets = &.{
            "mario_grassish2.png",
        } },
        .{ .name = "grid_render", .path = "examples/grid_render.zig", .assets = &.{} },
        .{ .name = "console_test", .path = "examples/console_test.zig", .assets = &.{
            "Roboto-Medium.ttf",
        } },
    };

    // Create a "build-all" option that builds everything
    const build_all_step = b.step("build-all", "Build all examples");

    // Build each example
    for (examples) |example_info| {
        const exe = buildExample(b, target, optimize, engDat.engine_lib, engDat.pixeng_mod, example_info.name, example_info.path, example_info.assets);

        // Create a step for this specific example
        //const example_step = b.step(b.fmt("{s}_exe", .{example_info.name}), b.fmt("Build the {s} example", .{example_info.name}));

        // if (target.result.os.tag == .emscripten) {
        //     //example_step.dependOn(&exe.step);
        // } else {
        const install_exe = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = b.pathJoin(&.{ "bin", example_info.name }) } } });
        build_all_step.dependOn(&install_exe.step); //example_step);
        //example_step.dependOn(&install_exe.step);
        // }

        // Add to build-all step
    }

    if (target.result.os.tag != .emscripten) {
        // Sprite packer tool
        const spack = buildExample(b, target, optimize, engDat.engine_lib, engDat.pixeng_mod, "spack", "tools/spack/spack.zig", &.{});
        const zargs = b.dependency("zargunaught", .{});
        spack.root_module.addImport("zargunaught", zargs.module("zargunaught"));

        const zstbi = b.dependency("zstbi", .{ .target = target });
        spack.root_module.addImport("zstbi", zstbi.module("root"));

        // Unit tests
        const tests = buildExample(b, target, optimize, engDat.engine_lib, engDat.pixeng_mod, "tests", "tests/main.zig", &.{});
        const testzMod = b.dependency("testz", .{});
        tests.root_module.addImport("testz", testzMod.module("testz"));
    }

    // Make build-all the default step
    //b.default_step.dependOn(build_all_step);
}

fn buildEngine(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) EngineData {
    // Create the engine module
    const pixeng = b.addModule("pixzig", .{
        .root_source_file = b.path("src/pixzig/pixzig.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create the engine library
    const engine_lib = b.addStaticLibrary(.{
        .name = "pixzig",
        .root_module = pixeng,
    });
    engine_lib.linkLibC();

    // GLFW
    const zglfw = b.dependency("zglfw", .{ .target = target });
    const zglfw_mod = zglfw.module("root");
    pixeng.addImport("zglfw", zglfw_mod);

    if (target.result.os.tag != .emscripten) {
        const glfw_dep = zglfw.artifact("glfw");
        engine_lib.linkLibrary(glfw_dep);
    }

    // OpenGL bindings
    const zopengl = b.dependency("zopengl", .{ .target = target });
    const gl_mod = zopengl.module("root");
    pixeng.addImport("zopengl", gl_mod);

    // Flecs
    const zflecs = b.dependency("zflecs", .{ .target = target });
    const zflecs_mod = zflecs.module("root");
    pixeng.addImport("zflecs", zflecs_mod);

    const flecs_dep = zflecs.artifact("flecs");
    addArchIncludes(b, target, optimize, flecs_dep) catch unreachable;
    engine_lib.linkLibrary(flecs_dep);

    // Stbi
    const zstbi = b.dependency("zstbi", .{ .target = target });
    const zstbi_mod = zstbi.module("root");
    pixeng.addImport("zstbi", zstbi_mod);

    const stbi_dep = zstbi.artifact("zstbi");
    addArchIncludes(b, target, optimize, stbi_dep) catch unreachable;
    engine_lib.linkLibrary(stbi_dep);

    // Math
    const zmath = b.dependency("zmath", .{ .target = target });
    const math_mod = zmath.module("root");
    pixeng.addImport("zmath", math_mod);

    // GUI
    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .glfw_opengl3,
    });
    const zgui_mod = zgui.module("root");
    pixeng.addImport("zgui", zgui_mod);

    const gui_dep = zgui.artifact("imgui");
    addArchIncludes(b, target, optimize, gui_dep) catch unreachable;
    engine_lib.linkLibrary(gui_dep);

    // Lua
    const ziglua = b.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
    ziglua.module("ziglua").addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
    ziglua.module("ziglua-c").addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
    const ziglua_mod = ziglua.module("ziglua");
    const ziglua_c_mod = ziglua.module("ziglua-c");
    pixeng.addImport("ziglua", ziglua_mod);
    pixeng.addImport("ziglua-c", ziglua_c_mod);

    const lua_dep = ziglua.artifact("lua");
    addArchIncludes(b, target, optimize, lua_dep) catch unreachable;
    engine_lib.linkLibrary(lua_dep);

    // XML for tilemap loading
    const xml = b.addModule("xml", .{ .root_source_file = b.path("libs/xml.zig") });
    pixeng.addImport("xml", xml);

    // Install the engine library
    b.installArtifact(engine_lib);

    return .{ .engine_lib = engine_lib, .pixeng_mod = pixeng };
}

fn buildExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    engine_lib: *std.Build.Step.Compile,
    pixeng_mod: *std.Build.Module,
    name: []const u8,
    root_src_path: []const u8,
    assets: []const []const u8,
) *std.Build.Step.Compile {
    const exe = blk: {
        if (target.result.os.tag == .emscripten) {
            break :blk b.addStaticLibrary(.{
                .name = name,
                .root_source_file = b.path(root_src_path),
                .target = target,
                .optimize = optimize,
            });
        } else {
            break :blk b.addExecutable(.{
                .name = name,
                .root_source_file = b.path(root_src_path),
                .target = target,
                .optimize = optimize,
            });
        }
    };

    addArchIncludes(b, target, optimize, exe) catch unreachable;

    // Add the engine module
    exe.root_module.addImport("pixzig", pixeng_mod);
    exe.linkLibC();

    // Handle platform-specific linking
    switch (target.result.os.tag) {
        .emscripten => {
            const path = b.pathJoin(&.{ b.install_prefix, "web", name });
            std.debug.print("Installing to: {s}\n", .{path});

            const index_path = b.pathJoin(&.{ path, "index.html" });

            const mkdir_command = b.addSystemCommand(&[_][]const u8{"mkdir"});
            mkdir_command.addArgs(&.{ "-p", path });

            const emcc_exe_path = "/usr/lib/emscripten/em++";
            const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});

            emcc_command.step.dependOn(&mkdir_command.step);
            emcc_command.addArgs(&[_][]const u8{
                "-o",
                index_path,
                "-sFULL-ES3=1",
                "-sUSE_GLFW=3",
                "-O3",
                "-g",
                "-sASYNCIFY",
                "-sMIN_WEBGL_VERSION=2",
                "-sINITIAL_MEMORY=167772160",
                "-sALLOW_MEMORY_GROWTH=1",
                "-sMALLOC=emmalloc",
                "-sUSE_OFFSET_CONVERTER",
                "-sSUPPORT_LONGJMP=1",
                "-sERROR_ON_UNDEFINED_SYMBOLS=1",
                "-sSTACK_SIZE=2mb",
                "--shell-file",
                b.path("src/shell.html").getPath(b),
            });

            // Add all of the specified assets
            for (assets) |asset| {
                emcc_command.addArgs(&[_][]const u8{ "--preload-file", b.pathJoin(&.{ assets_dir, asset }) });
            }

            // Add the engine library and the example
            emcc_command.addFileArg(engine_lib.getEmittedBin());
            emcc_command.step.dependOn(&engine_lib.step);

            emcc_command.addFileArg(exe.getEmittedBin());
            emcc_command.step.dependOn(&exe.step);

            const install = emcc_command;
            b.default_step.dependOn(&install.step);
        },
        else => {
            // Link with the engine static library
            exe.linkLibrary(engine_lib);

            const path = b.pathJoin(&.{ "bin", name });

            const install_content_step = b.addInstallDirectory(.{
                .source_dir = b.path(assets_dir),
                .install_dir = .{ .custom = path },
                .install_subdir = "assets",
                .include_extensions = assets,
            });
            exe.step.dependOn(&install_content_step.step);

            const install_ex = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = path } } });
            //b.getInstallStep().dependOn(&.step);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.install_prefix, path }) });
            run_cmd.step.dependOn(&install_ex.step);

            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step(name, "Run example");
            run_step.dependOn(&run_cmd.step);
        },
    }

    return exe;
}
