const std = @import("std");
const testz = @import("testz");
const builtin = std.builtin;
pub const android = @import("build/android.zig");

// Zig 0.17 dropped --sysroot access from build.zig; the emscripten
// sysroot comes from the EMSCRIPTEN_SYSROOT env var now.
fn emSysroot(b: *std.Build) []const u8 {
    return b.graph.environ_map.get("EMSCRIPTEN_SYSROOT") orelse
        @panic("Set EMSCRIPTEN_SYSROOT for emscripten builds, e.g. ~/.cache/emscripten/sysroot");
}

// Replacement for the removed b.pathFromRoot.
fn fromRoot(b: *std.Build, sub: []const u8) []const u8 {
    return b.root.joinString(b.allocator, sub) catch @panic("OOM");
}

const assets_dir = "assets";

/// `target` with the Android API level filled in (see
/// `android.toolchain`), or `target` unchanged for everything else, so the
/// engine and every C dependency agree on which bionic they build against.
fn androidApiTarget(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.ResolvedTarget {
    if (!android.isAndroid(target)) return target;
    return android.toolchain(b, target).ndk.target;
}

fn addArchIncludes(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, dep: *std.Build.Step.Compile) !void {
    _ = optimize;
    switch (target.result.os.tag) {
        .emscripten => {
            const cache_include = std.fs.path.join(b.allocator, &.{ emSysroot(b), "include" }) catch @panic("Out of memory");
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
    return b.fmt("{s}/include", .{emSysroot(b)});
}

pub const EngineData = struct {
    engine_lib: *std.Build.Step.Compile,
    pixeng_mod: *std.Build.Module,
};

/// Memo for the Windows `sdl3` module. `sdlModule` is called once per consumer
/// (the engine module, and again for the `tests` exe), and every `addTranslateC`
/// call on the same header yields a *separate* module whose root is the one
/// generated `sdl.zig` file. Importing two of those into one compile is the
/// "file exists in modules 'sdl3' and 'sdl30'" error, so hand back the same
/// module object every time. A `std.Build` graph only ever builds one target,
/// so a single slot is enough.
var windows_sdl_module: ?*std.Build.Module = null;

/// Memo for the Android `sdl3` module and the `libSDL3.so` behind it, for
/// the same reason as `windows_sdl_module`; the APK packaging needs the
/// library too.
var android_sdl: ?struct {
    module: *std.Build.Module,
    lib: *std.Build.Step.Compile,
    java_dir: std.Build.LazyPath,
} = null;

/// Memo for the `apkpack` host tool: one build of it serves every APK.
var apkpack_tool: ?*std.Build.Step.Compile = null;

/// Returns the `sdl3` module the engine imports.
///
/// On desktop this is the `allyourcodebase/SDL` package's own module, which
/// carries the static libSDL3 with it, so importing it is all any consumer
/// needs -- no separate `linkLibrary`.
///
/// Windows (cross-compiled, normally the gnu ABI, which is what CI uses) is a
/// special case. The package's `sdl3` module is produced by `zig translate-c`,
/// and Zig 0.17's translate-c uses the Aro C frontend. Aro cannot parse the
/// bundled clang `<avx512*intrin.h>` headers: they call
/// `__builtin_elementwise_fshr`, `__builtin_elementwise_fshl` and
/// `__builtin_elementwise_clzg`, builtins Aro does not implement. On Windows the
/// mingw-w64 `<winnt.h>` / `<intrin.h>` chain pulls `<immintrin.h>` in
/// unconditionally, so the translation blows up with ~44 errors before it ever
/// reaches an SDL declaration. We run our own translate-c of the same header
/// there with those three builtins neutralised to a passthrough of their first
/// argument, then link the package's real static libSDL3 artifact. Nothing in
/// pixzig uses the AVX-512 intrinsic wrappers this produces; they are incidental
/// noise from the header pull.
///
/// Emscripten is different again. That package's `build.zig` has no target
/// config for wasm and panics outright, and even with the config disabled its
/// module drags the unbuildable library in behind it. Emscripten ships its
/// own SDL3 port, so there the link side comes from `--use-port=sdl3` in
/// `emcc` (see the emcc args in `buildExample`) and all we need from Zig is
/// the type and constant declarations. So we translate the upstream SDL
/// headers ourselves, reaching them through the package's own dependency on
/// them, and produce a module that links nothing.
///
/// Android is a fourth case: the package knows no Android config either, so
/// `build/android.zig` compiles the same upstream sources the way SDL's own
/// `Android.mk` does, into the `libSDL3.so` that `SDLActivity` loads.
fn sdlModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    if (target.result.os.tag == .windows) {
        if (windows_sdl_module) |mod| return mod;

        const sdl_dep = b.dependency("sdl", .{ .target = target, .optimize = optimize });
        const upstream = sdl_dep.builder.dependency("sdl", .{});

        const translate = b.addTranslateC(.{
            .root_source_file = sdl_dep.path("src/sdl.h"),
            .target = target,
            .optimize = optimize,
        });
        translate.defineCMacro("USING_GENERATED_CONFIG_H", "1");
        // See the doc comment: work around Aro choking on the bundled clang
        // AVX-512 intrinsic headers that mingw's headers drag in.
        translate.defineCMacroRaw("__builtin_elementwise_fshr(a,b,c)=(a)");
        translate.defineCMacroRaw("__builtin_elementwise_fshl(a,b,c)=(a)");
        translate.defineCMacroRaw("__builtin_elementwise_clzg(a,...)=(a)");
        translate.addIncludePath(upstream.path("include"));
        translate.addIncludePath(upstream.path("src/video/khronos"));

        const mod = translate.createModule();
        mod.linkLibrary(sdl_dep.artifact("SDL3"));
        windows_sdl_module = mod;
        return mod;
    }

    if (android.isAndroid(target)) {
        if (android_sdl == null) {
            const sdl_pkg = b.dependency("sdl", .{
                .target = target,
                .optimize = optimize,
                .default_target_config = false,
            });
            const built = android.sdlModule(b, android.toolchain(b, target).ndk, optimize, sdl_pkg);
            android_sdl = .{ .module = built.module, .lib = built.lib, .java_dir = android.sdlJavaDir(sdl_pkg) };
        }
        return android_sdl.?.module;
    }

    if (target.result.os.tag != .emscripten) {
        const sdl_dep = b.dependency("sdl", .{ .target = target, .optimize = optimize });
        return sdl_dep.module("sdl3");
    }

    _ = emSysroot(b); // fail early if EMSCRIPTEN_SYSROOT is unset

    // `default_target_config = false` keeps the package's build() from
    // panicking on an unrecognised target; we only want at its `sdl`
    // dependency, which is the upstream source tree with the headers.
    const sdl_pkg = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .default_target_config = false,
    });
    const upstream = sdl_pkg.builder.dependency("sdl", .{});

    const translate = b.addTranslateC(.{
        .root_source_file = sdl_pkg.path("src/sdl.h"),
        .target = target,
        .optimize = optimize,
    });
    translate.defineCMacro("USING_GENERATED_CONFIG_H", "1");
    translate.addIncludePath(upstream.path("include"));
    translate.addIncludePath(upstream.path("src/video/khronos"));
    translate.addIncludePath(.{ .cwd_relative = getSysRootInclude(b) });
    return translate.createModule();
}

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
    /// Non-null for file-based manifests: the source JSON's path relative to
    /// the build root, which is also its path in the Emscripten virtual FS.
    file_rel_path: ?[]const u8 = null,
    /// Non-null for inline manifests: the serialised JSON content.
    inline_json: ?[]const u8,
    /// For inline manifests: absolute path to the directory that contains the
    /// assets root (i.e. the build root, so `root` in the JSON resolves there).
    inline_base_dir: []const u8,
    /// Individual file paths (relative to `assets/`) for Emscripten --preload-file.
    /// If empty, the entire assets directory is preloaded.
    emcc_files: []const []const u8 = &.{},

    /// Wire the manifest into `exe`, adding the generated `manifest_options`
    /// import to the executable's root module.
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
        self.addToModule(exe, exe.root_module, is_package, src_assets_dir);
    }

    /// Wire the manifest into `exe`, adding the generated `manifest_options`
    /// import to `mod`. This is useful when the executable root is a generated
    /// wrapper and the caller's game module still imports `manifest_options`.
    pub fn addToModule(
        self: ManifestHandle,
        exe: *std.Build.Step.Compile,
        mod: *std.Build.Module,
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
                b.pathJoin(&.{ dest_subdir, "manifest.json" }),
            );
            exe.step.dependOn(&install_manifest.step);

            // The manifest is installed beside assets/, not inside it: its
            // `root` field (e.g. "assets") is resolved relative to the
            // manifest's own directory, so nesting the manifest inside
            // assets/ would make asset paths resolve to assets/assets/...
            // `manifest_path` is relative; `AssetManifest.loadFromFile`
            // resolves it against the running executable's own directory
            // (not the process cwd), so the package works no matter where
            // it's launched from.
            opts.addOption([]const u8, "manifest_path", "manifest.json");
            opts.addOption([]const u8, "manifest_json", "");
            opts.addOption([]const u8, "manifest_base_dir", "");
        }

        mod.addOptions("manifest_options", opts);
    }

    /// Wire the manifest into a web (Emscripten) `exe`. Assets are preloaded
    /// into the virtual FS relative to `/` (see the emcc args in
    /// `buildExample`), so the manifest resolves from there rather than from
    /// the host build root. A file-based manifest outside `assets/` is
    /// preloaded here as well.
    pub fn addToWeb(self: ManifestHandle, exe: *std.Build.Step.Compile, emcc_command: *std.Build.Step.Run) void {
        self.addToWebModule(exe, exe.root_module, emcc_command);
    }

    /// Web variant of `addToModule`.
    pub fn addToWebModule(
        self: ManifestHandle,
        exe: *std.Build.Step.Compile,
        mod: *std.Build.Module,
        emcc_command: *std.Build.Step.Run,
    ) void {
        const b = self.b;
        _ = exe;
        const opts = b.addOptions();

        if (self.file_rel_path) |rel| {
            if (!std.mem.startsWith(u8, rel, assets_dir ++ "/")) {
                emcc_command.addArgs(&.{ "--preload-file", b.fmt("{s}@/{s}", .{ rel, rel }) });
            }
            opts.addOption([]const u8, "manifest_path", b.fmt("/{s}", .{rel}));
            opts.addOption([]const u8, "manifest_json", "");
            opts.addOption([]const u8, "manifest_base_dir", "");
        } else {
            opts.addOption([]const u8, "manifest_path", "");
            opts.addOption([]const u8, "manifest_json", self.inline_json.?);
            opts.addOption([]const u8, "manifest_base_dir", "/");
        }

        mod.addOptions("manifest_options", opts);
    }

    /// Wire the manifest into an Android game module. Android reads assets
    /// out of the APK, where `addApk` puts `assets/` at the same relative
    /// path it has in the source tree, so the manifest resolves relative to
    /// the APK's asset root. A file-based manifest outside `assets/` is
    /// packaged too: the returned entries go in `ApkOptions.extra_assets`.
    pub fn addToAndroidModule(self: ManifestHandle, mod: *std.Build.Module) []const android.ExtraAsset {
        const b = self.b;
        const opts = b.addOptions();
        var extra: []const android.ExtraAsset = &.{};

        if (self.file_rel_path) |rel| {
            if (!std.mem.startsWith(u8, rel, assets_dir ++ "/")) {
                extra = b.allocator.dupe(android.ExtraAsset, &.{.{ .dest = rel, .source = b.path(rel) }}) catch @panic("OOM");
            }
            opts.addOption([]const u8, "manifest_path", rel);
            opts.addOption([]const u8, "manifest_json", "");
            opts.addOption([]const u8, "manifest_base_dir", "");
        } else {
            opts.addOption([]const u8, "manifest_path", "");
            opts.addOption([]const u8, "manifest_json", self.inline_json.?);
            opts.addOption([]const u8, "manifest_base_dir", "");
        }

        mod.addOptions("manifest_options", opts);
        return extra;
    }
};

/// Reference an existing manifest JSON file in the repository.
/// The file is used as-is in dev mode; it is copied to the install dir in package mode.
pub fn manifestFromFile(b: *std.Build, path: []const u8) ManifestHandle {
    return .{
        .b = b,
        .file_abs_path = fromRoot(b, path),
        .file_rel_path = path,
        .inline_json = null,
        .inline_base_dir = fromRoot(b, "."),
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
        .inline_base_dir = fromRoot(b, "."),
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
    const target = androidApiTarget(b, b.standardTargetOptions(.{}));
    const optimize = b.standardOptimizeOption(.{});
    const is_android = android.isAndroid(target);

    const build_examples = b.option(bool, "build_examples", "Build the examples") orelse true;
    const is_package = b.option(bool, "package", "Package assets to the output directory") orelse false;

    // Build the engine as a static library
    const engDat = buildEngine(b, target, optimize, is_package);

    buildPythonFfi(b, target, optimize, engDat.pixeng_mod);

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
        buildForWeb: bool = true,
    }{
        .{
            .name = "audio_ex",
            .path = "examples/audio_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{ "laserShoot", "explosion", "theme" } }},
                .assets = &.{
                    .{ .id = "laserShoot", .kind = "sound", .path = "laserShoot.wav" },
                    .{ .id = "explosion", .kind = "sound", .path = "explosion.wav" },
                    .{ .id = "theme", .kind = "music", .path = "music_loop.ogg" },
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
            .name = "create_texture_ex",
            .path = "examples/create_texture_ex.zig",
        },
        .{
            .name = "quad3d_ex",
            .path = "examples/quad3d_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"tiles"} }},
                .assets = &.{
                    .{ .id = "tiles", .kind = "texture", .path = "mario_grassish2.png" },
                },
            },
        },
        .{
            .name = "console_ex",
            .path = "examples/console_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"Roboto-Medium"} }},
                .assets = &.{
                    .{ .id = "Roboto-Medium", .kind = "font", .path = "Roboto-Medium.ttf", .font_size = 20.0 },
                },
            },
        },
        .{
            .name = "imgui_ex",
            .path = "examples/imgui_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"Roboto-Medium"} }},
                .assets = &.{
                    .{ .id = "Roboto-Medium", .kind = "font", .path = "Roboto-Medium.ttf", .font_size = 20.0 },
                    .{ .id = "tiles", .kind = "texture", .path = "mario_grassish2.png" },
                },
            },
        },
        .{
            .name = "text_rendering_ex",
            .path = "examples/text_rendering_ex.zig",
            .manifest_def = .{
                .groups = &.{.{ .name = "boot", .assets = &.{"Roboto-Medium"} }},
                .assets = &.{
                    .{ .id = "Roboto-Medium", .kind = "font", .path = "Roboto-Medium.ttf", .font_size = 20.0 },
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
            .name = "touch_ex",
            .path = "examples/touch_ex.zig",
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
                engDat.engine_lib.getEmittedBin(),
                engDat.pixeng_mod,
                example_info.name,
                exe_mod,
                manifest,
                is_package,
                true,
            );

            // On Android `buildExample` installs the APK instead.
            if (is_android) continue;
            const install_exe = b.addInstallArtifact(exe, .{
                .dest_dir = .{
                    .override = .{ .custom = b.pathJoin(&.{ "bin", example_info.name }) },
                },
            });
            build_all_step.dependOn(&install_exe.step);
        }

        if (target.result.os.tag != .emscripten and !is_android) {
            const install_tests = buildTests(b, target, optimize, engDat.pixeng_mod, is_package);
            build_all_step.dependOn(&install_tests.step);

            // Sprite packer tool
            const spack_mod = b.createModule(.{
                .root_source_file = b.path("tools/spack/spack.zig"),
                .target = target,
                .optimize = optimize,
            });
            const spack = buildExample(b, target, optimize, null, engDat.pixeng_mod, "spack", spack_mod, manifestFromDef(b, .{}), is_package, false);
            const zargs = b.dependency("zargunaught", .{});
            spack.root_module.addImport("zargunaught", zargs.module("zargunaught"));

            const zstbi = b.dependency("zstbi", .{ .target = target });
            spack.root_module.addImport("zstbi", zstbi.module("root"));

            // Python constants generator. Keeps python/pixzig/constants.py
            // in step with the engine's input enums; run it after editing
            // src/pixzig/input/keys.zig and commit the result.
            const gen_consts_mod = b.createModule(.{
                .root_source_file = b.path("tools/gen_py_constants/gen_py_constants.zig"),
                .target = target,
                .optimize = optimize,
            });
            gen_consts_mod.addImport("pixzig", engDat.pixeng_mod);
            const gen_consts = b.addExecutable(.{
                .name = "gen_py_constants",
                .root_module = gen_consts_mod,
            });
            gen_consts.root_module.linkLibrary(engDat.engine_lib);
            const run_gen_consts = b.addRunArtifact(gen_consts);
            run_gen_consts.setCwd(b.path("."));
            run_gen_consts.addArg("python/pixzig/constants.py");
            b.step("py-constants", "Regenerate python/pixzig/constants.py from the input enums")
                .dependOn(&run_gen_consts.step);

            const zkdocs = @import("zkdocs");
            b.step("docs", "Docs").dependOn(zkdocs.addDocsStep(b, .{
                .conf = "docs/zkdocs.conf",
                .out = "docs-out",
            }));
        }
    }

    addNewProjectStep(b);

    // Make build-all the default step
    b.default_step.dependOn(build_all_step);
}

/// `zig build new -Dname=my_cool_game -Ddest=../my_cool_game` copies
/// `template/` into a new game project (see tools/new_project).
fn addNewProjectStep(b: *std.Build) void {
    const name = b.option([]const u8, "name", "zig build new: the new project's name") orelse "my_game";
    const dest = b.option([]const u8, "dest", "zig build new: directory to create, relative to the pixzig root") orelse
        b.fmt("../{s}", .{name});

    const tool = b.addExecutable(.{
        .name = "new_project",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/new_project/new_project.zig"),
            .target = b.graph.host,
        }),
    });
    const run = b.addRunArtifact(tool);
    // Relative arguments resolve against the pixzig root.
    run.setCwd(b.path("."));
    run.addArg("template");
    run.addArg(dest);
    run.addArg(name);
    run.addArg(".");
    // It creates a directory outside the cache, so never skip it as cached.
    run.has_side_effects = true;

    b.step("new", "Create a new game project from template/ (-Dname=..., -Ddest=...)").dependOn(&run.step);
}

fn buildEngine(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    is_package: bool,
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
            // Linked into a game's `libmain.so` on Android.
            if (android.isAndroid(target)) lib.root_module.pic = true;
            break :blk lib;
        } else {
            const obj = b.addObject(.{
                .name = "pixzig_obj",
                .root_module = pixeng,
            });
            const installObjStep = b.addInstallFile(obj.getEmittedBin(), "web/pixzig.o");
            b.getInstallStep().dependOn(&installObjStep.step);
            // Lets `buildGame` link the object straight from the dependency,
            // without the game depending on pixzig's install step.
            b.addNamedLazyPath("pixzig_obj", obj.getEmittedBin());

            break :blk obj;
        }
    };

    addArchIncludes(b, target, optimize, engine_lib) catch unreachable;
    engine_lib.root_module.link_libc = true;

    // Every C compile for Android needs the NDK's bionic; see build/android.zig.
    const ndk: ?android.Ndk = if (android.isAndroid(target)) android.toolchain(b, target).ndk else null;
    if (ndk) |n| n.apply(engine_lib);

    // SDL3 (windowing, input, clipboard). The `sdl3` module carries the
    // static libSDL3 with it, so importing it is all a consumer needs.
    pixeng.addImport("sdl3", sdlModule(b, target, optimize));

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
    if (ndk) |n| n.apply(zflecs_lib);
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
    if (ndk) |n| n.apply(miniaudio);
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
    if (ndk) |n| n.apply(lua_lib);
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
        const em_inc = std.fs.path.join(b.allocator, &.{ emSysroot(b), "include" }) catch @panic("OOM");
        stbtt_translate.addIncludePath(.{ .cwd_relative = em_inc });
    }

    const stbtt = b.addModule("stb_truetype", .{ .root_source_file = b.path("libs/stb_truetype/stb_truetype.zig") });
    stbtt.addImport("c", if (ndk) |n|
        n.translateC(b, b.path("libs/stb_truetype/stb_truetype.h"), &.{b.path("libs/stb_truetype")}, &.{})
    else
        stbtt_translate.createModule());
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
        const em_inc = std.fs.path.join(b.allocator, &.{ emSysroot(b), "include" }) catch @panic("OOM");
        time_c_translate.addIncludePath(.{ .cwd_relative = em_inc });
    }
    pixeng.addImport("c_time", if (ndk) |n|
        n.translateC(b, b.path("src/pixzig/time_c.h"), &.{}, &.{})
    else
        time_c_translate.createModule());

    // The renderer's default font. `buildGame` replaces this import when a
    // game picks a different `default_font`.
    pixeng.addImport("pixzig_default_font", defaultFontModule(b, b.path(karla_path)));

    // Where relative asset paths resolve. `buildGame` replaces this import
    // so a downstream game points at its own source tree.
    pixeng.addImport("pixzig_asset_base", assetBaseModule(b, devAssetBase(b, target, is_package)));

    // Install the engine library
    if (target.result.os.tag != .emscripten and !android.isAndroid(target)) {
        b.installArtifact(engine_lib);
    }

    return .{ .engine_lib = engine_lib, .pixeng_mod = pixeng };
}

/// Builds `libpixzig_ffi`, a dynamic library exposing the flat C ABI defined
/// in `src/pixzig/c_api.zig`, for use from Python (or any other C-caller).
/// Only registered under the opt-in `python-ffi` step, never part of the
/// default build. Desktop targets only; there's no C-caller for a wasm
/// shared library in this project.
fn buildPythonFfi(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pixeng_mod: *std.Build.Module,
) void {
    if (target.result.os.tag == .emscripten or android.isAndroid(target)) return;

    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("src/pixzig/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_mod.addImport("pixzig", pixeng_mod);

    const ffi_lib = b.addLibrary(.{
        .name = "pixzig_ffi",
        .root_module = ffi_mod,
        .linkage = .dynamic,
    });
    ffi_lib.root_module.link_libc = true;

    // Same native libraries linked into the static engine lib in
    // buildEngine, re-linked here since a dynamic library is a separate
    // Compile step with its own link inputs. SDL3 is absent from this list
    // because the `sdl3` module links libSDL3 itself, so it comes along
    // with the engine module import above.
    const zflecs = b.dependency("zflecs", .{ .target = target });
    ffi_lib.root_module.linkLibrary(zflecs.artifact("flecs"));

    const zaudio = b.dependency("zaudio", .{ .target = target });
    ffi_lib.root_module.linkLibrary(zaudio.artifact("miniaudio"));

    const ziglua = b.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
    ffi_lib.root_module.linkLibrary(ziglua.artifact("lua"));

    const install_ffi = b.addInstallArtifact(ffi_lib, .{
        .dest_dir = .{ .override = .{ .custom = "python" } },
    });

    const python_ffi_step = b.step("python-ffi", "Build the pixzig C FFI shared library for Python bindings");
    python_ffi_step.dependOn(&install_ffi.step);
}

/// Builds the desktop-only unit test runner. It skips `buildExample`'s
/// pixzig root wrapper (whose panic and log handlers only differ from the
/// defaults on emscripten) and uses testz's instead, which installs a panic
/// handler that still prints while a test's output is being captured.
/// tests/main.zig forwards `pixzig.internal.system.std_options` itself.
fn buildTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pixeng_mod: *std.Build.Module,
    is_package: bool,
) *std.Build.Step.InstallArtifact {
    const name = "tests";
    const tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_mod.addImport("pixzig", pixeng_mod);
    // The unit tests reach past the engine's own input enums to check they
    // map SDL's codes correctly. Examples deliberately get no such import:
    // game code should never name SDL.
    tests_mod.addImport("sdl3", sdlModule(b, target, optimize));

    const tests_exe = testz.addTestExe(b, .{
        .target = target,
        .optimize = optimize,
        // Forward the target/optimize through: testz builds tree-sitter C
        // sources behind its `highlight_ansi` module, and without this they
        // compile for the host and the cross-linker rejects the host object
        // files ("lld-link: unknown file type").
        .testz_dep = b.dependency("testz", .{ .target = target, .optimize = optimize }),
        .name = name,
        .root_module = tests_mod,
    });

    const manifest = manifestFromDef(b, .{
        .assets = &.{
            .{ .id = "Roboto-Medium", .kind = "font", .path = "Roboto-Medium.ttf", .font_size = 20.0 },
        },
    });
    manifest.addToModule(tests_exe, tests_mod, is_package, assets_dir);

    const out_path = b.pathJoin(&.{ "bin", name });
    const install_tests = b.addInstallArtifact(tests_exe, .{ .dest_dir = .{ .override = .{ .custom = out_path } } });

    const run_cmd = b.addRunArtifact(tests_exe);
    if (is_package) {
        run_cmd.setCwd(.{ .cwd_relative = b.pathJoin(&.{ "zig-out", out_path }) });
    } else {
        run_cmd.setCwd(b.path("."));
    }
    run_cmd.step.dependOn(&install_tests.step);
    run_cmd.addPassthruArgs();

    const run_step = b.step(name, "Run the unit tests");
    run_step.dependOn(&run_cmd.step);

    return install_tests;
}

/// Which font `buildGame` embeds into the game as the renderer's default.
pub const DefaultFont = union(enum) {
    /// pixzig's bundled Karla-Regular.
    karla,
    /// Embed no font at all. The renderer starts without a default font
    /// unless the game passes one through `renderInitOpts.font`.
    none,
    /// Embed this TTF/OTF file instead of Karla.
    path: std.Build.LazyPath,
};

/// Options for `buildGame`.
pub const BuildGameOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// The pixzig dependency, e.g. `b.dependency("pixzig", .{ .target = target })`.
    engine_dep: *std.Build.Dependency,
    /// The executable's name; also the name of its run step.
    name: []const u8,
    /// The game's root module. Set this or `root_source_file`, not both.
    /// Use a module when the game needs its own imports.
    root_module: ?*std.Build.Module = null,
    /// Shortcut for the common case: the game's `main.zig`. `buildGame`
    /// makes the module from it with `target` and `optimize`.
    root_source_file: ?std.Build.LazyPath = null,
    manifest: ManifestHandle,
    /// Font embedded as the renderer's default (`renderInitOpts.font = .embedded`).
    default_font: DefaultFont = .karla,
    /// Package assets next to the executable. Null reads the `-Dpackage`
    /// build option instead (declared once, however many games share it).
    package: ?bool = null,
    /// Install the executable to `zig-out/bin/<name>/` as part of
    /// `zig build`/`zig build install`, next to the assets a package build
    /// copies there. Native only; web builds always emit to `zig-out/web/`.
    install: bool = true,
    /// Generate a tiny executable root module that installs Pixzig's panic
    /// and log handlers, then delegates to `root_module.main`. Leave this on
    /// unless your root module deliberately provides its own `panic` or
    /// `std_options`.
    wrap_root: bool = true,
};

const karla_path = "src/pixzig/assets/Karla-Regular.ttf";

/// Builds the `pixzig_asset_base` module: a single
/// `pub const dir: ?[]const u8`, the directory relative asset paths resolve
/// against. Null means "use the executable's own directory"
/// (`SDL_GetBasePath`), which is what a packaged build wants.
fn assetBaseModule(b: *std.Build, dir: ?[]const u8) *std.Build.Module {
    const files = b.addWriteFiles();
    const src = if (dir) |d|
        b.fmt("pub const dir: ?[]const u8 = \"{f}\";\n", .{std.zig.fmtString(d)})
    else
        "pub const dir: ?[]const u8 = null;\n";
    return b.createModule(.{ .root_source_file = files.add("asset_base.zig", src) });
}

/// The asset base directory for a dev build: the build root, so a freshly
/// built example reads (and hot-reloads) the assets in the source tree
/// rather than a copy. Package builds and web builds get null, which falls
/// back to the executable's own directory / the Emscripten VFS root.
fn devAssetBase(b: *std.Build, target: std.Build.ResolvedTarget, is_package: bool) ?[]const u8 {
    if (is_package) return null;
    if (target.result.os.tag == .emscripten) return null;
    // Android reads assets out of the APK by relative path.
    if (android.isAndroid(target)) return null;
    return fromRoot(b, ".");
}

/// Builds the `pixzig_default_font` module: a single
/// `pub const data: ?[]const u8`, the embedded font bytes or null.
fn defaultFontModule(b: *std.Build, font: ?std.Build.LazyPath) *std.Build.Module {
    const files = b.addWriteFiles();
    const root = if (font) |f| blk: {
        _ = files.addCopyFile(f, "default_font.ttf");
        break :blk files.add("default_font.zig", "pub const data: ?[]const u8 = @embedFile(\"default_font.ttf\");\n");
    } else files.add("default_font.zig", "pub const data: ?[]const u8 = null;\n");
    return b.createModule(.{ .root_source_file = root });
}

/// The `default_font` the first `buildGame` call chose. Every game in a build
/// graph shares the one engine module, so they all share its default font too.
var chosen_default_font: ?DefaultFont = null;

fn sameDefaultFont(a: DefaultFont, b: DefaultFont) bool {
    return switch (a) {
        .karla => b == .karla,
        .none => b == .none,
        .path => |pa| switch (b) {
            .path => |pb| pa == .src_path and pb == .src_path and
                pa.src_path.owner == pb.src_path.owner and
                std.mem.eql(u8, pa.src_path.sub_path, pb.src_path.sub_path),
            else => false,
        },
    };
}

/// The builder that declared `-Dpackage` through `buildGame`, and its value.
/// `b.option` panics if the same option is declared twice on one builder, so
/// a second `buildGame` call (a game plus an editor) reuses the first read.
var package_option_owner: ?*std.Build = null;
var package_option_value: bool = false;

fn packageOption(b: *std.Build) bool {
    if (package_option_owner != b) {
        package_option_value = b.option(bool, "package", "Package assets to the output directory") orelse false;
        package_option_owner = b;
    }
    return package_option_value;
}

/// Builds a game executable against the pixzig dependency, wiring in the
/// engine, its asset manifest and its embedded default font, plus a run
/// step named after the game.
pub fn buildGame(b: *std.Build, opts: BuildGameOptions) *std.Build.Step.Compile {
    const engine_mod = opts.engine_dep.module("pixzig");

    if (chosen_default_font) |prev| {
        if (!sameDefaultFont(prev, opts.default_font)) {
            @panic("buildGame: every game in one build must use the same default_font (they share the pixzig engine module)");
        }
    } else {
        chosen_default_font = opts.default_font;
        // The engine module ships with Karla wired in (see buildEngine);
        // swap the import only when the game asks for something else.
        switch (opts.default_font) {
            .karla => {},
            .none => engine_mod.addImport("pixzig_default_font", defaultFontModule(b, null)),
            .path => |p| engine_mod.addImport("pixzig_default_font", defaultFontModule(b, p)),
        }
    }

    const engine_obj: ?std.Build.LazyPath = if (opts.target.result.os.tag == .emscripten)
        opts.engine_dep.namedLazyPath("pixzig_obj")
    else
        null;

    const root_module = if (opts.root_module) |m| blk: {
        if (opts.root_source_file != null) @panic("buildGame: set root_module or root_source_file, not both");
        break :blk m;
    } else if (opts.root_source_file) |src|
        b.createModule(.{ .root_source_file = src, .target = opts.target, .optimize = opts.optimize })
    else
        @panic("buildGame: set root_module or root_source_file");

    const is_package = opts.package orelse packageOption(b);

    // Relative asset paths resolve against the game's own source tree in dev
    // builds (so hot-reload watches the real files) and against the
    // executable's directory once packaged. The engine module is shared, so
    // like `default_font` this is one setting for every game in a build.
    engine_mod.addImport(
        "pixzig_asset_base",
        assetBaseModule(b, devAssetBase(b, opts.target, is_package)),
    );

    const exe = buildExample(b, opts.target, opts.optimize, engine_obj, engine_mod, opts.name, root_module, opts.manifest, is_package, opts.wrap_root);

    if (opts.install and opts.target.result.os.tag != .emscripten) {
        const install_exe = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = b.pathJoin(&.{ "bin", opts.name }) } },
        });
        b.getInstallStep().dependOn(&install_exe.step);
    }

    return exe;
}

fn wrappedRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pixeng_mod: *std.Build.Module,
    game_mod: *std.Build.Module,
    name: []const u8,
) *std.Build.Module {
    const files = b.addWriteFiles();
    const root = files.add(b.fmt("{s}_pixzig_root.zig", .{name}),
        \\const std = @import("std");
        \\const pixzig = @import("pixzig");
        \\const game = @import("pixzig_game");
        \\
        \\pub const panic = pixzig.internal.system.panic;
        \\pub const std_options = pixzig.internal.system.std_options;
        \\
        \\pub fn main(init: std.process.Init) !void {
        \\    const main_info = @typeInfo(@TypeOf(game.main)).@"fn";
        \\    if (main_info.param_types.len > 1) {
        \\        @compileError("pixzig root wrapper supports game.main() or game.main(std.process.Init)");
        \\    }
        \\    const Return = main_info.return_type orelse
        \\        @compileError("pixzig root wrapper does not support noreturn game.main");
        \\    if (main_info.param_types.len == 0) {
        \\        switch (@typeInfo(Return)) {
        \\            .error_union => try game.main(),
        \\            .void => game.main(),
        \\            else => @compileError("pixzig root wrapper supports game.main returning void or !void"),
        \\        }
        \\    } else {
        \\        switch (@typeInfo(Return)) {
        \\            .error_union => try game.main(init),
        \\            .void => game.main(init),
        \\            else => @compileError("pixzig root wrapper supports game.main returning void or !void"),
        \\        }
        \\    }
        \\}
        \\
        \\// On Android there is no process entry point: SDLActivity loads
        \\// libmain.so and calls its SDL_main, which runs `main` above.
        \\comptime {
        \\    if (@import("builtin").abi.isAndroid()) {
        \\        @export(&pixzig.internal.android_main.Entry(main).sdlMain, .{ .name = "SDL_main" });
        \\    }
        \\}
        \\
    );

    const root_mod = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("pixzig", pixeng_mod);
    root_mod.addImport("pixzig_game", game_mod);
    return root_mod;
}

/// The Android half of `buildExample`: links `libmain.so` against the NDK and
/// packages it with `libSDL3.so`, SDL's Java glue and the `assets/`
/// directory into `zig-out/android/<name>.apk`. The `<name>_apk` step only
/// builds the APK; the `<name>` step also installs it on the connected device
/// (or emulator) with `adb` and launches it.
fn addAndroidApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    lib: *std.Build.Step.Compile,
    exe_mod: *std.Build.Module,
    pixeng_mod: *std.Build.Module,
    name: []const u8,
    manifest: ManifestHandle,
) void {
    const tc = android.toolchain(b, target);
    tc.ndk.apply(lib);
    lib.link_z_max_page_size = 16 * 1024;
    lib.root_module.link_libc = true;
    // std.log goes to logcat through liblog (see system.zig).
    lib.root_module.linkSystemLibrary("log", .{});

    // The engine's own build is where pixzig's tools and SDL live, so reach
    // them through the engine module's builder: for a downstream game
    // (`buildGame`) that's the pixzig dependency, not the game.
    const engine_b = pixeng_mod.owner;
    const extra = manifest.addToAndroidModule(exe_mod);

    const sdl = android_sdl orelse @panic("addAndroidApp: the engine's sdl3 module was not built for Android");

    const apkpack = apkpack_tool orelse blk: {
        const tool = engine_b.addExecutable(.{
            .name = "apkpack",
            .root_module = engine_b.createModule(.{
                .root_source_file = engine_b.path("tools/apkpack/apkpack.zig"),
                .target = engine_b.graph.host,
            }),
        });
        apkpack_tool = tool;
        break :blk tool;
    };

    const has_assets = blk: {
        var dir = b.root.openDir(b.graph.io, assets_dir, .{}) catch break :blk false;
        dir.close(b.graph.io);
        break :blk true;
    };

    const apk = android.addApk(b, tc, .{
        .name = name,
        .app_id = b.fmt("org.pixzig.{s}", .{name}),
        .main_lib = lib,
        .sdl_lib = sdl.lib,
        .java_dir = sdl.java_dir,
        .assets_dir = if (has_assets) b.path(assets_dir) else null,
        .extra_assets = extra,
        .icon = engine_b.path("src/pixzig/assets/pixzig_icon.png"),
        .apkpack = apkpack,
    });
    b.getInstallStep().dependOn(&apk.install.step);

    const apk_step = b.step(b.fmt("{s}_apk", .{name}), "Build the APK into zig-out/android/ without installing it");
    apk_step.dependOn(&apk.install.step);

    const run_step = b.step(name, "Install the APK on the connected Android device and launch it");
    run_step.dependOn(&apk.install.step);
    run_step.dependOn(&apk.run.step);
}

pub fn buildExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// The engine object emcc links on web builds; ignored on native, where
    /// the engine comes in through `pixeng_mod`.
    engine_obj: ?std.Build.LazyPath,
    pixeng_mod: *std.Build.Module,
    name: []const u8,
    exe_mod: *std.Build.Module,
    manifest: ManifestHandle,
    is_package: bool,
    wrap_root: bool,
) *std.Build.Step.Compile {
    exe_mod.addImport("pixzig", pixeng_mod);
    const root_mod = if (wrap_root)
        wrappedRootModule(b, target, optimize, pixeng_mod, exe_mod, name)
    else
        exe_mod;

    if (android.isAndroid(target) and !wrap_root) {
        @panic("buildExample: Android builds need wrap_root, which provides the SDL_main SDLActivity calls");
    }

    const exe = blk: {
        if (target.result.os.tag == .emscripten) {
            break :blk b.addLibrary(.{
                .name = name,
                .root_module = root_mod,
                .linkage = .static,
            });
        } else if (android.isAndroid(target)) {
            // `SDLActivity` loads the game as `libmain.so`.
            break :blk b.addLibrary(.{
                .name = "main",
                .root_module = root_mod,
                .linkage = .dynamic,
            });
        } else {
            break :blk b.addExecutable(.{
                .name = name,
                .root_module = root_mod,
            });
        }
    };

    if (android.isAndroid(target)) {
        addAndroidApp(b, target, exe, exe_mod, pixeng_mod, name, manifest);
        return exe;
    }

    // Handle platform-specific linking
    switch (target.result.os.tag) {
        .emscripten => {
            const path = b.pathJoin(&.{ "zig-out", "web", name });
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
                // Emscripten's own SDL3 port supplies the implementation the
                // engine's `sdl3` module only declares (see `sdlModule`).
                "--use-port=sdl3",
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
            });
            // Zig 0.17 removed LazyPath.getPath; addFileArg resolves the
            // path at make time and passes it as its own argument. The shell
            // ships with the engine, so resolve it against the engine's
            // builder; `b` is the game's when called through `buildGame`.
            emcc_command.addArg("--shell-file");
            emcc_command.addFileArg(pixeng_mod.owner.path("src/shell.html"));

            // Preload assets: use explicit file list when available, else whole dir.
            if (manifest.emcc_files.len > 0) {
                for (manifest.emcc_files) |asset| {
                    emcc_command.addArgs(&[_][]const u8{ "--preload-file", b.pathJoin(&.{ assets_dir, asset }) });
                }
            } else {
                emcc_command.addArgs(&[_][]const u8{ "--preload-file", b.fmt("{s}@/{s}", .{ assets_dir, assets_dir }) });
            }
            manifest.addToWebModule(exe, exe_mod, emcc_command);

            emcc_command.addFileArg(exe.getEmittedBin());
            emcc_command.addFileArg(engine_obj orelse
                @panic("buildExample: web builds need the engine object (engine_obj)"));

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
            manifest.addToModule(exe, exe_mod, is_package, assets_dir);

            const install_ex = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = out_path } } });

            const run_cmd = b.addRunArtifact(exe);
            if (is_package) {
                // Package mode: exe runs from install dir where assets were copied.
                run_cmd.setCwd(.{ .cwd_relative = b.pathJoin(&.{ "zig-out", out_path }) });
            } else {
                // Dev mode: exe runs from repo root so it can read assets in-place.
                run_cmd.setCwd(b.path("."));
            }
            run_cmd.step.dependOn(&install_ex.step);

            run_cmd.addPassthruArgs();

            const run_step = b.step(name, "Run example");
            run_step.dependOn(&run_cmd.step);
        },
    }

    return exe;
}
