// zig fmt: off
const std = @import("std");
const zargs = @import("zargunaught");
const pixzig = @import("pixzig");
const stbi = @import("zstbi");

const RectI = pixzig.common.RectI;
const Vec2U = pixzig.common.Vec2U;

const Option = zargs.Option;

const SpackFile = pixzig.textures.SpackFile;
const SpackFrame = pixzig.textures.SpackFrame;

const SpackProcessor = struct {
    curPos: Vec2U,
    image: stbi.Image,
    rects: std.ArrayList(SpackFrame),

    const Self = @This();
    pub fn init(alloc: std.mem.Allocator, size: Vec2U) !Self {
        return .{
            .curPos = .{ .x = 0, .y = 0},
            .image = try stbi.Image.createEmpty(size.x, size.y, 4, .{}),
            .rects = std.ArrayList(SpackFrame).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.image.deinit();
        self.rects.deinit();
    }
    pub fn handleImageFile(self: *Self, alloc: std.mem.Allocator, path: []const u8) !void {
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

        // Copy image into larger atlas.
        pixzig.textures.blit(
            self.image.data, .{ .x=self.image.width, .y=self.image.height}, 
            image.data, .{ .x=image.width, .y=image.height}, self.curPos);

        const rootName = blk: {
            const lastIndex = std.mem.lastIndexOf(u8, path, "/");
            if(lastIndex != null) {
                break :blk path[lastIndex.?+1..];
            }
            else {
                break :blk path;
            }
        };

        const name = blk: {
            const lastIndex = std.mem.lastIndexOf(u8, rootName, ".");
            if(lastIndex != null) {
                break :blk rootName[0..lastIndex.?];
            }
            else {
                break :blk rootName;
            }
        };

        try self.rects.append(
            .{ 
                .name = try alloc.dupe(u8, name),
                .sizePx = .{ 
                    .x = @intCast(image.width), 
                    .y = @intCast(image.height)
                },
                .pos = RectI.init(
                    @intCast(self.curPos.x), 
                    @intCast(self.curPos.y), 
                    @intCast(image.width), 
                    @intCast(image.height))
        });

        // Update position for next sprite.
        self.curPos.x += image.width;
        if(self.curPos.x >= self.image.width) {
            self.curPos = .{ .x = 0, .y = self.curPos.y + image.height };
        }

    }
};


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
                // TODO: Add in default values. Add default value as type to zargs.
                .{ .longName = "width", .shortName="w", .description = "The width of the sprite sheet", .maxNumParams = 1 },
                .{ .longName = "height", .shortName="h", .description = "The height of the sprite sheet", .maxNumParams = 1 },
                .{ .longName = "output", .shortName = "o", .description = "The output base name.", .maxNumParams = 1},
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

    const width = try args.optionNumValOrDefault(u32, "width", 256);
    const height = try args.optionNumValOrDefault(u32, "height", 256);
    var spack = try SpackProcessor.init(alloc, .{.x = width, .y = height});
    defer spack.deinit();

    for(args.positional.items) |path| {
        const metadata = try std.fs.cwd().statFile(path);

        // Check if it's a file or a directory
        switch (metadata.kind) {
            .file => {
                std.debug.print("{s} is a file.\n", .{path});
                try spack.handleImageFile(alloc, path);
            },
            .directory => std.debug.print("{s} is a directory.\n", .{path}),
            else => std.debug.print("{s} is neither a file nor a directory.\n", .{path}),
        }
    }

    const output: []const u8 = args.optionValOrDefault("output", "sprites");

    const imageName = try std.mem.concatWithSentinel(alloc, u8, &[_][]const u8{ output, ".png"}, 0);
    defer alloc.free(imageName);

    try spack.image.writeToFile(imageName, .png);

    // Write out the json file.
    const data: SpackFile = .{
        .frames = spack.rects.items
    };

    const jsonName = try std.mem.concat(alloc, u8, &[_][]const u8{ output, ".json"});
    defer alloc.free(jsonName);

    var file = try std.fs.cwd().createFile(jsonName, .{});
    defer file.close();

    try std.json.stringify(data, .{ .whitespace = .indent_2 }, file.writer());
    try stdout.print("Wrote out json file with {} rects.\n", .{spack.rects.items.len});
    try stdout.flush();
}

