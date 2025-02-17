const std = @import("std");
const builtin = @import("builtin");
const web = @import("./web.zig");

// Either the default panic handler or an emscripten capable one.
pub const panic = if (builtin.os.tag == .emscripten) web.panic else std.debug.FullPanic(std.debug.defaultPanic);

// Standard options for setting up logging to either use an emscripten log handler, or the default one.
pub const std_options = blk: {
    if (builtin.os.tag == .emscripten) {
        break :blk std.Options{ .logFn = web.log };
    } else {
        break :blk std.Options{ .logFn = std.log.defaultLog };
    }
};
