// zig fmt: off
const std = @import("std");
const testz = @import("testz");

const Tests = testz.discoverTests(.{ 
    @import("./tile_tests.zig"),
});

pub fn main() void {
    const verbose = if(std.os.argv.len > 1 and std.mem.eql(u8, "verbose", std.mem.span(std.os.argv[1]))) true else false;
    
    _ = testz.runTests(Tests, verbose);
}
