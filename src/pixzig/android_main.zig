//! The Android entry point. An Android game is a shared library,
//! `libmain.so`, that SDL's `SDLActivity` loads and calls `SDL_main` on,
//! from its own thread, so Zig's `start.zig` never runs and nothing builds
//! the `std.process.Init` a game's `main` takes. `Entry(main).sdlMain` does
//! what `start.zig`'s `callMain` would, then calls `main`; the root wrapper
//! `buildGame` generates exports it as `SDL_main`.

const std = @import("std");

pub fn Entry(comptime main: anytype) type {
    return struct {
        pub fn sdlMain(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
            const args = argv[0..@intCast(argc)];

            var env_count: usize = 0;
            while (std.c.environ[env_count] != null) : (env_count += 1) {}
            const env_block: std.process.Environ.Block = .{ .slice = std.c.environ[0..env_count :null] };

            // libc's malloc rather than a debug allocator: there is no
            // terminal to report leaks to, and the process outlives `main`
            // (SDLActivity can start it again without a fresh process).
            const gpa = std.heap.c_allocator;

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();

            var threaded: std.Io.Threaded = .init(gpa, .{
                .argv0 = .init(.{ .vector = args }),
                .environ = .{ .block = env_block },
            });
            defer threaded.deinit();

            var environ_map = std.process.Environ.createMap(.{ .block = env_block }, gpa) catch |err| {
                std.log.err("failed to parse environment variables: {t}", .{err});
                return 1;
            };
            defer environ_map.deinit();

            const preopens = std.process.Preopens.init(arena.allocator()) catch |err| {
                std.log.err("failed to init preopens: {t}", .{err});
                return 1;
            };

            main(.{
                .minimal = .{
                    .args = .{ .vector = args },
                    .environ = .{ .block = env_block },
                },
                .arena = &arena,
                .gpa = gpa,
                .io = threaded.io(),
                .environ_map = &environ_map,
                .preopens = preopens,
            }) catch |err| {
                std.log.err("main failed: {t}", .{err});
                if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
                return 1;
            };
            return 0;
        }
    };
}
