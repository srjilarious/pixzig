// zig fmt: off
const std = @import("std");
const zargs = @import("zargunaught");
const pixzig = @import("pixzig");
const stbi = @import("zstbi");

const RectI = pixzig.common.RectI;

const Option = zargs.Option;

pub const SpriteFrame = struct {
    name: []u8,
    pos: RectI,
};

fn handleImageFile(alloc: std.mem.Allocator, path: []const u8) !void {
    // Convert our string slice to a null terminated string
    var nt_str = try alloc.alloc(u8, path.len + 1);
    defer alloc.free(nt_str);
    @memcpy(nt_str[0..path.len], path);
    nt_str[path.len] = 0;
    const nt_file_path = nt_str[0..path.len :0];

    // Try to load an image
    var image = try stbi.Image.loadFromFile(nt_file_path, 0);
    defer image.deinit();

    std.debug.print("Loaded image '{s}', width={}, height={}\n", .{ path, image.width, image.height });
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    stbi.init(alloc);
    defer stbi.deinit();

    var parser = try zargs.ArgParser.init(
        alloc, .{ 
            .name = "Spack",
            .description = "A simple sprite packing tool",
            .usage = "Packs identically sized images into a larger sprite sheet as a PNG.",
            .opts = &.{
                .{ .longName = "width", .shortName="w", .description = "The width of the sprite sheet", .maxNumParams = 1 },
                .{ .longName = "height", .shortName="h", .description = "The height of the sprite sheet", .maxNumParams = 1 },
                .{ .longName = "output", .shortName = "o", .description = "The output base name."},
                .{ .longName = "help", .description = "Prints out help for the program." },
            },
        });
    defer parser.deinit();

    var args = parser.parse() catch |err| {
        std.debug.print("Error parsing args: {any}\n", .{err});
        return;
    };
    defer args.deinit();

    var stdout = try zargs.print.Printer.stdout(std.heap.page_allocator);
    defer stdout.deinit();

    if(args.hasOption("help")) {
        var help = try zargs.help.HelpFormatter.init(&parser, stdout, zargs.help.DefaultTheme, std.heap.page_allocator);
        defer help.deinit();

        help.printHelpText() catch |err| {
            std.debug.print("Err: {any}\n", .{err});
        };
    }


    for(args.positional.items) |path| {
        const metadata = try std.fs.cwd().statFile(path);

        // Check if it's a file or a directory
        switch (metadata.kind) {
            .file => {
                std.debug.print("{s} is a file.\n", .{path});
                try handleImageFile(alloc, path);
            },
            .directory => std.debug.print("{s} is a directory.\n", .{path}),
            else => std.debug.print("{s} is neither a file nor a directory.\n", .{path}),
        }
    }

    try stdout.flush();
    
}

