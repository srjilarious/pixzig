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

/// A reference-counted, generation-tracked handle to an asset of type `T`.
/// Handles are owned by a `ManagedResource` and must be obtained via
/// `acquire`. Holders should call `release` when finished and inspect
/// `dirty` to decide whether to re-acquire for a newer generation.
pub fn AssetHandle(comptime T: type) type {
    return struct {
        id: u32,
        generation: u32,
        refCount: u32,
        dirty: bool,
        val: T,

        /// Function signature for a function that frees the underlying resource.
        pub const FreeFunc = *const fn (T) void;
    };
}

pub const TextureHandle = AssetHandle(Texture);
pub const ShaderHandle = AssetHandle(*Shader);

// pub const SoundHandle = AssetHandler()

/// A pool of refcounted, hot-reloadable assets of type `T`, keyed by a
/// user-supplied `u32` id. Multiple generations of the same id may coexist:
/// adding a new version marks any older live version dirty so holders can
/// notice and re-acquire, while unreferenced older versions are reclaimed
/// immediately.
///
/// Handles returned by `add` / `acquire` are heap-allocated and remain at
/// stable addresses for their full lifetime, so callers may hold raw
/// `*AssetHandle(T)` pointers across `add` calls.
pub fn ManagedResource(comptime ResourceName: []const u8, comptime T: type) type {
    return struct {
        res: std.ArrayList(?*HandleType),
        alloc: std.mem.Allocator,
        freeFunc: HandleType.FreeFunc,
        id: u32,
        gen: u32,

        const Self = @This();
        pub const HandleType = AssetHandle(T);

        pub fn init(alloc: std.mem.Allocator, id: u32, freeFunc: HandleType.FreeFunc) Self {
            return .{
                .res = .empty,
                .alloc = alloc,
                .freeFunc = freeFunc,
                .id = id,
                .gen = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.res.items) |hOpt| {
                if (hOpt) |h| {
                    if (h.refCount != 0) {
                        std.log.err("{s}:{}: refCount = {} on deinit", .{ ResourceName, h.id, h.refCount });
                    }
                    self.freeFunc(h.val);
                    self.alloc.destroy(h);
                }
            }
            self.res.deinit(self.alloc);
        }

        /// Add a new version of the managed resource. Existing versions
        /// are either marked dirty (if still referenced) or freed
        /// immediately (if no one holds them).
        pub fn add(self: *Self, obj: T) !void {
            for (self.res.items, 0..) |hOpt, i| {
                if (hOpt) |h| {
                    if (h.refCount == 0) {
                        self.freeFunc(h.val);
                        self.alloc.destroy(h);
                        self.res.items[i] = null;
                    } else {
                        h.dirty = true;
                    }
                }
            }

            self.gen += 1;

            const handle = try self.alloc.create(HandleType);
            errdefer self.alloc.destroy(handle);
            handle.* = .{
                .id = self.id,
                .generation = self.gen,
                .refCount = 0,
                .dirty = false,
                .val = obj,
            };

            try self.insertHandle(handle);
        }

        /// Increment the refCount on the latest live handle for the resource.
        /// Returns null if nothing is registered under `id`.
        pub fn acquire(self: *Self) ?*HandleType {
            const latestHandle = self.latest() orelse return null;
            latestHandle.refCount += 1;
            return latestHandle;
        }

        /// Decrement the refCount. A dirty handle dropping to refCount == 0
        /// is freed and its slot reclaimed. Clean handles at refCount == 0
        /// are retained so subsequent `acquire` calls still hit.
        pub fn release(self: *Self, handle: *HandleType) void {
            std.debug.assert(handle.refCount > 0);
            handle.refCount -= 1;
            if (handle.refCount == 0 and handle.dirty) {
                self.freeHandle(handle);
            }
        }

        /// Latest live handle for the resource without bumping refCount.
        /// Useful for peeking; prefer `acquire` for anything that outlives
        /// one frame.
        pub fn get(self: *Self) ?*HandleType {
            return self.latest();
        }

        fn latest(self: *Self) ?*HandleType {
            var latestHandle: ?*HandleType = null;
            for (self.res.items) |hOpt| {
                if (hOpt) |h| {
                    if (latestHandle == null or h.generation > latestHandle.?.generation) {
                        latestHandle = h;
                    }
                }
            }
            return latestHandle;
        }

        fn insertHandle(self: *Self, handle: *HandleType) !void {
            for (self.res.items) |*slot| {
                if (slot.* == null) {
                    slot.* = handle;
                    return;
                }
            }
            try self.res.append(self.alloc, handle);
        }

        fn freeHandle(self: *Self, handle: *HandleType) void {
            for (self.res.items, 0..) |hOpt, i| {
                if (hOpt) |h| {
                    if (h == handle) {
                        self.freeFunc(h.val);
                        self.alloc.destroy(h);
                        self.res.items[i] = null;
                        return;
                    }
                }
            }
            unreachable; // handle wasn't owned by this manager
        }
    };
}

/// The atlas stores named, refcounted views over GL textures. A Texture
/// value itself owns no GL state, so reclaiming a stale view is free.
pub const TextureAtlasPool = ManagedResource("Texture", Texture);

/// A TextureImage owns the GL texture handle. Reclaiming a stale
/// TextureImage deletes the GL handle.
pub const TextureImagePool = ManagedResource("TextureImage", TextureImage);

/// A Shader owns its GL program + vertex/fragment shaders. The pool stores
/// shaders by value; pointer stability comes from the heap-allocated
/// `AssetHandle` inside the pool.
pub const ShaderPool = ManagedResource("Shader", Shader);

fn freeTextureNoop(_: Texture) void {}

fn freeTextureImage(t: TextureImage) void {
    gl.deleteTextures(1, &t.texture);
}

fn freeShader(s: Shader) void {
    var copy = s;
    copy.deinit();
}

/// A structure for managing game resources, particularly rendering ones:
/// textures, shaders and texture atlases. The resource manager is responsible
/// for loading and unloading these resources, as well as providing access to
/// them for the rest of the application. It also handles deallocating them
/// and their OpenGL resources, if any, when the resource manager is
/// deinitialized.
pub const ResourceManager = struct {
    textures: std.StringHashMap(*TextureImagePool),
    shaders: std.StringHashMap(*ShaderPool),
    atlas: std.StringHashMap(*TextureAtlasPool),
    alloc: std.mem.Allocator,
    /// Monotonic id assigned to each new ManagedResource the manager owns.
    /// Lookups inside a pool use generations; this id distinguishes pools.
    gid: u32,

    const Self = @This();

    /// Initializes the resource manager.
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .textures = std.StringHashMap(*TextureImagePool).init(alloc),
            .shaders = std.StringHashMap(*ShaderPool).init(alloc),
            .atlas = std.StringHashMap(*TextureAtlasPool).init(alloc),
            .alloc = alloc,
            .gid = 0,
        };
    }

    // Deinitializes the resource manager, freeing all resources and their OpenGL resources.
    pub fn deinit(self: *Self) void {
        var tit = self.textures.iterator();
        while (tit.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        self.textures.deinit();

        var it = self.atlas.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        self.atlas.deinit();

        var sit = self.shaders.iterator();
        while (sit.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        self.shaders.deinit();
    }

    /// Returns the existing atlas pool for `name`, or creates a new empty
    /// pool (consuming one `gid`) and inserts it. The returned pointer is
    /// stable across atlas mutations.
    fn getOrCreateAtlasPool(self: *Self, name: []const u8) !*TextureAtlasPool {
        if (self.atlas.get(name)) |existing| return existing;

        const keyOwned = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(keyOwned);

        const pool = try self.alloc.create(TextureAtlasPool);
        errdefer self.alloc.destroy(pool);

        pool.* = TextureAtlasPool.init(self.alloc, self.gid, freeTextureNoop);
        self.gid += 1;

        try self.atlas.put(keyOwned, pool);
        return pool;
    }

    /// Returns the existing TextureImage pool for `name`, or creates a new
    /// empty pool (consuming one `gid`) and inserts it.
    fn getOrCreateTextureImagePool(self: *Self, name: []const u8) !*TextureImagePool {
        if (self.textures.get(name)) |existing| return existing;

        const keyOwned = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(keyOwned);

        const pool = try self.alloc.create(TextureImagePool);
        errdefer self.alloc.destroy(pool);

        pool.* = TextureImagePool.init(self.alloc, self.gid, freeTextureImage);
        self.gid += 1;

        try self.textures.put(keyOwned, pool);
        return pool;
    }

    /// Returns the existing shader pool for `name`, or creates a new empty
    /// pool (consuming one `gid`) and inserts it.
    fn getOrCreateShaderPool(self: *Self, name: []const u8) !*ShaderPool {
        if (self.shaders.get(name)) |existing| return existing;

        const keyOwned = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(keyOwned);

        const pool = try self.alloc.create(ShaderPool);
        errdefer self.alloc.destroy(pool);

        pool.* = ShaderPool.init(self.alloc, self.gid, freeShader);
        self.gid += 1;

        try self.shaders.put(keyOwned, pool);
        return pool;
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
        const baseName = utils.baseNameFromPath(name);

        var texture: c_uint = undefined;
        gl.genTextures(1, &texture);
        errdefer gl.deleteTextures(1, &texture);

        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        const format = gl.RGBA;
        gl.texImage2D(gl.TEXTURE_2D, 0, format, @intCast(width), @intCast(height), 0, format, gl.UNSIGNED_BYTE, @ptrCast(buffer));

        const imagePool = try self.getOrCreateTextureImagePool(baseName);
        try imagePool.add(.{
            .texture = texture,
            .size = .{ .x = @intCast(width), .y = @intCast(height) },
        });

        const pool = try self.getOrCreateAtlasPool(baseName);
        try pool.add(.{
            .texture = texture,
            .size = .{ .x = @intCast(width), .y = @intCast(height) },
            .src = .{ .t = 0, .l = 0, .b = 1, .r = 1 },
        });

        return &pool.get().?.val;
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
        var image = try stbi.Image.loadFromFile(nt_file_path, 4);
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
            const pool = try self.getOrCreateAtlasPool(frame.name);
            try pool.add(.{
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
        const pool = try self.getOrCreateAtlasPool(name);
        try pool.add(tex.sub(coords));
        return &pool.get().?.val;
    }

    /// Gets a texture by name. Returns an error if no texture with that name
    /// exists. The name is the base name of the file, without the extension,
    /// so "player" would match "player.png" and "player.json" in the case of
    /// an atlas.  Textures within an atlas are accessed by the name specified
    /// with the json.
    pub fn getTexture(self: *Self, name: []const u8) !*Texture {
        const pool = self.atlas.get(name) orelse return error.NoTextureWithThatName;
        const handle = pool.get() orelse return error.NoTextureWithThatName;
        return &handle.val;
    }

    /// Gets a shader by name. Returns an error if no shader with that name
    /// exists.
    pub fn getShaderByName(self: *Self, name: []const u8) !*const Shader {
        const pool = self.shaders.get(name) orelse return error.NoShaderWithThatName;
        const handle = pool.get() orelse return error.NoShaderWithThatName;
        return &handle.val;
    }

    /// Loads a shader from vertex and fragment shader source code, and stores
    /// it in the resource manager with the given name. Calling with an
    /// existing name compiles a fresh shader and marks the prior version
    /// dirty, so live holders can re-acquire to pick up the new program.
    pub fn loadShader(
        self: *Self,
        name: []const u8,
        vs: shaders.ShaderCodePtr,
        fs: shaders.ShaderCodePtr,
    ) !*const Shader {
        const pool = try self.getOrCreateShaderPool(name);
        try pool.add(try Shader.init(vs, fs));
        return &pool.get().?.val;
    }
};
