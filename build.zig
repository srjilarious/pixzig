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

pub const EngineData = struct {
    engine_lib: *std.Build.Step.Compile,
    pixeng_mod: *std.Build.Module,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_examples = b.option(bool, "build_examples", "Build the examples") orelse true;

    // Build the engine as a static library
    const engDat = buildEngine(b, target, optimize);

    if (target.result.os.tag == .emscripten) {
        const engine_step = b.step("build-engine", "Build the pixzig object file for Emscripten");
        engine_step.dependOn(&engDat.engine_lib.step);
        b.default_step.dependOn(engine_step);
    }

    // Define examples
    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        assets: []const []const u8,
    }{
        .{ .name = "tile_load_test", .path = "examples/tile_load_test.zig", .assets = &.{
            "mario_grassish2.png",
            "level1a.tmx",
        } },
        .{ .name = "natetris", .path = "games/natetris/natetris.zig", .assets = &.{} },
        .{ .name = "actor_test", .path = "examples/actor_test.zig", .assets = &.{
            "pac-tiles.json",
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
        .{ .name = "text_rendering", .path = "examples/text_rendering.zig", .assets = &.{
            "Roboto-Medium.ttf",
        } },
    };

    // Create a "build-all" option that builds everything
    const build_all_step = b.step("build-all", "Build all examples");

    // std.debug.print("build_examples = {}\n", .{build_examples});
    if (build_examples) {
        // Build each example
        for (examples) |example_info| {
            const exe_mod = b.createModule(.{
                .root_source_file = b.path(example_info.path),
                .target = target,
                .optimize = optimize,
            });

            const exe = buildExample(
                b,
                target,
                optimize,
                engDat.engine_lib,
                engDat.pixeng_mod,
                example_info.name,
                exe_mod,
                example_info.assets,
            );
            const install_exe = b.addInstallArtifact(exe, .{
                .dest_dir = .{
                    .override = .{ .custom = b.pathJoin(&.{ "bin", example_info.name }) },
                },
            });
            build_all_step.dependOn(&install_exe.step);
        }

        if (target.result.os.tag != .emscripten) {
            // Sprite packer tool
            const spack_mod = b.createModule(.{
                .root_source_file = b.path("tools/spack/spack.zig"),
                .target = target,
                .optimize = optimize,
            });
            const spack = buildExample(b, target, optimize, engDat.engine_lib, engDat.pixeng_mod, "spack", spack_mod, &.{});
            const zargs = b.dependency("zargunaught", .{});
            spack.root_module.addImport("zargunaught", zargs.module("zargunaught"));

            const zstbi = b.dependency("zstbi", .{ .target = target });
            spack.root_module.addImport("zstbi", zstbi.module("root"));

            // Unit tests
            const tests_mod = b.createModule(.{
                .root_source_file = b.path("tests/main.zig"),
                .target = target,
                .optimize = optimize,
            });
            const tests = buildExample(b, target, optimize, engDat.engine_lib, engDat.pixeng_mod, "tests", tests_mod, &.{
                "Roboto-Medium.ttf",
            });
            const testzMod = b.dependency("testz", .{});
            tests.root_module.addImport("testz", testzMod.module("testz"));
        }
    }

    // Make build-all the default step
    b.default_step.dependOn(build_all_step);
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
    const engine_lib = blk: {
        if (target.result.os.tag != .emscripten) {
            const lib = b.addStaticLibrary(.{
                .name = "pixzig",
                .root_module = pixeng,
            });
            //engine_lib.root_module.strip = false;
            _ = b.addInstallArtifact(lib, .{});
            break :blk lib;
        } else {
            const obj = b.addObject(.{
                .name = "pixzig_obj",
                .root_source_file = b.path("src/pixzig/pixzig.zig"),
                .target = target,
                .optimize = optimize,
            });
            const installObjStep = b.addInstallFile(obj.getEmittedBin(), "web/pixzig.o");
            b.getInstallStep().dependOn(&installObjStep.step);

            break :blk obj;
        }
    };

    addArchIncludes(b, target, optimize, engine_lib) catch unreachable;
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
    const zflecs_lib = zflecs.artifact("flecs");
    addArchIncludes(b, target, optimize, zflecs_lib) catch unreachable;
    engine_lib.linkLibrary(zflecs_lib);

    // Stbi
    const zstbi = b.dependency("zstbi", .{ .target = target });
    const zstbi_mod = zstbi.module("root");
    pixeng.addImport("zstbi", zstbi_mod);

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
    const gui_lib = zgui.artifact("imgui");
    addArchIncludes(b, target, optimize, gui_lib) catch unreachable;
    engine_lib.linkLibrary(gui_lib);

    // Lua
    const ziglua = b.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
    ziglua.module("ziglua").addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
    ziglua.module("ziglua-c").addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
    const ziglua_mod = ziglua.module("ziglua");
    const ziglua_c_mod = ziglua.module("ziglua-c");
    pixeng.addImport("ziglua", ziglua_mod);
    pixeng.addImport("ziglua-c", ziglua_c_mod);
    const lua_lib = ziglua.artifact("lua");
    addArchIncludes(b, target, optimize, lua_lib) catch unreachable;
    engine_lib.linkLibrary(lua_lib);

    // XML for tilemap loading
    const xml = b.addModule("xml", .{ .root_source_file = b.path("libs/xml.zig") });
    pixeng.addImport("xml", xml);

    // STB Truetype module
    const stbtt = b.addModule("stb_truetype", .{ .root_source_file = b.path("libs/stb_truetype/stb_truetype.zig") });
    stbtt.addCSourceFile(.{ .file = b.path("libs/stb_truetype/stb_truetype.c") });
    stbtt.addIncludePath(b.path("libs/stb_truetype"));
    // Add Emscripten system includes for web builds
    if (target.result.os.tag == .emscripten) {
        stbtt.addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
    }
    pixeng.addImport("stb_truetype", stbtt);

    // Install the engine library
    if (target.result.os.tag != .emscripten) {
        b.installArtifact(engine_lib);
    }

    return .{ .engine_lib = engine_lib, .pixeng_mod = pixeng };
}

pub fn buildGame(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    engine_dep: *std.Build.Dependency,
    engine_mod: *std.Build.Module,
    name: []const u8,
    exe_mod: *std.Build.Module,
    assets: []const []const u8,
) *std.Build.Step.Compile {
    const engine_lib: ?*std.Build.Step.Compile = blk: {
        if (target.result.os.tag != .emscripten) {
            break :blk engine_dep.artifact("pixzig");
        } else {
            break :blk null;
        }
    };

    return buildExample(
        b,
        target,
        optimize,
        engine_lib,
        engine_mod,
        name,
        exe_mod,
        assets,
    );
}

pub fn buildExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    engine_lib: ?*std.Build.Step.Compile,
    pixeng_mod: *std.Build.Module,
    name: []const u8,
    exe_mod: *std.Build.Module,
    assets: []const []const u8,
) *std.Build.Step.Compile {
    const exe = blk: {
        if (target.result.os.tag == .emscripten) {
            break :blk b.addStaticLibrary(.{
                .name = name,
                .root_module = exe_mod,
            });
        } else {
            break :blk b.addExecutable(.{
                .name = name,
                .root_module = exe_mod,
            });
        }
    };

    // Add the engine module
    exe.root_module.addImport("pixzig", pixeng_mod);

    // Handle platform-specific linking
    switch (target.result.os.tag) {
        .emscripten => {
            const path = b.pathJoin(&.{ b.install_prefix, "web", name });
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
                //"-sMALLOC=emmalloc",
                "-sUSE_OFFSET_CONVERTER",
                "-sSUPPORT_LONGJMP=1",
                "-sERROR_ON_UNDEFINED_SYMBOLS=1",
                "-sSTACK_SIZE=2mb",
                "-sEXPORT_ALL=1",
                "--shell-file",
                b.path("src/shell.html").getPath(b),
            });

            // Add all of the specified assets
            for (assets) |asset| {
                emcc_command.addArgs(&[_][]const u8{ "--preload-file", b.pathJoin(&.{ assets_dir, asset }) });
            }

            emcc_command.addFileArg(exe.getEmittedBin());
            // emcc_command.addFileArg(engine_lib.getEmittedBin());
            // We setup the engine in an emscripten build to output a `web/engine.o` to link against
            const obj_path = pixeng_mod.owner.getInstallPath(
                .prefix,
                "web/pixzig.o",
            );
            emcc_command.addArg(obj_path);

            const zgui = pixeng_mod.owner.dependency("zgui", .{
                .target = target,
                .backend = .glfw_opengl3,
            });
            const gui_dep = zgui.artifact("imgui");
            emcc_command.addFileArg(gui_dep.getEmittedBin());

            // Lua
            const ziglua = pixeng_mod.owner.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
            const lua_dep = ziglua.artifact("lua");
            emcc_command.addFileArg(lua_dep.getEmittedBin());

            // emcc_command.addFileArg(.getEmittedBin());
            emcc_command.step.dependOn(&exe.step);

            const install = emcc_command;
            b.default_step.dependOn(&install.step);
        },
        else => {
            exe.linkLibrary(engine_lib.?);

            const path = b.pathJoin(&.{ "bin", name });

            const install_content_step = b.addInstallDirectory(.{
                .source_dir = b.path(assets_dir),
                .install_dir = .{ .custom = path },
                .install_subdir = "assets",
                .include_extensions = assets,
            });
            exe.step.dependOn(&install_content_step.step);

            const install_ex = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = path } } });

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
