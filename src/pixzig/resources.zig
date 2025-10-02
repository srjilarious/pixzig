const std = @import("std");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const common = @import("./common.zig");
const utils = @import("./utils.zig");
const shaders = @import("./renderer/shaders.zig");
const textures = @import("./renderer/textures.zig");

const TextureImage = textures.TextureImage;
const Texture = textures.Texture;
const Shader = shaders.Shader;
const CharToColor = textures.CharToColor;
const SpackFile = textures.SpackFile;

const Vec2U = common.Vec2U;
const Vec2I = common.Vec2I;
const Color8 = common.Color8;
const RectF = common.RectF;
const RectI = common.RectI;

pub const ResourceManager = struct {
    textures: std.ArrayList(TextureImage),
    shaders: std.ArrayList(*Shader),
    atlas: std.StringHashMap(Texture),
    alloc: std.mem.Allocator,

    const Self = @This();
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .textures = .{},
            .shaders = .{},
            .atlas = std.StringHashMap(Texture).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.textures.items) |t| {
            gl.deleteTextures(1, &t.texture);
            self.alloc.free(t.name.?);
        }
        self.textures.clearAndFree(self.alloc);

        var atlasKeys = self.atlas.keyIterator();
        while (atlasKeys.next()) |key| {
            self.alloc.free(key.*);
        }

        self.atlas.deinit();
    }

    pub fn createTextureImageFromChars(self: *Self, name: []const u8, width: usize, height: usize, chars: []const u8, mapping: []const CharToColor) !*Texture {
        // Generate the color buffer, mapping chars to their given colors.
        var buffer: []u8 = try self.alloc.alloc(u8, width * height * 4);
        defer self.alloc.free(buffer);

        // Manually track the index since we need to skip newlines.
        var chrIdx: usize = 0;
        var h: usize = 0;
        var w: usize = 0;

        while (chrIdx < chars.len) {
            const curr_ch = chars[chrIdx];
            chrIdx += 1;

            // Skip over newlines from raw literals
            if (curr_ch == '\n' or curr_ch == '\r') continue;

            var color: Color8 = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
            for (0..mapping.len) |idx| {
                if (mapping[idx].char == curr_ch) {
                    color = mapping[idx].color;
                }
            }

            const col_idx: usize = (h * width + w) * 4;
            buffer[col_idx] = color.r;
            buffer[col_idx + 1] = color.g;
            buffer[col_idx + 2] = color.b;
            buffer[col_idx + 3] = color.a;

            // Update pixel buffer locations.
            w += 1;
            if (w >= width) {
                w = 0;
                h += 1;
            }
        }

        return try self.loadTextureFromBuffer(name, width, height, buffer);
    }

    pub fn loadTextureFromBuffer(self: *Self, name: []const u8, width: usize, height: usize, buffer: []u8) !*Texture {
        var texture: c_uint = undefined;
        gl.genTextures(1, &texture);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        const format = gl.RGBA;
        gl.texImage2D(gl.TEXTURE_2D, 0, format, @intCast(width), @intCast(height), 0, format, gl.UNSIGNED_BYTE, @ptrCast(buffer));

        const baseName = utils.baseNameFromPath(name);

        try self.textures.append(self.alloc, .{
            .texture = texture,
            .size = .{ .x = @intCast(width), .y = @intCast(height) },
            .name = try self.alloc.dupe(u8, baseName),
        });

        try self.atlas.put(try self.alloc.dupe(u8, baseName), .{ .texture = texture, .size = .{ .x = @intCast(width), .y = @intCast(height) }, .src = .{ .t = 0, .l = 0, .b = 1, .r = 1 } });

        return self.atlas.getPtr(baseName).?;
    }

    // TODO: Add error handler.
    pub fn loadTexture(self: *Self, name: []const u8, file_path: []const u8) !*Texture {
        std.log.info("Loading image '{s}' from '{s}'\n", .{ name, file_path });
        const nt_file_path = try self.alloc.dupeZ(u8, file_path);
        defer self.alloc.free(nt_file_path);

        // Try to load an image
        var image = try stbi.Image.loadFromFile(nt_file_path, 0);
        defer image.deinit();

        std.log.info("Loaded image '{s}', width={}, height={}\n", .{ name, image.width, image.height });

        return try self.loadTextureFromBuffer(name, image.width, image.height, image.data);
    }

    pub fn loadAtlas(self: *Self, baseName: []const u8) !usize {
        const imageName = try utils.addExtension(self.alloc, baseName, ".png");
        defer self.alloc.free(imageName);
        const texImage = try self.loadTexture(baseName, imageName);

        const jsonName = try utils.addExtension(self.alloc, baseName, ".json");
        defer self.alloc.free(jsonName);

        // Read entire file into memory
        const file_contents = try std.fs.cwd().readFileAlloc(self.alloc, jsonName, std.math.maxInt(usize));
        defer self.alloc.free(file_contents);

        const parsed = try std.json.parseFromSlice(SpackFile, self.alloc, file_contents, .{});
        defer parsed.deinit();

        const spack = parsed.value;

        const sz: Vec2I = texImage.size.asVec2I();
        var num: usize = 0;
        for (spack.frames) |frame| {
            try self.atlas.put(try self.alloc.dupe(u8, frame.name), .{
                .texture = texImage.texture,
                .size = frame.sizePx,
                .src = RectF.fromCoords(
                    frame.pos.l,
                    frame.pos.t,
                    frame.pos.width(),
                    frame.pos.height(),
                    sz.x,
                    sz.y,
                ),
            });

            num += 1;
        }

        return num;
    }

    pub fn addSubTexture(self: *Self, tex: *Texture, name: []const u8, coords: RectF) !*Texture {
        try self.atlas.put(try self.alloc.dupe(u8, name), tex.sub(coords));
        return self.atlas.getPtr(name).?;
    }

    pub fn getTexture(self: *Self, name: []const u8) !*Texture {
        const tex = self.atlas.getPtr(name);
        if (tex == null) {
            return error.NoTextureWithThatName;
        }
        return tex.?;
    }

    pub fn getShaderByName(self: *Self, name: []const u8) !*const Shader {
        for (self.shaders.items) |s| {
            if (s.name != null and std.mem.eql(u8, name, s.name.?)) {
                return s;
            }
        }

        return error.NoShaderWithThatName;
    }

    pub fn loadShader(
        self: *Self,
        name: []const u8,
        vs: shaders.ShaderCodePtr,
        fs: shaders.ShaderCodePtr,
    ) !*const Shader {

        // Check if we already have a shader with that name.
        for (self.shaders.items) |s| {
            if (s.name != null and std.mem.eql(u8, name, s.name.?)) {
                return s;
            }
        }

        const shader = try self.alloc.create(Shader);
        shader.* = try Shader.init(vs, fs, .{ .name = name });
        try self.shaders.append(self.alloc, shader);
        return self.shaders.items[self.shaders.items.len - 1];
    }
};
