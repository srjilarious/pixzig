const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

pub const Language = enum {
    lua51,
    lua52,
    lua53,
    lua54,
    luajit,
    luau,
};

pub fn configure(b: *Build, mod: *Build.Module, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, lang: Language, shared: bool) *Step.Compile {
    const version = switch (lang) {
        .lua51 => std.SemanticVersion{ .major = 5, .minor = 1, .patch = 5 },
        .lua52 => std.SemanticVersion{ .major = 5, .minor = 2, .patch = 4 },
        .lua53 => std.SemanticVersion{ .major = 5, .minor = 3, .patch = 6 },
        .lua54 => std.SemanticVersion{ .major = 5, .minor = 4, .patch = 6 },
        else => unreachable,
    };

    const lib = if (shared)
        b.addLibrary(.{
            .name = "lua",
            .linkage = .static,
            .version = version,
            .root_module = mod,
        })
    else
        b.addLibrary(.{
            .name = "lua",
            .linkage = .static,
            .version = version,
            .root_module = mod,
        });

    lib.addIncludePath(upstream.path("src"));

    const flags = [_][]const u8{
        // Standard version used in Lua Makefile
        "-std=gnu99",
        // "-DLUA_COMPAT_5_2",

        // Define target-specific macro
        switch (target.result.os.tag) {
            .linux => "-DLUA_USE_LINUX",
            .macos => "-DLUA_USE_MACOSX",
            .windows => "-DLUA_USE_WINDOWS",
            else => "-DLUA_USE_POSIX",
        },

        // Enable api check
        if (optimize == .Debug) "-DLUA_USE_APICHECK" else "",
    };

    const lua_source_files = switch (lang) {
        .lua51 => &lua_base_source_files,
        .lua52 => &lua_52_source_files,
        .lua53 => &lua_53_source_files,
        .lua54 => &lua_54_source_files,
        else => unreachable,
    };

    if (target.result.os.tag != .emscripten) {
        lib.addCSourceFiles(.{
            .root = .{ .dependency = .{
                .dependency = upstream,
                .sub_path = "",
            } },
            .files = lua_source_files,
            .flags = &flags,
        });
    } else {
        for (lua_source_files) |file| {
            const compile_lua = emCompileStep(
                b,
                upstream.path(file),
                optimize,
                &flags,
            );
            lib.addObjectFile(compile_lua);
        }
    }
    lib.linkLibC();

    // unsure why this is necessary, but even with linkLibC() lauxlib.h will fail to find stdio.h
    // lib.installHeader(b.path("src/emscripten/stdio.h"), "stdio.h");

    lib.installHeader(upstream.path("src/lua.h"), "lua.h");
    lib.installHeader(upstream.path("src/lualib.h"), "lualib.h");
    lib.installHeader(upstream.path("src/lauxlib.h"), "lauxlib.h");
    lib.installHeader(upstream.path("src/luaconf.h"), "luaconf.h");

    return lib;
}

pub fn emCompileStep(b: *Build, filename: Build.LazyPath, optimize: std.builtin.OptimizeMode, extra_flags: []const []const u8) Build.LazyPath {
    // const emcc_path = emSdkLazyPath(b, emsdk, &.{ "upstream", "emscripten", "emcc" }).getPath(b);
    // const emcc = b.addSystemCommand(&.{emcc_path});
    const emcc_exe_path = "/usr/lib/emscripten/emcc";
    const emcc = b.addSystemCommand(&[_][]const u8{emcc_exe_path});
    emcc.setName("emcc"); // hide emcc path
    emcc.addArg("-c");
    if (optimize == .ReleaseSmall) {
        emcc.addArg("-Oz");
    } else if (optimize == .ReleaseFast or optimize == .ReleaseSafe) {
        emcc.addArg("-O3");
    }
    emcc.addFileArg(filename);
    for (extra_flags) |flag| {
        emcc.addArg(flag);
    }
    emcc.addArg("-o");

    const output_name = switch (filename) {
        .dependency => filename.dependency.sub_path,
        .src_path => filename.src_path.sub_path,
        .cwd_relative => filename.cwd_relative,
        .generated => filename.generated.sub_path,
    };

    const output = emcc.addOutputFileArg(b.fmt("{s}.o", .{output_name}));
    return output;
}

const lua_base_source_files = [_][]const u8{
    "src/lapi.c",
    "src/lcode.c",
    "src/ldebug.c",
    "src/ldo.c",
    "src/ldump.c",
    "src/lfunc.c",
    "src/lgc.c",
    "src/llex.c",
    "src/lmem.c",
    "src/lobject.c",
    "src/lopcodes.c",
    "src/lparser.c",
    "src/lstate.c",
    "src/lstring.c",
    "src/ltable.c",
    "src/ltm.c",
    "src/lundump.c",
    "src/lvm.c",
    "src/lzio.c",
    "src/lauxlib.c",
    "src/lbaselib.c",
    "src/ldblib.c",
    "src/liolib.c",
    "src/lmathlib.c",
    "src/loslib.c",
    "src/ltablib.c",
    "src/lstrlib.c",
    "src/loadlib.c",
    "src/linit.c",
};

const lua_52_source_files = lua_base_source_files ++ [_][]const u8{
    "src/lctype.c",
    "src/lbitlib.c",
    "src/lcorolib.c",
};

const lua_53_source_files = lua_base_source_files ++ [_][]const u8{
    "src/lctype.c",
    "src/lbitlib.c",
    "src/lcorolib.c",
    "src/lutf8lib.c",
};

const lua_54_source_files = lua_base_source_files ++ [_][]const u8{
    "src/lctype.c",
    "src/lcorolib.c",
    "src/lutf8lib.c",
};
