const std = @import("std");
const builtin = @import("builtin");
const web = @import("./web.zig");
const ptime = @import("./time.zig");

/// The default panic handler, or one that also reaches the browser console
/// (emscripten) or logcat (Android), where stderr goes nowhere.
pub const panic = if (builtin.os.tag == .emscripten)
    web.panic
else if (builtin.abi.isAndroid())
    std.debug.FullPanic(androidPanic)
else
    std.debug.FullPanic(std.debug.defaultPanic);

/// Standard options for setting up logging to the browser console
/// (emscripten), logcat (Android), or stderr.
pub const std_options = blk: {
    if (builtin.os.tag == .emscripten) {
        break :blk std.Options{ .logFn = web.log };
    } else if (builtin.abi.isAndroid()) {
        break :blk std.Options{ .logFn = androidLog };
    } else {
        break :blk std.Options{ .logFn = nativeLog };
    }
};

/// The tag every pixzig log line carries in logcat:
/// `adb logcat -s pixzig` shows a game's log and nothing else.
const android_log_tag = "pixzig";

// From <android/log.h>; declared by hand so the engine needs no translated
// NDK header for one function. The priorities are `android_LogPriority`'s.
extern "log" fn __android_log_write(prio: c_int, tag: [*:0]const u8, text: [*:0]const u8) c_int;
const ANDROID_LOG_DEBUG = 3;
const ANDROID_LOG_INFO = 4;
const ANDROID_LOG_WARN = 5;
const ANDROID_LOG_ERROR = 6;

fn androidLog(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const prio = comptime switch (level) {
        .err => ANDROID_LOG_ERROR,
        .warn => ANDROID_LOG_WARN,
        .info => ANDROID_LOG_INFO,
        .debug => ANDROID_LOG_DEBUG,
    };
    const scope_prefix = comptime if (scope == .default) "" else "(" ++ @tagName(scope) ++ ") ";
    // logcat keeps lines up to about 4 KiB; a longer message is cut short
    // rather than dropped.
    var buf: [4096]u8 = undefined;
    const line = std.fmt.bufPrintSentinel(&buf, scope_prefix ++ format, args, 0) catch blk: {
        buf[buf.len - 1] = 0;
        break :blk buf[0 .. buf.len - 1 :0];
    };
    _ = __android_log_write(prio, android_log_tag, line.ptr);
}

fn androidPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    var buf: [1024]u8 = undefined;
    const line = std.fmt.bufPrintSentinel(&buf, "panic: {s}", .{msg}, 0) catch "panic (message too long)";
    _ = __android_log_write(ANDROID_LOG_ERROR, android_log_tag, line.ptr);
    std.debug.defaultPanic(msg, first_trace_addr);
}

fn nativeLog(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_color = comptime switch (level) {
        .err => "\x1b[31;1m",
        .warn => "\x1b[33;1m",
        .info => "\x1b[32;1m",
        .debug => "\x1b[36;1m",
    };
    const level_char = comptime switch (level) {
        .err => "E",
        .warn => "W",
        .info => "I",
        .debug => "D",
    };
    const scope_prefix = comptime if (scope == .default) "" else "(" ++ @tagName(scope) ++ ") ";

    const io = std.Io.Threaded.global_single_threaded.io();
    const lt = ptime.getLocalTime(io);

    var buffer: [256]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer);
    defer std.debug.unlockStderr();
    nosuspend {
        stderr.file_writer.interface.print(
            "\x1b[2m{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}\x1b[0m " ++
                level_color ++ level_char ++ "\x1b[0m " ++
                scope_prefix,
            .{ lt.hour, lt.minute, lt.second, lt.msPart },
        ) catch return;
        stderr.file_writer.interface.print(format ++ "\x1b[0m\n", args) catch return;
    }
}
