//! Android build support: finding the SDK and NDK, compiling SDL3 for
//! Android, and packaging a game's `libmain.so` into a signed APK.
//!
//! `zig build <example> -Dtarget=aarch64-linux-android` builds
//! `zig-out/android/<example>.apk`, installs it with `adb` and launches it,
//! the same way `zig build <example>` runs a desktop build. `-Dtarget=
//! x86_64-linux-android` builds for the emulator instead. One APK carries
//! one ABI.
//!
//! **No Gradle.** An APK is a zip of a binary manifest, compiled resources,
//! `classes.dex`, native libraries and assets, signed. The SDK's own tools
//! make each piece: `aapt2` links the manifest, icon and `assets/` into a
//! base APK, `javac` + `d8` turn SDL's Java glue (`SDLActivity` and
//! friends, from the SDL source tree already pinned for desktop) into
//! `classes.dex`, `tools/apkpack` adds the dex and the `.so` files with the
//! alignment Android wants, and `apksigner` signs it with the debug key.
//! That keeps a downstream game (`buildGame`) on plain `zig build` with no
//! Android project to copy around.
//!
//! **Why the NDK is needed.** SDL, Lua, flecs, miniaudio and stb are C, C
//! needs a libc, and Zig ships glibc and musl but not Android's bionic. So
//! every C compile points Zig at the NDK sysroot with a generated libc paths
//! file (`Ndk.apply`). Zig hands clang an unversioned triple, and the NDK's
//! `sys/cdefs.h` refuses to compile without the API level a versioned one
//! would define, so `apply` also defines `__ANDROID_API__`.
//!
//! **SDL as a shared library.** `SDLActivity` loads `libSDL3.so` and then
//! `libmain.so` and calls the latter's `SDL_main`. Linking SDL statically
//! into `libmain.so` would drop its JNI entry points (nothing in the game
//! references `JNI_OnLoad` or the `Java_org_libsdl_app_*` natives, so the
//! linker leaves those objects out), so SDL stays its own `.so`, the way
//! SDL's own Android template builds it.

const std = @import("std");

/// The Android API level built against when `-Dandroid_api` isn't given:
/// Android 8.0, the first with AAudio, which miniaudio and SDL prefer.
pub const default_api_level: u32 = 26;

/// The `targetSdkVersion` written into the manifest when
/// `-Dandroid_target_sdk` isn't given.
pub const default_target_sdk: u32 = 35;

/// The `android-<n>` platform `android.jar` is compiled against: the newest
/// one installed, so SDL's Java (which names APIs up to its own target)
/// always resolves.
pub const Sdk = struct {
    sdk_dir: []const u8,
    build_tools_dir: []const u8,
    android_jar: []const u8,
    target_sdk: u32,
    keystore: []const u8,

    pub fn tool(self: Sdk, b: *std.Build, name: []const u8) []const u8 {
        return b.pathJoin(&.{ self.build_tools_dir, name });
    }
};

/// The NDK pieces one Android target's C compiles and links need.
pub const Ndk = struct {
    ndk_dir: []const u8,
    sysroot: []const u8,
    api_level: u32,
    /// Bionic's per-API `libc.so`, `crtbegin_so.o` and the system
    /// libraries (`liblog`, `libEGL`, ...).
    lib_dir: []const u8,
    /// The API-independent static libraries (`libc++_static.a`, ...).
    static_lib_dir: []const u8,
    libc_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,

    /// Points `compile` at bionic: the libc paths file, the system library
    /// directory and the API level macro the NDK headers insist on.
    pub fn apply(self: Ndk, compile: *std.Build.Step.Compile) void {
        compile.setLibCFile(self.libc_file);
        self.applyModule(compile.root_module);
    }

    /// The module half of `apply`, for a module whose C sources compile into
    /// some other artifact.
    pub fn applyModule(self: Ndk, mod: *std.Build.Module) void {
        const b = mod.owner;
        mod.addLibraryPath(.{ .cwd_relative = self.lib_dir });
        mod.addCMacro("__ANDROID_API__", b.fmt("{d}", .{self.api_level}));
        mod.addCMacro("__ANDROID_MIN_SDK_VERSION__", b.fmt("{d}", .{self.api_level}));
    }

    /// Translates `header` for Android against the NDK's headers. A Run step
    /// rather than `addTranslateC`, because `TranslateC` has no libc-file
    /// option and without one falls back to the host's glibc headers.
    pub fn translateC(
        self: Ndk,
        b: *std.Build,
        header: std.Build.LazyPath,
        include_dirs: []const std.Build.LazyPath,
        defines: []const []const u8,
    ) *std.Build.Module {
        const run = b.addSystemCommand(&.{ b.graph.zig_exe, "translate-c" });
        run.addArgs(&.{ "-target", self.triple(b), "-lc", "--libc" });
        run.addFileArg(self.libc_file);
        run.addArg(b.fmt("-D__ANDROID_API__={d}", .{self.api_level}));
        run.addArg(b.fmt("-D__ANDROID_MIN_SDK_VERSION__={d}", .{self.api_level}));
        // Bionic's <limits.h> does an `#include_next <limits.h>`, and
        // translate-c's search path continues on to the host's
        // /usr/include, whose glibc copy then fails on glibc-only macros.
        // Predefining glibc's include guard, and its `__GLIBC_USE` for the
        // parts outside the guard, makes that copy a no-op; bionic defines
        // everything itself.
        run.addArg("-D_LIBC_LIMITS_H_");
        run.addArg("-D__GLIBC_USE(F)=0");
        for (defines) |d| run.addArg(d);
        for (include_dirs) |dir| run.addPrefixedDirectoryArg("-I", dir);
        run.addFileArg(header);
        return b.createModule(.{ .root_source_file = run.captureStdOut(.{ .basename = "translated.zig" }) });
    }

    /// The versioned Zig triple, e.g. `aarch64-linux-android.26`.
    pub fn triple(self: Ndk, b: *std.Build) []const u8 {
        return b.fmt("{s}-linux-android.{d}", .{ @tagName(self.target.result.cpu.arch), self.api_level });
    }

    /// The ABI directory name an APK keeps this target's libraries under.
    pub fn abiName(self: Ndk) []const u8 {
        return abiDirName(self.target.result.cpu.arch);
    }
};

/// The APK's `lib/<abi>/` directory name for `arch`.
pub fn abiDirName(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .aarch64 => "arm64-v8a",
        .x86_64 => "x86_64",
        .arm => "armeabi-v7a",
        .x86 => "x86",
        else => @panic("pixzig: unsupported Android architecture"),
    };
}

/// The NDK's name for `arch` in its sysroot library directories.
fn ndkArchTriple(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .aarch64 => "aarch64-linux-android",
        .x86_64 => "x86_64-linux-android",
        .arm => "arm-linux-androideabi",
        .x86 => "i686-linux-android",
        else => @panic("pixzig: unsupported Android architecture"),
    };
}

pub fn isAndroid(target: std.Build.ResolvedTarget) bool {
    return target.result.abi.isAndroid();
}

/// Everything an Android build needs, found once per build graph.
pub const Toolchain = struct {
    sdk: Sdk,
    ndk: Ndk,
};

var toolchain_memo: ?Toolchain = null;

/// Finds the SDK and NDK for `target`. The SDK comes from `-Dandroid_sdk`,
/// else `$ANDROID_HOME`/`$ANDROID_SDK_ROOT`, else `~/Android/Sdk`; the NDK
/// from `-Dandroid_ndk`, else `$ANDROID_NDK_HOME`, else the newest under the
/// SDK's `ndk/`. Panics with what's missing, since nothing Android can build
/// without them. The API level is the target's (`aarch64-linux-android.28`)
/// when it names one, else `-Dandroid_api`, else `default_api_level`.
pub fn toolchain(b: *std.Build, target: std.Build.ResolvedTarget) Toolchain {
    if (toolchain_memo) |t| return t;

    const env = b.graph.environ_map;
    const sdk_opt = b.option([]const u8, "android_sdk", "Android SDK directory (default: $ANDROID_HOME, then ~/Android/Sdk)");
    const ndk_opt = b.option([]const u8, "android_ndk", "Android NDK directory (default: $ANDROID_NDK_HOME, then the newest under the SDK)");
    const api_opt = b.option(u32, "android_api", b.fmt("Android API level (minSdkVersion) to build for (default {d})", .{default_api_level}));
    const target_sdk_opt = b.option(u32, "android_target_sdk", b.fmt("targetSdkVersion written to the APK manifest (default {d})", .{default_target_sdk}));
    const keystore_opt = b.option([]const u8, "android_keystore", "Keystore the APK is signed with (default ~/.android/debug.keystore)");

    const home = env.get("HOME") orelse "";
    const sdk_dir = sdk_opt orelse env.get("ANDROID_HOME") orelse env.get("ANDROID_SDK_ROOT") orelse
        b.pathJoin(&.{ home, "Android", "Sdk" });
    if (!dirExists(b, sdk_dir)) {
        std.debug.panic("pixzig: no Android SDK at {s}; pass -Dandroid_sdk=<dir> or set ANDROID_HOME", .{sdk_dir});
    }

    const ndk_dir = ndk_opt orelse env.get("ANDROID_NDK_HOME") orelse
        newestSubdir(b, b.pathJoin(&.{ sdk_dir, "ndk" })) orelse
        std.debug.panic("pixzig: no Android NDK found; pass -Dandroid_ndk=<dir> or set ANDROID_NDK_HOME", .{});

    const build_tools_dir = newestSubdir(b, b.pathJoin(&.{ sdk_dir, "build-tools" })) orelse
        std.debug.panic("pixzig: no build-tools under {s}; install them with the SDK manager", .{sdk_dir});
    const platform_dir = newestSubdir(b, b.pathJoin(&.{ sdk_dir, "platforms" })) orelse
        std.debug.panic("pixzig: no platforms under {s}; install one with the SDK manager", .{sdk_dir});

    // A triple that names an API level (`aarch64-linux-android.28`) wins
    // over the option.
    const api_level: u32 = if (target.query.android_api_level) |lvl| lvl else api_opt orelse default_api_level;

    const arch = target.result.cpu.arch;
    const sysroot = b.pathJoin(&.{ ndk_dir, "toolchains", "llvm", "prebuilt", "linux-x86_64", "sysroot" });
    const static_lib_dir = b.pathJoin(&.{ sysroot, "usr", "lib", ndkArchTriple(arch) });
    const lib_dir = b.pathJoin(&.{ static_lib_dir, b.fmt("{d}", .{api_level}) });
    if (!dirExists(b, lib_dir)) {
        std.debug.panic("pixzig: the NDK at {s} has no API {d} libraries for {s}", .{ ndk_dir, api_level, ndkArchTriple(arch) });
    }

    // Zig 0.17 wants every field present, and `cc_dir` non-empty on Linux;
    // the NDK keeps its crtbegin objects beside libc.
    const libc_contents = b.fmt(
        \\include_dir={s}
        \\sys_include_dir={s}
        \\crt_dir={s}
        \\cc_dir={s}
        \\msvc_lib_dir=
        \\kernel32_lib_dir=
        \\darwin_sdk_dir=
        \\
    , .{
        b.pathJoin(&.{ sysroot, "usr", "include" }),
        b.pathJoin(&.{ sysroot, "usr", "include", ndkArchTriple(arch) }),
        lib_dir,
        lib_dir,
    });
    const files = b.addWriteFiles();

    // The resolved target with the API level filled in, so Zig links
    // against the same bionic the headers describe.
    var query = target.query;
    query.android_api_level = api_level;

    const t: Toolchain = .{
        .sdk = .{
            .sdk_dir = sdk_dir,
            .build_tools_dir = build_tools_dir,
            .android_jar = b.pathJoin(&.{ platform_dir, "android.jar" }),
            .target_sdk = target_sdk_opt orelse default_target_sdk,
            .keystore = keystore_opt orelse b.pathJoin(&.{ home, ".android", "debug.keystore" }),
        },
        .ndk = .{
            .ndk_dir = ndk_dir,
            .sysroot = sysroot,
            .api_level = api_level,
            .lib_dir = lib_dir,
            .static_lib_dir = static_lib_dir,
            .libc_file = files.add("ndk-libc.txt", libc_contents),
            .target = b.resolveTargetQuery(query),
        },
    };
    toolchain_memo = t;
    return t;
}

fn dirExists(b: *std.Build, path: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(b.graph.io, path, .{}) catch return false;
    dir.close(b.graph.io);
    return true;
}

/// The subdirectory of `parent` whose name sorts last as a version
/// (`36.0.0` after `35.0.1`, `android-37` after `android-36`), or null when
/// there is none.
fn newestSubdir(b: *std.Build, parent: []const u8) ?[]const u8 {
    const io = b.graph.io;
    var dir = std.Io.Dir.cwd().openDir(io, parent, .{ .iterate = true }) catch return null;
    defer dir.close(io);
    var best: ?[]const u8 = null;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .directory) continue;
        if (best == null or versionLess(best.?, entry.name)) best = b.dupe(entry.name);
    }
    return if (best) |name| b.pathJoin(&.{ parent, name }) else null;
}

/// Compares two names as dotted/dashed version strings, numerically where
/// both pieces are numbers.
fn versionLess(a: []const u8, b: []const u8) bool {
    var ia = std.mem.tokenizeAny(u8, a, ".-_");
    var ib = std.mem.tokenizeAny(u8, b, ".-_");
    while (true) {
        const pa = ia.next() orelse return ib.peek() != null;
        const pb = ib.next() orelse return false;
        const na = std.fmt.parseInt(u64, pa, 10) catch null;
        const nb = std.fmt.parseInt(u64, pb, 10) catch null;
        if (na != null and nb != null) {
            if (na.? != nb.?) return na.? < nb.?;
        } else {
            const order = std.mem.order(u8, pa, pb);
            if (order != .eq) return order == .lt;
        }
    }
}

// ---------------------------------------------------------------------------
// SDL3
// ---------------------------------------------------------------------------

/// The SDL source directories `Android.mk` compiles, wildcard for wildcard.
/// Kept in that file's order so the two are easy to compare on an SDL bump.
const sdl_source_dirs = [_][]const u8{
    "",
    "audio",
    "audio/android",
    "audio/dummy",
    "audio/aaudio",
    "audio/openslES",
    "atomic",
    "camera",
    "camera/android",
    "camera/dummy",
    "core",
    "core/android",
    "cpuinfo",
    "dynapi",
    "events",
    "io",
    "io/generic",
    "gpu",
    "gpu/vulkan",
    "haptic",
    "haptic/android",
    "haptic/dummy",
    "haptic/hidapi",
    "hidapi",
    "joystick",
    "joystick/android",
    "joystick/dummy",
    "joystick/hidapi",
    "joystick/steam",
    "joystick/virtual",
    "loadso/dlopen",
    "locale",
    "locale/android",
    "main",
    "main/generic",
    "misc",
    "misc/android",
    "power",
    "power/android",
    "process",
    "process/dummy",
    "filesystem",
    "filesystem/android",
    "filesystem/posix",
    "sensor",
    "sensor/android",
    "sensor/dummy",
    "render",
    "render/direct3d",
    "render/direct3d11",
    "render/direct3d12",
    "render/gpu",
    "render/metal",
    "render/ngage",
    "render/opengl",
    "render/opengles2",
    "render/ps2",
    "render/psp",
    "render/software",
    "render/vitagxm",
    "render/vulkan",
    "stdlib",
    "storage",
    "storage/generic",
    "thread",
    "thread/pthread",
    "time",
    "time/unix",
    "timer",
    "timer/unix",
    "tray/dummy",
    "tray",
    "video",
    "video/android",
    "video/yuv2rgb",
};

/// `Android.mk` names these individually rather than by wildcard.
const sdl_single_sources = [_][]const u8{
    "dialog/SDL_dialog.c",
    "dialog/SDL_dialog_utils.c",
    "dialog/android/SDL_androiddialog.c",
};

/// The SDL3 module for Android: the SDL headers translated against the NDK,
/// carrying a `libSDL3.so` built from the upstream sources. `sdl_pkg` is the
/// `allyourcodebase/SDL` package, reached with `default_target_config =
/// false` so its own build (which knows no Android) stays out of the way;
/// only its `sdl.h` and its upstream source dependency are used.
pub fn sdlModule(b: *std.Build, ndk: Ndk, optimize: std.builtin.OptimizeMode, sdl_pkg: *std.Build.Dependency) struct { module: *std.Build.Module, lib: *std.Build.Step.Compile } {
    const upstream = sdl_pkg.builder.dependency("sdl", .{});

    const lib = sdlLibrary(b, ndk, optimize, upstream);

    const module = ndk.translateC(b, sdl_pkg.path("src/sdl.h"), &.{
        upstream.path("include"),
        upstream.path("src/video/khronos"),
    }, &.{});
    module.linkLibrary(lib);
    return .{ .module = module, .lib = lib };
}

/// The SDL source tree's Java glue, `org/libsdl/app/*.java`.
pub fn sdlJavaDir(sdl_pkg: *std.Build.Dependency) std.Build.LazyPath {
    return sdl_pkg.builder.dependency("sdl", .{}).path("android-project/app/src/main/java");
}

fn sdlLibrary(b: *std.Build, ndk: Ndk, optimize: std.builtin.OptimizeMode, upstream: *std.Build.Dependency) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .name = "SDL3",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .target = ndk.target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    ndk.apply(lib);
    lib.link_z_max_page_size = 16 * 1024;

    const mod = lib.root_module;
    mod.addIncludePath(upstream.path("include"));
    mod.addIncludePath(upstream.path("include/build_config"));
    mod.addIncludePath(upstream.path("src"));
    mod.addIncludePath(upstream.path("src/video/khronos"));
    mod.addCMacro("GL_GLEXT_PROTOTYPES", "1");

    const c_flags: []const []const u8 = &.{
        "-std=gnu11",
        // Zig enables UBSan for C in Debug; SDL isn't written against it,
        // and a trap inside a JNI callback is a silent crash on Android.
        "-fno-sanitize=undefined",
        "-Wno-unused-parameter",
        "-Wno-sign-compare",
    };

    const src_root = upstream.builder.root;
    const io = b.graph.io;
    var sources: std.ArrayList([]const u8) = .empty;
    for (sdl_source_dirs) |sub| {
        const rel = if (sub.len == 0) "src" else b.pathJoin(&.{ "src", sub });
        var dir = src_root.openDir(io, rel, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".c")) continue;
            const path = if (sub.len == 0) b.dupe(entry.name) else b.pathJoin(&.{ sub, entry.name });
            sources.append(b.allocator, path) catch @panic("OOM");
        }
    }
    sources.appendSlice(b.allocator, &sdl_single_sources) catch @panic("OOM");
    // Directory order varies between filesystems; sort so the compile
    // command (and so the cache key) doesn't.
    std.mem.sort([]const u8, sources.items, {}, struct {
        fn lt(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lt);
    mod.addCSourceFiles(.{ .root = upstream.path("src"), .files = sources.items, .flags = c_flags });

    // hidapi's Android backend (USB and Bluetooth controllers through
    // `HIDDeviceManager.java`) is the one C++ file. It uses no C++ library
    // beyond `new`/`delete`, which the NDK's static libc++ supplies.
    mod.addCSourceFile(.{
        .file = upstream.path("src/hidapi/android/hid.cpp"),
        .flags = &.{ "-std=gnu++11", "-fno-exceptions", "-fno-rtti", "-fno-sanitize=undefined", "-nostdinc++" },
    });
    mod.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ ndk.static_lib_dir, "libc++_static.a" }) });
    mod.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ ndk.static_lib_dir, "libc++abi.a" }) });

    for ([_][]const u8{ "dl", "GLESv1_CM", "GLESv2", "OpenSLES", "log", "android" }) |name| {
        mod.linkSystemLibrary(name, .{});
    }
    return lib;
}

// ---------------------------------------------------------------------------
// APK packaging
// ---------------------------------------------------------------------------

/// What `addApk` needs to know about one game.
pub const ApkOptions = struct {
    /// The game's name: the APK file name and the default label.
    name: []const u8,
    /// The Java-style application id, e.g. `org.pixzig.render_ex`.
    app_id: []const u8,
    /// The launcher label. Defaults to `name`.
    label: ?[]const u8 = null,
    version_name: []const u8 = "1.0",
    version_code: u32 = 1,
    /// The game's `libmain.so`.
    main_lib: *std.Build.Step.Compile,
    sdl_lib: *std.Build.Step.Compile,
    /// SDL's Java sources (`sdlJavaDir`).
    java_dir: std.Build.LazyPath,
    /// Directory packaged as the APK's `assets/assets/`, so the game's
    /// relative `assets/...` paths find it in the APK as they do on disk.
    /// Null for a game with no assets.
    assets_dir: ?std.Build.LazyPath = null,
    /// Extra files packaged under `assets/` at the given path, e.g. a
    /// manifest JSON that lives outside the assets directory.
    extra_assets: []const ExtraAsset = &.{},
    /// The launcher icon, a PNG.
    icon: std.Build.LazyPath,
    /// The `apkpack` host tool (`tools/apkpack`).
    apkpack: *std.Build.Step.Compile,
};

pub const ExtraAsset = struct {
    /// Path inside the APK's `assets/` directory.
    dest: []const u8,
    source: std.Build.LazyPath,
};

/// The steps `addApk` creates.
pub const Apk = struct {
    /// The signed APK.
    file: std.Build.LazyPath,
    /// Installs the APK as `zig-out/android/<name>.apk`.
    install: *std.Build.Step.InstallFile,
    /// `adb install -r` + `am start`, then follows the game's log.
    run: *std.Build.Step.Run,
};

var dex_memo: ?std.Build.LazyPath = null;

/// SDL's Java glue compiled to `classes.dex`. The same for every game in a
/// build, so it's made once.
fn sdlDex(b: *std.Build, tc: Toolchain, java_dir: std.Build.LazyPath) std.Build.LazyPath {
    if (dex_memo) |d| return d;

    // `javac` takes the sources by name, so list them at configure time.
    // `-XDsuppressNotes` silences the "uses a deprecated API" notes SDL's
    // Java always draws; a Run step counts any stderr output as failure.
    const javac = b.addSystemCommand(&.{ "javac", "-nowarn", "-Xlint:none", "-XDsuppressNotes", "-encoding", "UTF-8", "--release", "11" });
    javac.addArgs(&.{ "-classpath", tc.sdk.android_jar });
    javac.addArg("-d");
    const classes = javac.addOutputDirectoryArg("classes");
    const java_root = java_dir.path(b, "org/libsdl/app");
    for (sdl_java_files) |file| javac.addFileArg(java_root.path(b, file));

    const jar = b.addSystemCommand(&.{ "jar", "--create", "--file" });
    const classes_jar = jar.addOutputFileArg("classes.jar");
    jar.addArg("-C");
    jar.addDirectoryArg(classes);
    jar.addArg(".");

    const d8 = b.addSystemCommand(&.{tc.sdk.tool(b, "d8")});
    d8.addArgs(&.{ "--release", "--min-api", b.fmt("{d}", .{tc.ndk.api_level}), "--lib", tc.sdk.android_jar, "--output" });
    const dex_dir = d8.addOutputDirectoryArg("dex");
    d8.addFileArg(classes_jar);

    const dex = dex_dir.path(b, "classes.dex");
    dex_memo = dex;
    return dex;
}

const sdl_java_files = [_][]const u8{
    "HIDDevice.java",
    "HIDDeviceBLESteamController.java",
    "HIDDeviceManager.java",
    "HIDDeviceUSB.java",
    "SDL.java",
    "SDLActivity.java",
    "SDLAudioManager.java",
    "SDLControllerManager.java",
    "SDLDummyEdit.java",
    "SDLInputConnection.java",
    "SDLSensorManager.java",
    "SDLSurface.java",
};

/// Builds, signs and installs one game's APK, and makes the step that runs
/// it on a device.

pub fn addApk(b: *std.Build, tc: Toolchain, opts: ApkOptions) Apk {
    const wf = b.addWriteFiles();
    const manifest = wf.add("AndroidManifest.xml", manifestXml(b, opts));

    // The icon has to go through `aapt2 compile` before `link` takes it.
    _ = wf.addCopyFile(opts.icon, "res/mipmap/ic_launcher.png");
    const res_dir = wf.getDirectory().path(b, "res");
    const compile_res = b.addSystemCommand(&.{ tc.sdk.tool(b, "aapt2"), "compile", "--dir" });
    compile_res.addDirectoryArg(res_dir);
    compile_res.addArg("-o");
    const flat_res = compile_res.addOutputFileArg("res.zip");

    // Assets are staged into one directory so `aapt2 link -A` sees the
    // tree the game's relative paths expect.
    const assets = b.addWriteFiles();
    if (opts.assets_dir) |dir| _ = assets.addCopyDirectory(dir, "assets", .{});
    for (opts.extra_assets) |extra| _ = assets.addCopyFile(extra.source, extra.dest);
    // `aapt2 link -A` fails on a missing directory, so there's always one.
    _ = assets.add(".pixzig", "");

    const link = b.addSystemCommand(&.{ tc.sdk.tool(b, "aapt2"), "link" });
    link.addArgs(&.{ "-I", tc.sdk.android_jar });
    link.addArgs(&.{ "--min-sdk-version", b.fmt("{d}", .{tc.ndk.api_level}) });
    link.addArgs(&.{ "--target-sdk-version", b.fmt("{d}", .{tc.sdk.target_sdk}) });
    link.addArgs(&.{ "--version-code", b.fmt("{d}", .{opts.version_code}) });
    link.addArgs(&.{ "--version-name", opts.version_name });
    link.addArg("--debug-mode");
    link.addArg("--manifest");
    link.addFileArg(manifest);
    link.addArg("-A");
    link.addDirectoryArg(assets.getDirectory());
    // Nothing is compressed: Android 11+ wants `resources.arsc` stored and
    // aligned, SDL can map stored assets straight out of the APK, and the
    // audio and images are already compressed anyway.
    link.addArg("--no-compress");
    link.addArg("-o");
    const base_apk = link.addOutputFileArg("base.apk");
    link.addFileArg(flat_res);

    const pack = b.addRunArtifact(opts.apkpack);
    pack.addFileArg(base_apk);
    const unsigned = pack.addOutputFileArg("unsigned.apk");
    pack.addPrefixedFileArg("classes.dex=", sdlDex(b, tc, opts.java_dir));
    const abi = tc.ndk.abiName();
    pack.addPrefixedFileArg(b.fmt("lib/{s}/libmain.so=", .{abi}), opts.main_lib.getEmittedBin());
    pack.addPrefixedFileArg(b.fmt("lib/{s}/libSDL3.so=", .{abi}), opts.sdl_lib.getEmittedBin());

    // JDK 22+ warns on stderr when apksigner's crypto library loads native
    // code unless that's allowed up front; a Run step counts the warning as
    // failure. `-J` hands the flag to apksigner's JVM, adding the leading dash itself.
    const sign = b.addSystemCommand(&.{ tc.sdk.tool(b, "apksigner"), "-J-enable-native-access=ALL-UNNAMED", "sign" });
    sign.addArgs(&.{ "--ks", tc.sdk.keystore, "--ks-pass", "pass:android", "--key-pass", "pass:android", "--ks-key-alias", "androiddebugkey" });
    sign.addArg("--out");
    const signed = sign.addOutputFileArg(b.fmt("{s}.apk", .{opts.name}));
    sign.addFileArg(unsigned);
    if (!fileExists(b, tc.sdk.keystore)) {
        sign.step.dependOn(&b.addFail(b.fmt(
            "pixzig: no keystore at {s}. Create the debug one with:\n  keytool -genkeypair -keystore {s} -storepass android -keypass android -alias androiddebugkey -dname \"CN=Android Debug,O=Android,C=US\" -keyalg RSA -validity 10000",
            .{ tc.sdk.keystore, tc.sdk.keystore },
        )).step);
    }

    const install = b.addInstallFile(signed, b.fmt("android/{s}.apk", .{opts.name}));

    const adb = b.pathJoin(&.{ tc.sdk.sdk_dir, "platform-tools", "adb" });
    const adb_install = b.addSystemCommand(&.{ adb, "install", "-r" });
    adb_install.addFileArg(signed);
    adb_install.has_side_effects = true;

    const start = b.addSystemCommand(&.{ adb, "shell", "am", "start", "-W", "-S", "-n", b.fmt("{s}/org.libsdl.app.SDLActivity", .{opts.app_id}) });
    start.has_side_effects = true;
    start.step.dependOn(&adb_install.step);

    return .{ .file = signed, .install = install, .run = start };
}

fn fileExists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.cwd().access(b.graph.io, path, .{}) catch return false;
    return true;
}

fn manifestXml(b: *std.Build, opts: ApkOptions) []const u8 {
    // The activity is SDL's own `SDLActivity`: it loads `libSDL3.so` and
    // `libmain.so` (its default `getLibraries()`) and runs `SDL_main`.
    // `configChanges` is SDL's template list, so rotating or plugging in a
    // keyboard resizes the surface instead of restarting the activity.
    // There's no `screenOrientation`: SDL sets the orientation itself when
    // the window is created (`EngineInitOptions.orientation`).
    return b.fmt(
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<manifest xmlns:android="http://schemas.android.com/apk/res/android"
        \\    package="{s}"
        \\    android:installLocation="auto">
        \\    <uses-feature android:glEsVersion="0x00030000" android:required="true" />
        \\    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
        \\    <uses-feature android:name="android.hardware.bluetooth" android:required="false" />
        \\    <uses-feature android:name="android.hardware.gamepad" android:required="false" />
        \\    <uses-feature android:name="android.hardware.usb.host" android:required="false" />
        \\    <uses-feature android:name="android.hardware.type.pc" android:required="false" />
        \\    <uses-permission android:name="android.permission.VIBRATE" />
        \\    <application android:label="{s}"
        \\        android:icon="@mipmap/ic_launcher"
        \\        android:allowBackup="true"
        \\        android:extractNativeLibs="false"
        \\        android:theme="@android:style/Theme.NoTitleBar.Fullscreen"
        \\        android:enableOnBackInvokedCallback="false"
        \\        android:hardwareAccelerated="true">
        \\        <activity android:name="org.libsdl.app.SDLActivity"
        \\            android:label="{s}"
        \\            android:alwaysRetainTaskState="true"
        \\            android:launchMode="singleInstance"
        \\            android:configChanges="layoutDirection|locale|grammaticalGender|fontScale|fontWeightAdjustment|orientation|uiMode|screenLayout|screenSize|smallestScreenSize|keyboard|keyboardHidden|navigation"
        \\            android:preferMinimalPostProcessing="true"
        \\            android:exported="true">
        \\            <intent-filter>
        \\                <action android:name="android.intent.action.MAIN" />
        \\                <category android:name="android.intent.category.LAUNCHER" />
        \\            </intent-filter>
        \\        </activity>
        \\    </application>
        \\</manifest>
        \\
    , .{
        opts.app_id,
        opts.label orelse opts.name,
        opts.label orelse opts.name,
    });
}
