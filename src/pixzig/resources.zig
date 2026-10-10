const std = @import("std");
const builtin = @import("builtin");
const stbi = @import("zstbi");
const gl = @import("zopengl").bindings;
const common = @import("./common.zig");
const utils = @import("./utils.zig");
const shaders = @import("./renderer/shaders.zig");
const textures = @import("./renderer/textures.zig");
const sprites = @import("./renderer/sprites.zig");
const font_atlas_mod = @import("./renderer/font_atlas.zig");
const file_watcher_mod = @import("./file_watcher.zig");
const tilemap_mod = @import("./tile/tilemap.zig");
const tiled_loader_mod = @import("./tile/tiled_loader.zig");
const paths = @import("./paths.zig");

const TextureImage = textures.TextureImage;
const Texture = textures.Texture;
const Shader = shaders.Shader;
const FontAtlas = font_atlas_mod.FontAtlas;
const CharToColor = textures.CharToColor;
const SpackFile = textures.SpackFile;
const FileWatcher = file_watcher_mod.FileWatcher;
const WatchId = file_watcher_mod.WatchId;
const TileMap = tilemap_mod.TileMap;
const TileSet = tilemap_mod.TileSet;
const TiledMapXmlLoader = tiled_loader_mod.TiledMapXmlLoader;

const Vec2U = common.Vec2U;
const Vec2I = common.Vec2I;
const Color8 = common.Color8;
const RectF = common.RectF;
const RectI = common.RectI;

/// A named asset slot. A handle is a pointer to one: the slot is allocated
/// the first time a name is loaded and stays at that address until the
/// `ResourceManager` deinits, so a handle never dangles and nothing needs to
/// be released.
///
/// Loading the same name again (a hot reload, or a second explicit load)
/// frees the old value and swaps the new one into the same slot, so
/// everything holding the handle uses the new asset with no extra code.
/// Do reloads outside a `begin`/`end` render pass.
pub fn Resource(comptime T: type, comptime freeFn: fn (*T) void) type {
    return struct {
        val: T,
        /// Goes up by one every time `replace` swaps in a new value. A holder
        /// that caches data derived from `val` (a tile mesh built from a map,
        /// attribute locations looked up in a shader) remembers the version
        /// it built from and rebuilds when this no longer matches.
        version: u32 = 0,

        const Self = @This();

        /// Frees the current value and stores `new` in its place.
        pub fn replace(self: *Self, new: T) void {
            freeFn(&self.val);
            self.val = new;
            self.version +%= 1;
        }

        /// Frees the value. Only the owning `ResourceManager` calls this.
        pub fn free(self: *Self) void {
            freeFn(&self.val);
        }
    };
}

/// A named view into a GL texture: a whole image, an atlas frame, or a
/// subtexture. Views own no GL state, so freeing one does nothing.
pub const TextureHandle = Resource(Texture, freeTextureView);

/// A loaded image; owns the GL texture its views draw from. A hot reload
/// re-uploads into the same GL texture object, so views keep working.
pub const TextureImageHandle = Resource(TextureImage, freeTextureImage);

/// A Shader owns its GL program + vertex/fragment shaders.
pub const ShaderHandle = Resource(Shader, freeShader);

/// A FontAtlas owns a GL texture + a char-to-glyph hashmap.
pub const FontAtlasHandle = Resource(FontAtlas, freeFontAtlas);

/// A TileMap owns allocated tile/layer/tileset data.
pub const TileMapHandle = Resource(TileMap, freeTileMap);

fn freeTextureView(_: *Texture) void {}

fn freeTextureImage(t: *TextureImage) void {
    gl.deleteTextures(1, &t.texture);
}

fn freeShader(s: *Shader) void {
    s.deinit();
}

fn freeFontAtlas(fa: *FontAtlas) void {
    fa.deinit();
}

fn freeTileMap(t: *TileMap) void {
    t.deinit();
}

// ---------------------------------------------------------------------------
// Hot-reload support (active in debug builds only)
// ---------------------------------------------------------------------------

/// State needed to reload a specific resource from disk. All string fields
/// are owned by the enclosing `HotReload` instance.
const ReloadInfo = union(enum) {
    texture: struct { name: []const u8, path: []const u8 },
    /// `name` is the resource key the caller chose; `basePath` is the
    /// resolved on-disk path base, without the .png/.json extension.
    atlas: struct { name: []const u8, basePath: []const u8 },
    font_ttf: struct { name: []const u8, path: []const u8, faceIndex: i32 = 0, fontSize: f32 },
    tilemap: struct { name: []const u8, path: []const u8 },

    /// Deep-copy all owned strings into `alloc`. The original slices are
    /// not freed; the caller decides when to release them.
    fn dupe(self: ReloadInfo, alloc: std.mem.Allocator) !ReloadInfo {
        return switch (self) {
            .texture => |t| .{ .texture = .{
                .name = try alloc.dupe(u8, t.name),
                .path = try alloc.dupe(u8, t.path),
            } },
            .atlas => |a| .{ .atlas = .{
                .name = try alloc.dupe(u8, a.name),
                .basePath = try alloc.dupe(u8, a.basePath),
            } },
            .font_ttf => |f| .{ .font_ttf = .{
                .name = try alloc.dupe(u8, f.name),
                .path = try alloc.dupe(u8, f.path),
                .faceIndex = f.faceIndex,
                .fontSize = f.fontSize,
            } },
            .tilemap => |t| .{ .tilemap = .{
                .name = try alloc.dupe(u8, t.name),
                .path = try alloc.dupe(u8, t.path),
            } },
        };
    }

    fn deinit(self: ReloadInfo, alloc: std.mem.Allocator) void {
        switch (self) {
            .texture => |t| {
                alloc.free(t.name);
                alloc.free(t.path);
            },
            .atlas => |a| {
                alloc.free(a.name);
                alloc.free(a.basePath);
            },
            .font_ttf => |f| {
                alloc.free(f.name);
                alloc.free(f.path);
            },
            .tilemap => |t| {
                alloc.free(t.name);
                alloc.free(t.path);
            },
        }
    }
};

/// Groups the `FileWatcher` with its per-file reload info tables.
const HotReload = struct {
    watcher: FileWatcher,
    watches: std.AutoHashMap(WatchId, ReloadInfo),
    pathToId: std.StringHashMap(WatchId),
    alloc: std.mem.Allocator,

    fn init(alloc: std.mem.Allocator) !HotReload {
        return .{
            .watcher = try FileWatcher.init(alloc),
            .watches = std.AutoHashMap(WatchId, ReloadInfo).init(alloc),
            .pathToId = std.StringHashMap(WatchId).init(alloc),
            .alloc = alloc,
        };
    }

    fn deinit(self: *HotReload) void {
        var vit = self.watches.valueIterator();
        while (vit.next()) |info| info.deinit(self.alloc);
        self.watches.deinit();

        var kit = self.pathToId.keyIterator();
        while (kit.next()) |key| self.alloc.free(key.*);
        self.pathToId.deinit();

        self.watcher.deinit();
    }

    /// Register `filePath` as a watched file. `info` slices are borrowed —
    /// this function deep-copies everything it needs to keep. Duplicate
    /// registrations for the same path are silently ignored (the first one
    /// wins), so calling a public load function during hot-reload is safe.
    fn registerWatch(self: *HotReload, filePath: []const u8, info: ReloadInfo) !void {
        if (self.pathToId.contains(filePath)) return;

        const id = try self.watcher.watch(filePath);

        const owned_fp = try self.alloc.dupe(u8, filePath);
        errdefer self.alloc.free(owned_fp);

        const owned_info = try info.dupe(self.alloc);
        errdefer owned_info.deinit(self.alloc);

        try self.pathToId.put(owned_fp, id);
        errdefer _ = self.pathToId.remove(owned_fp);

        try self.watches.put(id, owned_info);
    }
};

// ---------------------------------------------------------------------------
// ResourceManager
// ---------------------------------------------------------------------------

/// Owns all loaded game assets: textures, shaders, atlases, fonts, and tilemaps.
///
/// Every asset lives in a `Resource` slot keyed by name. The `load*`
/// functions, `addSubTexture*`, and the `getX(name)` family (`getTexture`,
/// `getShader`, `getFontAtlas`, `getTileMap`) all return a pointer to that
/// slot. It stays valid until the manager deinits and is never released:
/// load, draw, forget.
///
/// Loading a name that is already registered replaces the value in its
/// slot (see `Resource`), so a `Sprite`, batch or tile renderer holding the
/// handle picks up the new asset on its next draw. Holders that cache data
/// derived from an asset compare `handle.version` to notice.
///
/// Relative file paths are resolved by `paths.resolve` against the build's
/// asset base directory (the executable's own directory once packaged), not
/// the process's current working directory.
///
/// In debug builds, all file-backed resources are watched via `FileWatcher`
/// and reloaded in place when their file changes.
pub const ResourceManager = struct {
    /// Loaded images, keyed by image name. Each owns a GL texture.
    textures: std.StringHashMap(*TextureImageHandle),
    shaders: std.StringHashMap(*ShaderHandle),
    /// Texture views (whole images, atlas frames, subtextures) keyed by the
    /// name `getTexture` looks up.
    atlas: std.StringHashMap(*TextureHandle),
    /// Which frame names each atlas registered, so a reload of the same
    /// atlas isn't mistaken for a collision with another atlas.
    atlasManifests: std.StringHashMap(std.ArrayListUnmanaged([]const u8)),
    fonts: std.StringHashMap(*FontAtlasHandle),
    tilemaps: std.StringHashMap(*TileMapHandle),
    alloc: std.mem.Allocator,
    /// File-change watcher used in debug builds for hot-reload. Always null
    /// in release builds (never initialised). The field type is always
    /// `?HotReload` so the struct layout is uniform across build modes.
    hotReload: ?HotReload,

    const Self = @This();

    /// Initializes the resource manager.
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .textures = std.StringHashMap(*TextureImageHandle).init(alloc),
            .shaders = std.StringHashMap(*ShaderHandle).init(alloc),
            .atlas = std.StringHashMap(*TextureHandle).init(alloc),
            .atlasManifests = std.StringHashMap(std.ArrayListUnmanaged([]const u8)).init(alloc),
            .fonts = std.StringHashMap(*FontAtlasHandle).init(alloc),
            .tilemaps = std.StringHashMap(*TileMapHandle).init(alloc),
            .alloc = alloc,
            .hotReload = null,
        };
    }

    /// Frees all resources and their backing OpenGL objects. Every handle
    /// the manager gave out is invalid afterwards.
    pub fn deinit(self: *Self) void {
        self.freeSlots(TextureHandle, &self.atlas);
        self.freeSlots(TextureImageHandle, &self.textures);
        self.freeSlots(ShaderHandle, &self.shaders);
        self.freeSlots(FontAtlasHandle, &self.fonts);
        self.freeSlots(TileMapHandle, &self.tilemaps);

        var amit = self.atlasManifests.iterator();
        while (amit.next()) |entry| {
            for (entry.value_ptr.items) |name| self.alloc.free(name);
            entry.value_ptr.deinit(self.alloc);
            self.alloc.free(entry.key_ptr.*);
        }
        self.atlasManifests.deinit();

        if (self.hotReload) |*hr| hr.deinit();
    }

    fn freeSlots(self: *Self, comptime H: type, map: *std.StringHashMap(*H)) void {
        var it = map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.free();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        map.deinit();
    }

    /// Stores `val` under `name`: in a new slot the first time, otherwise
    /// replacing (and freeing) the value already there. On error `val` is
    /// not taken, so the caller still owns it.
    fn putSlot(self: *Self, comptime H: type, map: *std.StringHashMap(*H), name: []const u8, val: anytype) !*H {
        if (map.get(name)) |slot| {
            slot.replace(val);
            return slot;
        }

        const key = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(key);
        const slot = try self.alloc.create(H);
        errdefer self.alloc.destroy(slot);
        slot.* = .{ .val = val };
        try map.put(key, slot);
        return slot;
    }

    // -----------------------------------------------------------------------
    // Hot-reload: internal helpers
    // -----------------------------------------------------------------------

    /// Lazily initialise the HotReload state on first use. No-op in release
    /// builds. Logs an error and leaves `hotReload` null if initialisation
    /// fails (watcher remains disabled for the session).
    fn ensureHotReload(self: *Self) void {
        if (comptime builtin.mode != .debug) return;
        if (self.hotReload != null) return;
        self.hotReload = HotReload.init(self.alloc) catch |err| {
            std.log.err("Failed to init file watcher for hot reload: {}", .{err});
            return;
        };
    }

    fn reloadResource(self: *Self, info: ReloadInfo) !void {
        switch (info) {
            .texture => |t| _ = try self.loadTextureImpl(t.name, t.path),
            .atlas => |a| _ = try self.loadAtlasImpl(a.name, a.basePath),
            .font_ttf => |f| {
                var fa = try FontAtlas.initFromTtfFileIndexed(f.path, f.faceIndex, f.fontSize, self.alloc);
                errdefer fa.deinit();
                _ = try self.putSlot(FontAtlasHandle, &self.fonts, f.name, fa);
            },
            .tilemap => |t| {
                std.log.info("Hot reload: reloading tilemap '{s}' from '{s}'", .{ t.name, t.path });
                var map = try TiledMapXmlLoader.initFromFile(t.path, self.alloc);
                errdefer map.deinit();
                _ = try self.putSlot(TileMapHandle, &self.tilemaps, t.name, map);
            },
        }
    }

    /// Poll the file watcher and reload any resources whose source files have
    /// changed since the last call. This is a no-op in release builds.
    /// Called automatically by `AppRunner` each frame.
    pub fn checkHotReload(self: *Self) void {
        if (comptime builtin.mode != .debug) return;
        const hr = if (self.hotReload) |*h| h else return;

        var changed: std.ArrayList(WatchId) = .empty;
        defer changed.deinit(self.alloc);

        hr.watcher.poll(self.alloc, &changed) catch |err| {
            std.log.err("File watcher poll error: {}", .{err});
            return;
        };

        if (changed.items.len > 0) {
            std.log.info("File watcher: {} file change(s) detected", .{changed.items.len});
        }
        for (changed.items) |id| {
            if (hr.watches.get(id)) |info| {
                const type_name = switch (info) {
                    .texture => "texture",
                    .atlas => "atlas",
                    .font_ttf => "font",
                    .tilemap => "tilemap",
                };
                std.log.info("Hot reloading {s} (watch id {})", .{ type_name, id });
                self.reloadResource(info) catch |err| {
                    std.log.warn("Hot reload failed for watch id {}: {}", .{ id, err });
                };
            } else {
                std.log.warn("File watcher fired for unknown watch id {}", .{id});
            }
        }
    }

    // -----------------------------------------------------------------------
    // Texture loading
    // -----------------------------------------------------------------------

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
    ) !*TextureHandle {
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

    /// Uploads RGBA `pixels` as the image `name`, and registers a view of the
    /// whole image under the same name. A first load creates the GL texture;
    /// a reload re-uploads into the existing one, so every view of the image
    /// (atlas frames, subtextures) keeps a valid GL texture id.
    fn uploadImage(
        self: *Self,
        name: []const u8,
        width: usize,
        height: usize,
        pixels: []const u8,
    ) !*TextureHandle {
        const size: Vec2U = .{ .x = @intCast(width), .y = @intCast(height) };

        const image = if (self.textures.get(name)) |existing| blk: {
            existing.val.size = size;
            existing.version +%= 1;
            break :blk existing;
        } else blk: {
            var texture: c_uint = undefined;
            gl.genTextures(1, &texture);
            errdefer gl.deleteTextures(1, &texture);

            gl.bindTexture(gl.TEXTURE_2D, texture);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
            break :blk try self.putSlot(TextureImageHandle, &self.textures, name, TextureImage{
                .texture = texture,
                .size = size,
            });
        };

        gl.bindTexture(gl.TEXTURE_2D, image.val.texture);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @intCast(width), @intCast(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, @ptrCast(pixels));

        return self.putSlot(TextureHandle, &self.atlas, name, Texture{
            .texture = image.val.texture,
            .size = size,
            .src = .{ .t = 0, .l = 0, .b = 1, .r = 1 },
        });
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
        buffer: []const u8,
    ) !*TextureHandle {
        return self.uploadImage(utils.baseNameFromPath(name), width, height, buffer);
    }

    /// Internal: loads a texture from a file without registering a hot-reload
    /// watch. Called from `loadTexture` (which adds the watch) and from the
    /// hot-reload path.
    fn loadTextureImpl(
        self: *Self,
        name: []const u8,
        filePath: []const u8,
    ) !*TextureHandle {
        var image = try self.decodeImage(name, filePath);
        defer image.deinit();
        return self.uploadImage(utils.baseNameFromPath(name), image.width, image.height, image.data);
    }

    fn decodeImage(self: *Self, name: []const u8, filePath: []const u8) !stbi.Image {
        std.log.info("Loading image '{s}' from '{s}'\n", .{ name, filePath });
        const nt_file_path = try std.mem.concatWithSentinel(self.alloc, u8, &.{filePath}, 0);
        defer self.alloc.free(nt_file_path);

        const image = try stbi.Image.loadFromFile(nt_file_path, 4);
        std.log.info("Loaded image '{s}', width={}, height={}\n", .{ name, image.width, image.height });
        return image;
    }

    /// Loads a texture from a file path. The name is the base name of the
    /// file, without the extension, so "player" would match "player.png".
    /// The texture is stored in the atlas with the base name, so it can be
    /// accessed with `getTexture` using that name.  The file type is
    /// determined from the file extension, and should be a type supported
    /// by the `stbi` library, such as png or jpg.
    ///
    /// In debug builds, the file is watched and the texture is reloaded in
    /// place when it changes.
    pub fn loadTexture(
        self: *Self,
        name: []const u8,
        filePath: []const u8,
    ) !*TextureHandle {
        const resolved = try paths.resolve(self.alloc, filePath);
        defer self.alloc.free(resolved);

        const result = try self.loadTextureImpl(name, resolved);

        if (comptime builtin.mode == .debug) {
            self.ensureHotReload();
            if (self.hotReload) |*hr| {
                hr.registerWatch(resolved, .{
                    .texture = .{ .name = name, .path = resolved },
                }) catch |err| {
                    std.log.warn("Could not register texture watch for '{s}': {}", .{ resolved, err });
                };
            }
        }

        return result;
    }

    // -----------------------------------------------------------------------
    // Atlas loading
    // -----------------------------------------------------------------------

    /// Internal: loads a texture atlas without registering hot-reload watches.
    /// `name` is the resource key; `basePath` is the file path base (without
    /// extension). When both are equal this is an ordinary loadAtlas call.
    ///
    /// Everything that can fail on bad input (reading and parsing the JSON,
    /// frame name collisions, decoding the PNG) happens before any slot is
    /// touched, so a broken atlas file leaves the previous load drawing.
    fn loadAtlasImpl(self: *Self, name: []const u8, basePath: []const u8) !usize {
        const jsonName = try utils.addExtension(self.alloc, basePath, ".json");
        defer self.alloc.free(jsonName);

        const io = std.Io.Threaded.global_single_threaded.io();
        const file_contents = try std.Io.Dir.cwd().readFileAlloc(io, jsonName, self.alloc, .unlimited);
        defer self.alloc.free(file_contents);

        const parsed = try std.json.parseFromSlice(SpackFile, self.alloc, file_contents, .{});
        defer parsed.deinit();

        const spack = parsed.value;

        // Reject frame names that collide with a texture/frame owned by a
        // different atlas (or a plain loaded texture). Frames already owned
        // by this same atlas from a prior load are an expected reload, not a
        // collision.
        const prev_frames: ?[]const []const u8 = if (self.atlasManifests.get(name)) |pm| pm.items else null;
        for (spack.frames) |frame| {
            if (self.atlas.contains(frame.name) and !ownedByFrameList(prev_frames, frame.name)) {
                std.log.err("AssetManifest: atlas '{s}' frame '{s}' collides with an existing texture owned elsewhere", .{ name, frame.name });
                return error.AtlasFrameNameCollision;
            }
        }

        const imageName = try utils.addExtension(self.alloc, basePath, ".png");
        defer self.alloc.free(imageName);
        var decoded = try self.decodeImage(name, imageName);
        defer decoded.deinit();

        const whole = try self.uploadImage(utils.baseNameFromPath(name), decoded.width, decoded.height, decoded.data);
        const sz: Vec2I = whole.val.size.asVec2I();

        const gop = try self.atlasManifests.getOrPut(name);
        if (!gop.found_existing) {
            gop.key_ptr.* = self.alloc.dupe(u8, name) catch |err| {
                self.atlasManifests.removeByPtr(gop.key_ptr);
                return err;
            };
            gop.value_ptr.* = .empty;
        }
        const manifest = gop.value_ptr;

        for (spack.frames) |frame| {
            _ = try self.putSlot(TextureHandle, &self.atlas, frame.name, Texture{
                .texture = whole.val.texture,
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

            // A frame dropped from the JSON keeps its slot (handles to it
            // must stay valid) and stays listed here, so it still counts as
            // this atlas's own name.
            if (!ownedByFrameList(manifest.items, frame.name)) {
                const name_owned = try self.alloc.dupe(u8, frame.name);
                errdefer self.alloc.free(name_owned);
                try manifest.append(self.alloc, name_owned);
            }
        }

        return spack.frames.len;
    }

    fn ownedByFrameList(frames: ?[]const []const u8, frame_name: []const u8) bool {
        const list = frames orelse return false;
        for (list) |n| {
            if (std.mem.eql(u8, n, frame_name)) return true;
        }
        return false;
    }

    /// Loads a texture atlas from a base name. This looks for a .png and
    /// .json file with the given base name, and loads the texture and
    /// subtextures specified in the json file. The json file should be in the
    /// format of a `SpackFile`, which is the format used by our internal
    /// `TexturePacker` tool.
    ///
    /// The subtextures are stored in the atlas with their names from the json
    /// file, so they can be accessed with `getTexture` using those names.
    ///
    /// In debug builds, both the .png and .json files are watched; any change
    /// to either triggers a full atlas reload.
    pub fn loadAtlas(self: *Self, baseName: []const u8) !usize {
        return self.loadAtlasNamed(baseName, baseName);
    }

    /// Like `loadAtlas` but stores the resource under `name` instead of the
    /// base name of `basePath`. Use this when the manifest asset id should
    /// differ from the file name on disk (e.g. id="main_sprites", path="pac-tiles").
    /// After loading, `getTexture(name)` returns the full atlas image;
    /// individual frames remain accessible by their frame names.
    pub fn loadAtlasNamed(self: *Self, name: []const u8, basePath: []const u8) !usize {
        const resolved = try paths.resolve(self.alloc, basePath);
        defer self.alloc.free(resolved);

        const num = try self.loadAtlasImpl(name, resolved);

        if (comptime builtin.mode == .debug) {
            self.ensureHotReload();
            if (self.hotReload) |*hr| {
                const imageName = try utils.addExtension(self.alloc, resolved, ".png");
                defer self.alloc.free(imageName);
                const jsonName = try utils.addExtension(self.alloc, resolved, ".json");
                defer self.alloc.free(jsonName);

                hr.registerWatch(imageName, .{ .atlas = .{ .name = name, .basePath = resolved } }) catch |err| {
                    std.log.warn("Could not register atlas PNG watch for '{s}': {}", .{ imageName, err });
                };
                hr.registerWatch(jsonName, .{ .atlas = .{ .name = name, .basePath = resolved } }) catch |err| {
                    std.log.warn("Could not register atlas JSON watch for '{s}': {}", .{ jsonName, err });
                };
            }
        }

        return num;
    }

    /// Adds a named subtexture from a region of an existing texture. `px` is
    /// in pixels, relative to `tex`'s own top-left corner (so a subtexture of
    /// a subtexture or atlas frame works as expected). The region is cut
    /// once, from `tex` as it is now.
    pub fn addSubTexture(
        self: *Self,
        tex: *const TextureHandle,
        name: []const u8,
        px: RectI,
    ) !*TextureHandle {
        return self.putSlot(TextureHandle, &self.atlas, name, Texture{
            .texture = tex.val.texture,
            .size = .{ .x = @intCast(px.width()), .y = @intCast(px.height()) },
            .src = sprites.pixelsToUv(&tex.val, px),
        });
    }

    /// Like `addSubTexture`, but `coords` are in the underlying image's UV
    /// space: (0,0) is top-left, (1,1) is bottom-right.
    pub fn addSubTextureUV(
        self: *Self,
        tex: *const TextureHandle,
        name: []const u8,
        coords: RectF,
    ) !*TextureHandle {
        return self.putSlot(TextureHandle, &self.atlas, name, tex.val.sub(coords));
    }

    /// Creates a `Sprite` for the texture (or atlas frame / subtexture)
    /// registered as `name`.
    pub fn createSprite(self: *Self, name: []const u8) !sprites.Sprite {
        return sprites.Sprite.create(try self.getTexture(name));
    }

    /// The texture (or atlas frame / subtexture) registered as `name`.
    pub fn getTexture(self: *Self, name: []const u8) !*TextureHandle {
        return self.atlas.get(name) orelse error.NoTextureWithThatName;
    }

    // -----------------------------------------------------------------------
    // Font loading
    // -----------------------------------------------------------------------

    /// Loads a TTF font from disk and registers it under `name`. A second
    /// call with the same name replaces the atlas in place.
    ///
    /// In debug builds, the file is watched and the font is reloaded in
    /// place when it changes.
    pub fn loadFontFromTtfFile(
        self: *Self,
        name: []const u8,
        fontPath: []const u8,
        fontSize: f32,
    ) !*FontAtlasHandle {
        return self.loadFontFromTtfFileIndexed(name, fontPath, 0, fontSize);
    }

    /// Like `loadFontFromTtfFile`, but `faceIndex` selects a face inside a
    /// TrueType/OpenType collection (`.ttc`). Use 0 for a plain font file.
    pub fn loadFontFromTtfFileIndexed(
        self: *Self,
        name: []const u8,
        fontPath: []const u8,
        faceIndex: i32,
        fontSize: f32,
    ) !*FontAtlasHandle {
        const resolved = try paths.resolve(self.alloc, fontPath);
        defer self.alloc.free(resolved);

        var fa = try FontAtlas.initFromTtfFileIndexed(resolved, faceIndex, fontSize, self.alloc);
        errdefer fa.deinit();
        const handle = try self.putSlot(FontAtlasHandle, &self.fonts, name, fa);

        if (comptime builtin.mode == .debug) {
            self.ensureHotReload();
            if (self.hotReload) |*hr| {
                hr.registerWatch(resolved, .{
                    .font_ttf = .{ .name = name, .path = resolved, .faceIndex = faceIndex, .fontSize = fontSize },
                }) catch |err| {
                    std.log.warn("Could not register font watch for '{s}': {}", .{ resolved, err });
                };
            }
        }

        return handle;
    }

    /// Loads a TTF/OTF font from bytes in memory (e.g. an `@embedFile`) and
    /// registers it under `name`. The atlas copies `fontData`.
    pub fn loadFontFromTtfData(
        self: *Self,
        name: []const u8,
        fontData: []const u8,
        faceIndex: i32,
        fontSize: f32,
    ) !*FontAtlasHandle {
        var fa = try FontAtlas.initFromTtfData(fontData, faceIndex, fontSize, self.alloc);
        errdefer fa.deinit();
        return self.putSlot(FontAtlasHandle, &self.fonts, name, fa);
    }

    /// Loads a TTF font embedded at comptime into the binary and registers
    /// it under `name`.
    pub fn loadFontFromTtfEmbedded(
        self: *Self,
        name: []const u8,
        comptime fontPath: []const u8,
        fontSize: f32,
    ) !*FontAtlasHandle {
        var fa = try FontAtlas.initFromTtfEmbedded(fontPath, fontSize, self.alloc);
        errdefer fa.deinit();
        return self.putSlot(FontAtlasHandle, &self.fonts, name, fa);
    }

    /// Loads a fixed-cell bitmap font and registers it under `name`.
    pub fn loadFontFromBitmap(
        self: *Self,
        name: []const u8,
        fontImagePath: []const u8,
        charWidth: i32,
        charHeight: i32,
        charsPerRow: i32,
        chars: []const u8,
    ) !*FontAtlasHandle {
        const resolved = try paths.resolve(self.alloc, fontImagePath);
        defer self.alloc.free(resolved);

        var fa = try FontAtlas.initFromBitmap(resolved, charWidth, charHeight, charsPerRow, chars, self.alloc);
        errdefer fa.deinit();
        return self.putSlot(FontAtlasHandle, &self.fonts, name, fa);
    }

    /// The font atlas registered as `name`.
    pub fn getFontAtlas(self: *Self, name: []const u8) !*FontAtlasHandle {
        return self.fonts.get(name) orelse error.NoFontWithThatName;
    }

    /// Appends a fallback face to an already-loaded TTF font. Codepoints the
    /// primary face (and any earlier fallback) lacks are then filled from
    /// this face. `faceIndex` selects a face inside a `.ttc` collection; use
    /// 0 for a plain font file.
    ///
    /// Note: a hot-reload of the primary font file rebuilds the atlas from
    /// that file alone and drops fallbacks; re-add them after a reload if it
    /// matters for the build.
    pub fn addFontFallback(self: *Self, name: []const u8, fontPath: []const u8, faceIndex: i32) !void {
        const handle = try self.getFontAtlas(name);

        const resolved = try paths.resolve(self.alloc, fontPath);
        defer self.alloc.free(resolved);

        try handle.val.addFallbackFaceFromFile(resolved, faceIndex, self.alloc);
    }

    // -----------------------------------------------------------------------
    // TileMap loading
    // -----------------------------------------------------------------------

    /// Loads a Tiled map from a .tmx file and registers it under `name`.
    /// A second call with the same name replaces the map in place and bumps
    /// the handle's `version`, which is how `TileMapRenderer` knows to
    /// rebuild.
    ///
    /// In debug builds, the .tmx file is watched and the map is reloaded in
    /// place when it changes.
    pub fn loadTileMap(self: *Self, name: []const u8, path: []const u8) !*TileMapHandle {
        const resolved = try paths.resolve(self.alloc, path);
        defer self.alloc.free(resolved);

        var map = try TiledMapXmlLoader.initFromFile(resolved, self.alloc);
        errdefer map.deinit();
        const handle = try self.putSlot(TileMapHandle, &self.tilemaps, name, map);

        if (comptime builtin.mode == .debug) {
            self.ensureHotReload();
            if (self.hotReload) |*hr| {
                hr.registerWatch(resolved, .{
                    .tilemap = .{ .name = name, .path = resolved },
                }) catch |err| {
                    std.log.warn("Could not register tilemap watch for '{s}': {}", .{ resolved, err });
                };
            }
        }

        return handle;
    }

    /// Registers a tilemap that was built in code rather than loaded from a
    /// .tmx, under `name`. The manager takes ownership of `map`, so the
    /// caller must not deinit it; as with `loadTileMap`, a second call with
    /// the same name replaces the map in place.
    ///
    /// Nothing is watched for changes -- there is no file behind it.
    pub fn addTileMap(self: *Self, name: []const u8, map: TileMap) !*TileMapHandle {
        return self.putSlot(TileMapHandle, &self.tilemaps, name, map);
    }

    /// Returns the texture a tileset draws from, loading it on the first call
    /// if nothing is registered under that name yet.
    ///
    /// The name is the base name of the tileset's `<image source>` -- the
    /// tileset image `../art/tiles.png` is registered as `"tiles"` -- so a
    /// texture the game loaded under that name is reused rather than loaded a
    /// second time. Otherwise the path is read relative to `map.sourcePath`,
    /// the .tmx the tileset came from.
    pub fn tilesetTexture(self: *Self, map: *const TileMap, tileset: *const TileSet) !*TextureHandle {
        const source = tileset.imageSource orelse return error.TilesetHasNoImage;
        const name = utils.baseNameFromPath(source);

        if (self.atlas.contains(name)) return self.getTexture(name);

        const image_path = try self.tilesetImagePath(map, source);
        defer self.alloc.free(image_path);

        return self.loadTexture(name, image_path);
    }

    /// Joins a tileset's `<image source>` onto the directory holding the .tmx
    /// it came from. An absolute source, or a map with no file behind it, is
    /// used as-is and so resolves against the asset base like any other path.
    /// Caller owns the returned buffer.
    fn tilesetImagePath(self: *Self, map: *const TileMap, source: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(source)) return self.alloc.dupe(u8, source);

        const map_path = map.sourcePath orelse return self.alloc.dupe(u8, source);
        const dir = std.fs.path.dirname(map_path) orelse return self.alloc.dupe(u8, source);

        // `loadTileMap` resolves against the asset base before loading, so an
        // absolute map path is the normal case and `resolve` can fold away the
        // `..` segments Tiled likes to emit. A relative one (Emscripten, where
        // there is no base directory) must stay relative, so it is only
        // joined.
        if (std.fs.path.isAbsolute(dir)) {
            return std.fs.path.resolve(self.alloc, &.{ dir, source });
        }
        return std.fs.path.join(self.alloc, &.{ dir, source });
    }

    /// The tilemap registered as `name`.
    pub fn getTileMap(self: *Self, name: []const u8) !*TileMapHandle {
        return self.tilemaps.get(name) orelse error.NoTileMapWithThatName;
    }

    // -----------------------------------------------------------------------
    // Shader loading
    // -----------------------------------------------------------------------

    /// The shader registered as `name`.
    pub fn getShader(self: *Self, name: []const u8) !*ShaderHandle {
        return self.shaders.get(name) orelse error.NoShaderWithThatName;
    }

    /// Loads a shader from vertex and fragment shader source code, and stores
    /// it in the resource manager with the given name. Calling with an
    /// existing name compiles a fresh program and replaces the old one in
    /// place; holders re-look-up their uniform/attribute locations when the
    /// handle's `version` changes.
    pub fn loadShader(
        self: *Self,
        name: []const u8,
        vs: shaders.ShaderCodePtr,
        fs: shaders.ShaderCodePtr,
    ) !*ShaderHandle {
        var shader = try Shader.init(vs, fs);
        errdefer shader.deinit();
        return self.putSlot(ShaderHandle, &self.shaders, name, shader);
    }
};
