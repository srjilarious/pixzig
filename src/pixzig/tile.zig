const std = @import("std");
const xml = @import("xml");

const MaxFilesize = 1024 * 1024 * 1024;
pub const TileMap = struct {
    pub fn initFromFile(filename: []const u8, alloc: std.mem.Allocator) !void {
        const fileContents = try std.fs.cwd().readFileAlloc(alloc, filename, MaxFilesize);
        defer alloc.free(fileContents);

        std.debug.print("\nContents:\n\n-------\n{s}\n--------\n\n", .{fileContents});

        const doc = try xml.parse(std.heap.page_allocator, fileContents);
        var elems = doc.root.elements();
        while (elems.next()) |elem| {
            std.debug.print("Element: {s}\n", .{elem.tag});
        }
    }
};
