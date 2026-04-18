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

/// A structure for managing game resources, particularly rendering ones:
/// textures, shaders and texture atlases. The resource manager is responsible
/// for loading and unloading these resources, as well as providing access to
/// them for the rest of the application. It also handles deallocating them
/// and their OpenGL resources, if any, when the resource manager is
/// deinitialized.
pub const ResourceManager = struct {
    textures: std.ArrayList(TextureImage),
    shaders: std.ArrayList(*Shader),
    atlas: std.StringHashMap(Texture),
    alloc: std.mem.Allocator,

    const Self = @This();

    /// Initializes the resource manager.
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .textures = .empty,
            .shaders = .empty,
            .atlas = std.StringHashMap(Texture).init(alloc),
            .alloc = alloc,
        };
    }

    // Deinitializes the resource manager, freeing all resources and their OpenGL resources.
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

    /// Creates a texture from a character buffer, where each character is mapped
    /// to a color. This is useful for creating textures from ASCII art or other
    /// character-based representations.  This can be helpful for making games with
    /// simple retro textures embedded in the source itself.
    ///
    /// An example:
    /// ```zig
    /// const blockChars =
    ///     \\=------=
    ///     \\-..####-
    ///     \\-.####=-
    ///     \\-#####=-
    ///     \\-#####=-
    ///     \\-#####=-
    ///     \\-##===@-
    ///     \\=------=
    ///     ;
    ///
    ///     const tex = try eng.resources.createTextureImageFromChars("test", 8, 8, blockChars, &[_]CharToColor{
    ///         .{ .char = '#', .color = Color8.from(40, 255, 40, 255) },
    ///         .{ .char = '-', .color = Color8.from(100, 100, 200, 255) },
    ///         .{ .char = '=', .color = Color8.from(100, 100, 100, 255) },
    ///         .{ .char = '.', .color = Color8.from(240, 240, 240, 255) },
    ///         .{ .char = '@', .color = Color8.from(30, 155, 30, 255) },
    ///         .{ .char = ' ', .color = Color8.from(0, 0, 0, 0) },
    ///     });
    /// ```
    pub fn createTextureImageFromChars(
        self: *Self,
        name: []const u8,
        width: usize,
        height: usize,
        chars: []const u8,
        mapping: []const CharToColor,
    ) !*Texture {
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

    /// Loads an RGBA texture from a raw buffer. The buffer should be in RGBA
    /// format, with 4 bytes per pixel. The name is the name that the texture
    /// will be stored with in the resource manager, and is used to access the
    /// texture later with `getTexture`. The width and height are the dimensions
    /// of the texture and must match the buffer size.
    pub fn loadTextureFromBuffer(
        self: *Self,
        name: []const u8,
        width: usize,
        height: usize,
        buffer: []u8,
    ) !*Texture {
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

    /// Loads a texture from a file path. The name is the base name of the
    /// file, without the extension, so "player" would match "player.png".
    /// The texture is stored in the atlas with the base name, so it can be
    /// accessed with `getTexture` using that name.  The file type is
    /// determined from the file extension, and should be a type supported
    /// by the `stbi` library, such as png or jpg.
    pub fn loadTexture(
        self: *Self,
        name: []const u8,
        file_path: []const u8,
    ) !*Texture {
        std.log.info("Loading image '{s}' from '{s}'\n", .{ name, file_path });
        const nt_file_path = try self.alloc.dupeZ(u8, file_path);
        defer self.alloc.free(nt_file_path);

        // Try to load an image
        var image = try stbi.Image.loadFromFile(nt_file_path, 0);
        defer image.deinit();

        std.log.info("Loaded image '{s}', width={}, height={}\n", .{ name, image.width, image.height });

        return try self.loadTextureFromBuffer(name, image.width, image.height, image.data);
    }

    /// Loads a texture atlas from a base name. This looks for a .png and
    /// .json file with the given base name, and loads the texture and
    /// subtextures specified in the json file. The json file should be in the
    /// format of a `SpackFile`, which is the format used by our internal
    /// `TexturePacker` tool.
    ///
    /// The subtextures are stored in the atlas with their names from the json
    /// file, so they can be accessed with `getTexture` using those names.
    pub fn loadAtlas(self: *Self, baseName: []const u8) !usize {
        const imageName = try utils.addExtension(self.alloc, baseName, ".png");
        defer self.alloc.free(imageName);
        const texImage = try self.loadTexture(baseName, imageName);

        const jsonName = try utils.addExtension(self.alloc, baseName, ".json");
        defer self.alloc.free(jsonName);

        // Read entire file into memory
        const io = std.Io.Threaded.global_single_threaded.io();
        const file_contents = try std.Io.Dir.cwd().readFileAlloc(io, jsonName, self.alloc, .unlimited);
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

    /// Adds a subtexture to the manager. This is useful for adding a named
    /// texture from a region of a larger generated texture.  Coordinates are
    /// in UV space, so (0, 0) is the top left of the texture and (1, 1) is
    /// the bottom right of the texture.
    pub fn addSubTexture(
        self: *Self,
        tex: *Texture,
        name: []const u8,
        coords: RectF,
    ) !*Texture {
        try self.atlas.put(try self.alloc.dupe(u8, name), tex.sub(coords));
        return self.atlas.getPtr(name).?;
    }

    /// Gets a texture by name. Returns an error if no texture with that name
    /// exists. The name is the base name of the file, without the extension,
    /// so "player" would match "player.png" and "player.json" in the case of
    /// an atlas.  Textures within an atlas are accessed by the name specified
    /// with the json.
    pub fn getTexture(self: *Self, name: []const u8) !*Texture {
        const tex = self.atlas.getPtr(name);
        if (tex == null) {
            return error.NoTextureWithThatName;
        }
        return tex.?;
    }

    /// Gets a shader by name. Returns an error if no shader with that name
    /// exists.
    pub fn getShaderByName(self: *Self, name: []const u8) !*const Shader {
        for (self.shaders.items) |s| {
            if (s.name != null and std.mem.eql(u8, name, s.name.?)) {
                return s;
            }
        }

        return error.NoShaderWithThatName;
    }

    /// Loads a shader from vertex and fragment shader source code, and stores
    /// it in the resource manager with the given name. If a shader with that
    /// name already exists, it is returned instead of loading a new one.
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
