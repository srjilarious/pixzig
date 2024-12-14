// zig fmt: off
const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const common = @import("./common.zig");

const Vec2U = common.Vec2U;
const Color8 = common.Color8;

pub const Texture = struct {
    // GL Texture ID once loaded.
    texture: c_uint,
    size: Vec2U,
    name: ?[]u8,
};

pub const CharToColor = struct {
    char: u8,
    color: Color8, 
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
    textures: std.ArrayList(Texture),
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) TextureManager{
        const textures = std.ArrayList(Texture).init(alloc);
        return .{ .textures = textures, .allocator = alloc };
    }

    pub fn destroy(self: *TextureManager) void {
        for (self.textures.items) |t| {
            gl.deleteTextures(1, &t.texture);
            self.allocator.free(t.name.?);
        }
        self.textures.clearAndFree();
    }

    pub fn createTextureFromChars(
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


    pub fn loadTextureFromBuffer(self: *TextureManager, name: []const u8, width: usize, height: usize, buffer:[]u8) !*Texture{
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

        return &self.textures.items[self.textures.items.len - 1];
    }


    // TODO: Add error handler.
    pub fn loadTexture(self: *TextureManager, name: []const u8, file_path: []const u8) !*Texture{

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
        // var texture: c_uint = undefined;
        // gl.genTextures(1, &texture);
        // gl.bindTexture(gl.TEXTURE_2D, texture);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        // const format = gl.RGBA;
        // gl.texImage2D(gl.TEXTURE_2D, 0, format, 
        //     @intCast(image.width), 
        //     @intCast(image.height), 
        //     0, format, 
        //     gl.UNSIGNED_BYTE, 
        //     @ptrCast(image.data)
        // );
        //
        // const copied_name = try self.allocator.alloc(u8, name.len);
        // @memcpy(copied_name, name);
        // try self.textures.append(.{
        //     .texture = texture,
        //     .size = .{ .x = image.width, .y = image.height },
        //     .name = copied_name,
        // });
        //
        // return &self.textures.items[self.textures.items.len - 1];
    }
};


