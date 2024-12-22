// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const common = @import("./common.zig");
const utils = @import("./utils.zig");

const Vec2U = common.Vec2U;
const Color8 = common.Color8;
const RectF = common.RectF;
const RectI = common.RectI;

pub const TextureImage = struct {
    // GL Texture ID once loaded.
    texture: c_uint,
    size: Vec2U,
    name: ?[]u8,
};

pub const Texture = struct {
    texture: c_uint,
    size: Vec2U,
    src: RectF,

    pub fn sub(self: *const Texture, coords: RectF) Texture {
        const w: u32 = @intFromFloat(coords.width() * @as(f32, @floatFromInt(self.size.x)));
        const h: u32 = @intFromFloat(coords.height() * @as(f32, @floatFromInt(self.size.y)));
        return .{ 
            .texture = self.texture,
            .size = .{ .x = w, .y = h},
            .src = coords,
        };
    }
};

pub const CharToColor = struct {
    char: u8,
    color: Color8, 
};

// A sprite pack file.
pub const SpackFile = struct {
    frames: []SpackFrame
};

// A sprite frame as stored in an atlas json file.
pub const SpackFrame = struct {
    name: []u8,
    sizePx: Vec2U,
    pos: RectI,
};

pub fn blit(dest: []u8, destSize: Vec2U, src: []const u8, srcSize: Vec2U, offsetIntoBuffer: Vec2U) void {
    var srcIdx: usize = 0;
    const lineLen: usize = srcSize.x*4;
    const destLineLen: usize = destSize.x*4;
    var destIdx: usize = (offsetIntoBuffer.y*destSize.x+offsetIntoBuffer.x)*4;

    // Copy each line of the source image into the dest.
    while(srcIdx < src.len) {
        @memcpy(dest[destIdx..destIdx+lineLen], src[srcIdx..srcIdx+lineLen]);
        srcIdx += lineLen;
        destIdx += destLineLen;
    }
}

pub fn drawBufferFromChars(buffer: []u8, buffSize: Vec2U, chars: []const u8, charsSize: Vec2U, offsetIntoBuffer: Vec2U, mapping: []const CharToColor) void {
    // Manually track the index since we need to skip newlines.
    var chrIdx: usize = 0;
    var h: usize = offsetIntoBuffer.y;
    var w: usize = offsetIntoBuffer.x;

    while(chrIdx < chars.len) {
        const curr_ch = chars[chrIdx];
        chrIdx += 1;

        // Skip over newlines from raw literals
        if(curr_ch == '\n' or curr_ch == '\r') continue;

        // Find the color for the char.
        var color: Color8 = .{ .r=0, .g=0, .b=0, .a=255 };
        for(0..mapping.len) |idx| {
            if(mapping[idx].char == curr_ch) {
                color = mapping[idx].color;
            }
        }

        const col_idx:usize = (h*buffSize.x+w)*4;
        buffer[col_idx] = color.r;
        buffer[col_idx+1] = color.g;
        buffer[col_idx+2] = color.b;
        buffer[col_idx+3] = color.a;

        // Update pixel buffer locations.
        w += 1;
        if(w >= (offsetIntoBuffer.x+charsSize.x)) {
            w = offsetIntoBuffer.x;
            h += 1;
        }
    }
}

pub const TextureManager = struct {
    textures: std.ArrayList(TextureImage),
    atlas: std.StringHashMap(Texture),
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) TextureManager{
        return .{ 
            .textures = std.ArrayList(TextureImage).init(alloc),
            .atlas = std.StringHashMap(Texture).init(alloc),
            .allocator = alloc 
        };
    }

    pub fn destroy(self: *TextureManager) void {
        for (self.textures.items) |t| {
            gl.deleteTextures(1, &t.texture);
            self.allocator.free(t.name.?);
        }
        self.textures.clearAndFree();

        var atlasKeys = self.atlas.keyIterator();
        while(atlasKeys.next()) |key| {
            self.allocator.free(key.*);
        }

        self.atlas.deinit();
    }

    pub fn createTextureImageFromChars(
        self: *TextureManager, 
        name: []const u8, 
        width: usize, 
        height: usize, 
        chars: []const u8, 
        mapping: []const CharToColor) !*Texture
    {
        // Generate the color buffer, mapping chars to their given colors.
        var buffer: []u8 = try self.allocator.alloc(u8, width*height*4);
        defer self.allocator.free(buffer);

        // Manually track the index since we need to skip newlines.
        var chrIdx: usize = 0;
        var h: usize = 0;
        var w: usize = 0;

        while(chrIdx < chars.len) {
            const curr_ch = chars[chrIdx];
            chrIdx += 1;

            // Skip over newlines from raw literals
            if(curr_ch == '\n' or curr_ch == '\r') continue;

            var color: Color8 = .{ .r=0, .g=0, .b=0, .a=255 };
            for(0..mapping.len) |idx| {
                if(mapping[idx].char == curr_ch) {
                    color = mapping[idx].color;
                }
            }

            const col_idx:usize = (h*width+w)*4;
            buffer[col_idx] = color.r;
            buffer[col_idx+1] = color.g;
            buffer[col_idx+2] = color.b;
            buffer[col_idx+3] = color.a;

            // Update pixel buffer locations.
            w += 1;
            if(w >= width) {
                w = 0;
                h += 1;
            }
        }

        return try self.loadTextureFromBuffer(name, width, height, buffer);
    }


    pub fn loadTextureFromBuffer(self: *TextureManager, name: []const u8, width: usize, height: usize, buffer:[]u8) !*Texture
    {
        var texture: c_uint = undefined;
        gl.genTextures(1, &texture);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        const format = gl.RGBA;
        gl.texImage2D(gl.TEXTURE_2D, 0, format, 
            @intCast(width), 
            @intCast(height), 
            0, format, 
            gl.UNSIGNED_BYTE, 
            @ptrCast(buffer)
        );

        const copied_name = try self.allocator.alloc(u8, name.len);
        @memcpy(copied_name, name);
        try self.textures.append(.{
            .texture = texture,
            .size = .{ .x = @intCast(width), .y = @intCast(height) },
            .name = copied_name,
        });

        try self.atlas.put(try self.allocator.dupe(u8, name), .{
            .texture = texture,
            .size = .{ .x = @intCast(width), .y = @intCast(height) },
            .src = .{ .t = 0, .l = 0, .b = 1, .r = 1}
        });

        return self.atlas.getPtr(name).?;
    }


    // TODO: Add error handler.
    pub fn loadTexture(self: *TextureManager, name: []const u8, file_path: []const u8) !*Texture {

        // Convert our string slice to a null terminated string
        var nt_str = try self.allocator.alloc(u8, file_path.len + 1);
        defer self.allocator.free(nt_str);
        @memcpy(nt_str[0..file_path.len], file_path);
        nt_str[file_path.len] = 0;
        const nt_file_path = nt_str[0..file_path.len :0];

        // Try to load an image
        var image = try stbi.Image.loadFromFile(nt_file_path, 0);
        defer image.deinit();

        std.debug.print("Loaded image '{s}', width={}, height={}\n", .{ name, image.width, image.height });

        return try self.loadTextureFromBuffer(name, image.width, image.height, image.data);
    }

    pub fn loadAtlas(self: *TextureManager, baseName: []const u8) !usize {
        const imageName = try utils.addExtension(self.allocator, baseName, ".png");
        defer self.allocator.free(imageName);
        const texImage = try self.loadTexture(baseName, imageName);

        const jsonName = try utils.addExtension(self.allocator, baseName, ".json");
        defer self.allocator.free(jsonName);
        const f = try std.fs.cwd().openFile(jsonName, .{});
        defer f.close();

        var buffered = std.io.bufferedReader(f.reader());
        var reader = std.json.reader(self.allocator, buffered.reader());
        defer reader.deinit();
        const parsed = try std.json.parseFromTokenSource(
            SpackFile, 
            self.allocator, 
            &reader, 
            .{}
        );
        defer parsed.deinit();

        const spack = parsed.value;

        var num: usize = 0;
        for(spack.frames) |frame| {
            try self.atlas.put(
                try self.allocator.dupe(u8, frame.name), 
                .{
                    .texture = texImage.texture,
                    .size = frame.sizePx,
                    .src = RectF.fromCoords(
                        frame.pos.t, 
                        frame.pos.l, 
                        frame.pos.width(), 
                        frame.pos.height(), 
                        @intCast(texImage.size.x),
                        @intCast(texImage.size.y)
                    ),
                }
            );

            num += 1;
        }

        return num;
    }
    
    pub fn addSubTexture(self: *TextureManager, tex: *Texture, name: []const u8, coords: RectF) !*Texture {
       try self.atlas.put(try self.allocator.dupe(u8, name), tex.sub(coords));
       return self.atlas.getPtr(name).?;
    }

    pub fn getTexture(self: *TextureManager, name: []const u8) !*Texture {
        const tex = self.atlas.getPtr(name);
        if(tex == null) {
            return error.NoTextureWithThatName;
        }
        return tex.?;
    }
};


