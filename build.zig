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

            // TODO: Add this check back in.
            // var dir = std.fs.openDirAbsolute(cache_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch {
            //     @panic("No emscripten cache. Generate it!");
            // };

            // dir.close();
            dep.root_module.addIncludePath(.{ .cwd_relative = cache_include });
        },
        else => {},
    }
}

fn getSysRootInclude(b: *std.Build) []const u8 {
    return b.fmt("{s}/include", .{b.sysroot.?});
}

pub const EngineData = struct {
    engine_lib: *std.Build.Step.Compile,
    pixeng_mod: *std.Build.Module,
};

// ---------------------------------------------------------------------------
// Asset manifest build support
// ---------------------------------------------------------------------------

pub const AssetEntry = struct {
    id: []const u8,
    kind: []const u8,
    path: []const u8,
    /// Only required when kind == "font".
    font_size: ?f32 = null,
};

pub const GroupEntry = struct {
    name: []const u8,
    assets: []const []const u8,
};

/// Inline manifest definition for use directly in build.zig.
pub const ManifestDef = struct {
    root: []const u8 = "assets",
    groups: []const GroupEntry = &.{},
    assets: []const AssetEntry = &.{},
};

/// Returned by `manifestFromFile` / `manifestFromDef`; wire to an exe with `addTo`.
pub const ManifestHandle = struct {
    b: *std.Build,
    /// Non-null for file-based manifests: absolute path to the source JSON.
    file_abs_path: ?[]const u8,
    /// Non-null for inline manifests: the serialised JSON content.
    inline_json: ?[]const u8,
    /// For inline manifests: absolute path to the directory that contains the
    /// assets root (i.e. the build root, so `root` in the JSON resolves there).
    inline_base_dir: []const u8,
    /// Individual file paths (relative to `assets/`) for Emscripten --preload-file.
    /// If empty, the entire assets directory is preloaded.
    emcc_files: []const []const u8 = &.{},

    /// Wire the manifest into `exe`.
    ///
    /// **Dev mode** (`is_package == false`):
    ///   - File-based: `manifest_path` = absolute path, assets read from source tree.
    ///   - Inline: `manifest_json` / `manifest_base_dir` build options carry the
    ///     JSON content and asset root; no file needed.
    ///
    /// **Package mode** (`is_package == true`):
    ///   All assets + the manifest JSON are copied to
    ///   `<prefix>/bin/<exe_name>/assets/` and `manifest_path` is set to the
    ///   relative path `assets/manifest.json`.
    pub fn addTo(
        self: ManifestHandle,
        exe: *std.Build.Step.Compile,
        is_package: bool,
        src_assets_dir: []const u8,
    ) void {
        const b = self.b;
        const exe_name = exe.name;
        const opts = b.addOptions();

        if (!is_package) {
            if (self.file_abs_path) |abs_path| {
                // File-based dev: absolute path, read at runtime.
                opts.addOption([]const u8, "manifest_path", abs_path);
                opts.addOption([]const u8, "manifest_json", "");
                opts.addOption([]const u8, "manifest_base_dir", "");
            } else {
                // Inline dev: embed JSON content + asset root as build options.
                opts.addOption([]const u8, "manifest_path", "");
                opts.addOption([]const u8, "manifest_json", self.inline_json.?);
                opts.addOption([]const u8, "manifest_base_dir", self.inline_base_dir);
            }
        } else {
            // Package mode: copy assets + manifest to install tree.
            const dest_subdir = b.pathJoin(&.{ "bin", exe_name });

            const copy_assets = b.addInstallDirectory(.{
                .source_dir = b.path(src_assets_dir),
                .install_dir = .{ .custom = dest_subdir },
                .install_subdir = "assets",
            });
            exe.step.dependOn(&copy_assets.step);

            // Determine the source manifest file to install.
            const manifest_src: std.Build.LazyPath = if (self.file_abs_path) |ap|
                .{ .cwd_relative = ap }
            else blk: {
                // Write inline JSON to a WriteFile step for installation.
                const wf = b.addWriteFiles();
                break :blk wf.add("manifest.json", self.inline_json.?);
            };

            const install_manifest = b.addInstallFile(
                manifest_src,
                b.pathJoin(&.{ dest_subdir, "assets", "manifest.json" }),
            );
            exe.step.dependOn(&install_manifest.step);

            // At runtime exe cwd is <prefix>/bin/<exe_name>/,
            // so manifest is at assets/manifest.json relative to cwd.
            opts.addOption([]const u8, "manifest_path", "assets/manifest.json");
            opts.addOption([]const u8, "manifest_json", "");
            opts.addOption([]const u8, "manifest_base_dir", "");
        }

        exe.root_module.addOptions("manifest_options", opts);
    }
};

/// Reference an existing manifest JSON file in the repository.
/// The file is used as-is in dev mode; it is copied to the install dir in package mode.
pub fn manifestFromFile(b: *std.Build, path: []const u8) ManifestHandle {
    return .{
        .b = b,
        .file_abs_path = b.pathFromRoot(path),
        .inline_json = null,
        .inline_base_dir = b.pathFromRoot("."),
    };
}

/// Define a manifest inline in build.zig. The struct is serialised to JSON and
/// embedded as a build option so no file I/O is needed in dev mode.
/// `src_assets_root` is the directory the manifest's `root` field is relative to
/// (typically the repo root, i.e. `b.pathFromRoot(".")`).
pub fn manifestFromDef(b: *std.Build, def: ManifestDef) ManifestHandle {
    const json = generateManifestJson(b.allocator, def) catch @panic("OOM generating manifest JSON");

    // Build the emcc file list: atlas assets expand to .json + .png; others use path as-is.
    var files: std.ArrayList([]const u8) = .empty;
    for (def.assets) |asset| {
        if (std.mem.eql(u8, asset.kind, "atlas")) {
            files.append(b.allocator, b.fmt("{s}.json", .{asset.path})) catch @panic("OOM");
            files.append(b.allocator, b.fmt("{s}.png", .{asset.path})) catch @panic("OOM");
        } else {
            files.append(b.allocator, asset.path) catch @panic("OOM");
        }
    }

    return .{
        .b = b,
        .file_abs_path = null,
        .inline_json = json,
        .inline_base_dir = b.pathFromRoot("."),
        .emcc_files = files.toOwnedSlice(b.allocator) catch @panic("OOM"),
    };
}

fn jsonAppend(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(alloc, fmt, args);
    defer alloc.free(s);
    try buf.appendSlice(alloc, s);
}

fn generateManifestJson(alloc: std.mem.Allocator, def: ManifestDef) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(alloc);

    try buf.appendSlice(alloc, "{\n  \"version\": 1,\n");
    try jsonAppend(&buf, alloc, "  \"root\": \"{s}\",\n", .{def.root});

    // Groups object
    try buf.appendSlice(alloc, "  \"groups\": {\n");
    for (def.groups, 0..) |group, gi| {
        try jsonAppend(&buf, alloc, "    \"{s}\": [", .{group.name});
        for (group.assets, 0..) |id, ai| {
            try jsonAppend(&buf, alloc, "\"{s}\"", .{id});
            if (ai + 1 < group.assets.len) try buf.appendSlice(alloc, ", ");
        }
        try buf.appendSlice(alloc, "]");
        if (gi + 1 < def.groups.len) try buf.appendSlice(alloc, ",");
        try buf.appendSlice(alloc, "\n");
    }
    try buf.appendSlice(alloc, "  },\n");

    // Assets array
    try buf.appendSlice(alloc, "  \"assets\": [\n");
    for (def.assets, 0..) |asset, ai| {
        try jsonAppend(&buf, alloc, "    {{\"id\": \"{s}\", \"kind\": \"{s}\", \"path\": \"{s}\"", .{
            asset.id, asset.kind, asset.path,
        });
        if (asset.font_size) |fs| {
            try jsonAppend(&buf, alloc, ", \"font_size\": {d}", .{fs});
        }
        try buf.appendSlice(alloc, "}");
        if (ai + 1 < def.assets.len) try buf.appendSlice(alloc, ",");
        try buf.appendSlice(alloc, "\n");
    }
    try buf.appendSlice(alloc, "  ]\n}\n");

    return buf.toOwnedSlice(alloc);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_examples = b.option(bool, "build_examples", "Build the examples") orelse true;
    const is_package = b.option(bool, "package", "Package assets to the output directory") orelse false;

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
        manifest_def: ManifestDef = .{},
        extraMods: []const []const u8 = &.{},
        buildForWeb: bool = true,
    }{
        .{
            .name = "audio_ex",
            .path = "examples/audio_ex.zig",
            .manifest_def = .{
                .assets = &.{
                    .{ .id = "laserShoot", .kind = "raw", .path = "laserShoot.wav" },
                },
            },
        },
        .{
            .name = "tile_load_ex",
            .path = "examples/tile_load_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{ "tiles", "level1a" } }},
                .assets = &.{
                    .{ .id = "tiles", .kind = "texture", .path = "mario_grassish2.png" },
                    .{ .id = "level1a", .kind = "tilemap", .path = "level1a.tmx" },
                },
            },
        },
        .{
            .name = "natetris",
            .path = "games/natetris/natetris.zig",
        },
        .{
            .name = "actor_ex",
            .path = "examples/actor_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"pac-tiles"} }},
                .assets = &.{
                    .{ .id = "pac-tiles", .kind = "atlas", .path = "pac-tiles" },
                },
            },
        },
        .{
            .name = "sequencer_ex",
            .path = "examples/sequencer_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{ "pac-tiles", "circle_move" } }},
                .assets = &.{
                    .{ .id = "pac-tiles", .kind = "atlas", .path = "pac-tiles" },
                    .{ .id = "circle_move", .kind = "raw", .path = "circle_move.lua" },
                },
            },
        },
        .{
            .name = "collision_ex",
            .path = "examples/collision_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"tiles"} }},
                .assets = &.{
                    .{ .id = "tiles", .kind = "texture", .path = "pac-tiles.png" },
                },
            },
        },
        .{
            .name = "flecs_ex",
            .path = "examples/flecs_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"tiles"} }},
                .assets = &.{
                    .{ .id = "tiles", .kind = "texture", .path = "mario_grassish2.png" },
                },
            },
        },
        .{
            .name = "a_star_path_ex",
            .path = "examples/a_star_path_ex.zig",
        },
        .{
            .name = "gameloop_ex",
            .path = "examples/gameloop_ex.zig",
        },
        .{
            .name = "gamepad_ex",
            .path = "examples/gamepad_ex.zig",
        },
        .{
            .name = "game_state_ex",
            .path = "examples/game_state_ex.zig",
        },
        .{
            .name = "render_ex",
            .path = "examples/render_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"tiles"} }},
                .assets = &.{
                    .{ .id = "tiles", .kind = "texture", .path = "mario_grassish2.png" },
                },
            },
        },
        .{
            .name = "grid_render_ex",
            .path = "examples/grid_render_ex.zig",
        },
        .{
            .name = "console2_ex",
            .path = "examples/console2_ex.zig",
            .manifest_def = .{
                .assets = &.{
                    .{ .id = "Roboto-Medium", .kind = "raw", .path = "Roboto-Medium.ttf" },
                },
            },
        },
        .{
            .name = "console_ex",
            .path = "examples/console_ex.zig",
            .manifest_def = .{
                .assets = &.{
                    .{ .id = "Roboto-Medium", .kind = "raw", .path = "Roboto-Medium.ttf" },
                },
            },
        },
        .{
            .name = "imgui_ex",
            .path = "examples/imgui_ex.zig",
            .manifest_def = .{
                .assets = &.{
                    .{ .id = "Roboto-Medium", .kind = "raw", .path = "Roboto-Medium.ttf" },
                    .{ .id = "tiles", .kind = "texture", .path = "mario_grassish2.png" },
                },
            },
        },
        .{
            .name = "text_rendering_ex",
            .path = "examples/text_rendering_ex.zig",
            .manifest_def = .{
                .assets = &.{
                    .{ .id = "Roboto-Medium", .kind = "raw", .path = "Roboto-Medium.ttf" },
                },
            },
        },
        .{
            .name = "bitmap_text_rendering_ex",
            .path = "examples/bitmap_text_rendering_ex.zig",
            .manifest_def = .{
                .assets = &.{
                    .{ .id = "font5r", .kind = "raw", .path = "font5r.png" },
                },
            },
        },
        .{
            .name = "pixel_buffer_ex",
            .path = "examples/pixel_buffer_ex.zig",
        },
        .{
            .name = "mouse_ex",
            .path = "examples/mouse_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"tiles"} }},
                .assets = &.{
                    .{ .id = "tiles", .kind = "texture", .path = "mario_grassish2.png" },
                },
            },
        },
        // manifest_ex: demonstrates manifest-based asset loading at runtime.
        .{
            .name = "manifest_ex",
            .path = "examples/manifest_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "game", .assets = &.{"pac_tiles"} }},
                .assets = &.{
                    .{ .id = "pac_tiles", .kind = "atlas", .path = "pac-tiles" },
                },
            },
            .buildForWeb = false,
        },
        // Unit tests
        .{
            .name = "tests",
            .path = "tests/main.zig",
            .manifest_def = .{
                .assets = &.{
                    .{ .id = "Roboto-Medium", .kind = "raw", .path = "Roboto-Medium.ttf" },
                },
            },
            .extraMods = &.{"testz"},
            .buildForWeb = false,
        },
    };

    // Create a "build-all" option that builds everything
    const build_all_step = b.step("build-all", "Build all examples");

    // std.debug.print("build_examples = {}\n", .{build_examples});
    if (build_examples) {
        // Build each example
        for (examples) |example_info| {
            // Skip if marked to not build for web and we're building for emscripten.
            if (target.result.os.tag == .emscripten and !example_info.buildForWeb) continue;

            const exe_mod = b.createModule(.{
                .root_source_file = b.path(example_info.path),
                .target = target,
                .optimize = optimize,
            });

            const manifest = manifestFromDef(b, example_info.manifest_def);
            const exe = buildExample(
                b,
                target,
                optimize,
                engDat.engine_lib,
                engDat.pixeng_mod,
                example_info.name,
                exe_mod,
                manifest,
                is_package,
            );

            for (example_info.extraMods) |em| {
                const extraMod = b.dependency(em, .{});
                exe_mod.addImport(em, extraMod.module(em));
            }
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
            const spack = buildExample(b, target, optimize, engDat.engine_lib, engDat.pixeng_mod, "spack", spack_mod, manifestFromDef(b, .{}), is_package);
            const zargs = b.dependency("zargunaught", .{});
            spack.root_module.addImport("zargunaught", zargs.module("zargunaught"));

            const zstbi = b.dependency("zstbi", .{ .target = target });
            spack.root_module.addImport("zstbi", zstbi.module("root"));

            // Pixzig docs step
            const zkdocs = @import("zkdocs");
            b.step("docs", "Docs").dependOn(zkdocs.addDocsStep(b, .{
                .conf = "docs/zkdocs.conf",
                .out = "docs-out",
            }));
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
            const lib = b.addLibrary(.{
                .name = "pixzig",
                .root_module = pixeng,
                .linkage = .static,
            });
            //engine_lib.root_module.strip = false;
            _ = b.addInstallArtifact(lib, .{});
            break :blk lib;
        } else {
            const obj = b.addObject(.{
                .name = "pixzig_obj",
                .root_module = pixeng,
            });
            const installObjStep = b.addInstallFile(obj.getEmittedBin(), "web/pixzig.o");
            b.getInstallStep().dependOn(&installObjStep.step);

            break :blk obj;
        }
    };

    addArchIncludes(b, target, optimize, engine_lib) catch unreachable;
    engine_lib.root_module.link_libc = true;

    // GLFW
    const zglfw = b.dependency("zglfw", .{ .target = target });
    const zglfw_mod = zglfw.module("root");
    pixeng.addImport("zglfw", zglfw_mod);
    if (target.result.os.tag != .emscripten) {
        const glfw_dep = zglfw.artifact("glfw");
        engine_lib.root_module.linkLibrary(glfw_dep);
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
    engine_lib.root_module.linkLibrary(zflecs_lib);

    // Stbi
    const zstbi = b.dependency("zstbi", .{ .target = target });
    const zstbi_mod = zstbi.module("root");
    pixeng.addImport("zstbi", zstbi_mod);

    // Math
    const zmath = b.dependency("zmath", .{ .target = target });
    const math_mod = zmath.module("root");
    pixeng.addImport("zmath", math_mod);

    // Audio
    const zaudio = b.dependency("zaudio", .{ .target = target });
    pixeng.addImport("zaudio", zaudio.module("root"));
    const miniaudio = zaudio.artifact("miniaudio");
    addArchIncludes(b, target, optimize, miniaudio) catch unreachable;
    engine_lib.root_module.linkLibrary(miniaudio);

    // Lua
    const ziglua = b.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
    if (target.result.os.tag == .emscripten) {
        ziglua.module("zlua").addIncludePath(.{ .cwd_relative = getSysRootInclude(b) });
    }

    const ziglua_mod = ziglua.module("zlua");
    pixeng.addImport("ziglua", ziglua_mod);

    const ziglua_c_mod = ziglua.module("ziglua-c");
    pixeng.addImport("ziglua-c", ziglua_c_mod);

    const lua_lib = ziglua.artifact("lua");
    addArchIncludes(b, target, optimize, lua_lib) catch unreachable;
    engine_lib.root_module.linkLibrary(lua_lib);

    // XML for tilemap loading
    const xml = b.addModule("xml", .{ .root_source_file = b.path("libs/xml.zig") });
    pixeng.addImport("xml", xml);

    // STB Truetype module
    const stbtt_translate = b.addTranslateC(.{
        .root_source_file = b.path("libs/stb_truetype/stb_truetype.h"),
        .target = target,
        .optimize = optimize,
    });
    stbtt_translate.addIncludePath(b.path("libs/stb_truetype"));
    if (target.result.os.tag == .emscripten) {
        if (b.sysroot == null) @panic("Pass '--sysroot' for emscripten builds");
        const em_inc = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "include" }) catch @panic("OOM");
        stbtt_translate.addIncludePath(.{ .cwd_relative = em_inc });
    }

    const stbtt = b.addModule("stb_truetype", .{ .root_source_file = b.path("libs/stb_truetype/stb_truetype.zig") });
    stbtt.addImport("c", stbtt_translate.createModule());
    stbtt.addCSourceFile(.{ .file = b.path("libs/stb_truetype/stb_truetype.c"), .flags = &.{"-fno-sanitize=undefined"} });
    stbtt.addIncludePath(b.path("libs/stb_truetype"));
    if (target.result.os.tag == .emscripten) {
        stbtt.addIncludePath(.{ .cwd_relative = getSysRootInclude(b) });
    }
    pixeng.addImport("stb_truetype", stbtt);

    // C time functions (localtime / localtime_r) for local-time logging
    const time_c_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/pixzig/time_c.h"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .emscripten) {
        if (b.sysroot == null) @panic("Pass '--sysroot' for emscripten builds");
        const em_inc = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "include" }) catch @panic("OOM");
        time_c_translate.addIncludePath(.{ .cwd_relative = em_inc });
    }
    pixeng.addImport("c_time", time_c_translate.createModule());

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
    manifest: ManifestHandle,
) *std.Build.Step.Compile {
    const engine_lib: ?*std.Build.Step.Compile = blk: {
        if (target.result.os.tag != .emscripten) {
            break :blk engine_dep.artifact("pixzig");
        } else {
            break :blk null;
        }
    };

    const is_package = b.option(bool, "package", "Package assets to the output directory") orelse false;

    return buildExample(b, target, optimize, engine_lib, engine_mod, name, exe_mod, manifest, is_package);
}

pub fn buildExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    engine_lib: ?*std.Build.Step.Compile,
    pixeng_mod: *std.Build.Module,
    name: []const u8,
    exe_mod: *std.Build.Module,
    manifest: ManifestHandle,
    is_package: bool,
) *std.Build.Step.Compile {
    const exe = blk: {
        if (target.result.os.tag == .emscripten) {
            break :blk b.addLibrary(.{
                .name = name,
                .root_module = exe_mod,
                .linkage = .static,
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

            const emcc_exe_path = "em++";
            const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});

            emcc_command.step.dependOn(&mkdir_command.step);
            emcc_command.addArgs(&[_][]const u8{
                "-o",
                index_path,
                "-sFULL-ES3=1",
                "-sUSE_GLFW=3",
                "-O3",
                "-g",
                "-sASYNCIFY=1",
                "-sUSE_WEBGL2=1",
                // "-sOFFSCREEN_FRAMEBUFFER=1",
                "-sMIN_WEBGL_VERSION=2",
                "-sINITIAL_MEMORY=167772160",
                "-sALLOW_MEMORY_GROWTH=1",
                //"-sMALLOC=emmalloc",
                // "-sUSE_OFFSET_CONVERTER=1",
                "-sSUPPORT_LONGJMP=1",
                "-sERROR_ON_UNDEFINED_SYMBOLS=1",
                "-sSTACK_SIZE=2mb",
                "-sEXPORT_ALL=1",
                // "-sAUDIO_WORKLET=1",
                // "-sWASM_WORKERS=1",
                "--shell-file",
                b.path("src/shell.html").getPath(b),
            });

            // Preload assets: use explicit file list when available, else whole dir.
            if (manifest.emcc_files.len > 0) {
                for (manifest.emcc_files) |asset| {
                    emcc_command.addArgs(&[_][]const u8{ "--preload-file", b.pathJoin(&.{ assets_dir, asset }) });
                }
            } else {
                emcc_command.addArgs(&[_][]const u8{ "--preload-file", b.fmt("{s}@/{s}", .{ assets_dir, assets_dir }) });
            }

            emcc_command.addFileArg(exe.getEmittedBin());
            if (engine_lib) |lib| {
                emcc_command.addFileArg(lib.getEmittedBin());
            } else {
                const obj_path = pixeng_mod.owner.getInstallPath(
                    .prefix,
                    "web/pixzig.o",
                );
                emcc_command.addArg(obj_path);
            }

            // Lua
            const ziglua = pixeng_mod.owner.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
            const lua_dep = ziglua.artifact("lua");
            emcc_command.addFileArg(lua_dep.getEmittedBin());

            // Zaudio / Miniaudio
            const zaudio = pixeng_mod.owner.dependency("zaudio", .{ .target = target, .optimize = optimize });
            const zaudio_dep = zaudio.artifact("miniaudio");
            emcc_command.addFileArg(zaudio_dep.getEmittedBin());

            emcc_command.step.dependOn(&exe.step);

            const install = emcc_command;
            b.default_step.dependOn(&install.step);

            const build_step = b.step(name, "Build web example");
            build_step.dependOn(&install.step);
        },
        else => {
            const out_path = b.pathJoin(&.{ "bin", name });

            // Wire the manifest (dev: embed JSON/path; package: copy assets + install manifest).
            manifest.addTo(exe, is_package, assets_dir);

            const install_ex = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = out_path } } });

            const run_cmd = b.addRunArtifact(exe);
            if (is_package) {
                // Package mode: exe runs from install dir where assets were copied.
                run_cmd.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.install_prefix, out_path }) });
            } else {
                // Dev mode: exe runs from repo root so it can read assets in-place.
                run_cmd.setCwd(b.path("."));
            }
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
