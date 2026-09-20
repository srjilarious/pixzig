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
const TiledMapXmlLoader = tiled_loader_mod.TiledMapXmlLoader;

const Vec2U = common.Vec2U;
const Vec2I = common.Vec2I;
const Color8 = common.Color8;
const RectF = common.RectF;
const RectI = common.RectI;

/// A pool of refcounted, hot-reloadable assets of type `T`, keyed by a
/// user-supplied `u32` id. Multiple generations of the same id may coexist:
/// adding a new version marks any older live version dirty so holders can
/// notice and re-acquire, while unreferenced older versions are reclaimed
/// immediately.
///
/// Handles returned by `add` / `acquire` are heap-allocated and remain at
/// stable addresses for their full lifetime, so callers may hold raw
/// `*Handle` pointers across `add` calls.
///
/// Each `Handle` carries a back-pointer to its parent `ManagedResource` so
/// callers only need to store one pointer. Call `handle.release()` to
/// decrement the refcount, and `handle.reacquire()` to atomically upgrade to
/// the latest generation after a hot-reload.
pub fn ManagedResource(comptime ResourceName: []const u8, comptime T: type) type {
    return struct {
        res: std.ArrayList(?*Handle),
        alloc: std.mem.Allocator,
        freeFunc: Handle.FreeFunc,
        id: u32,
        /// The name the resource is registered under, used in leak and
        /// error logs. Borrowed: the `ResourceManager` owns the bytes (its
        /// map key) and frees them only after this resource is deinited.
        name: []const u8,
        gen: u32,
        /// When true, superseded generations are never freed before
        /// `deinit`, even at refCount 0. The `ResourceManager` sets this for
        /// textures in debug builds so a borrowed (unreferenced) handle from
        /// `getTexture` can't dangle after a hot-reload.
        keepStale: bool = false,

        const Self = @This();

        /// A reference-counted, generation-tracked handle to an asset of
        /// type `T`. Obtained via `ManagedResource.acquire`. Holders should
        /// call `release` when done and `reacquire` when `dirty` is true.
        pub const Handle = struct {
            id: u32,
            generation: u32,
            refCount: u32,
            dirty: bool,
            val: T,
            parent: *Self,

            pub const FreeFunc = *const fn (T) void;

            /// Upgrades to the latest generation from the parent, releasing
            /// the current handle when it has been superseded. Returns the
            /// new handle, or `self` when no newer generation exists yet.
            pub fn reacquire(self: *Handle) *Handle {
                const new = self.parent.latest() orelse return self;
                if (new == self) return self;
                new.refCount += 1;
                std.debug.assert(self.refCount > 0);
                self.refCount -= 1;
                if (self.refCount == 0 and self.dirty and !self.parent.keepStale) {
                    self.parent.freeHandle(self);
                }
                return new;
            }

            pub fn release(self: *Handle) void {
                self.parent.release(self);
            }

            /// Adds a reference to this exact generation (unlike `acquire`,
            /// which takes the latest). Pair with `release`.
            pub fn retain(self: *Handle) *Handle {
                self.refCount += 1;
                return self;
            }
        };

        pub fn init(alloc: std.mem.Allocator, id: u32, name: []const u8, freeFunc: Handle.FreeFunc) Self {
            return .{
                .res = .empty,
                .alloc = alloc,
                .freeFunc = freeFunc,
                .id = id,
                .name = name,
                .gen = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.res.items) |hOpt| {
                if (hOpt) |h| {
                    if (h.refCount != 0) {
                        std.log.err("{s} '{s}' (generation {}): refCount = {} on deinit, a handle was never released", .{ ResourceName, self.name, h.generation, h.refCount });
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
            // Free unreferenced old versions first. Safe even if the insert
            // below fails (refCount == 0 means no caller holds these), and
            // creates null slots that insertHandle can reuse without allocating.
            for (self.res.items, 0..) |hOpt, i| {
                if (hOpt) |h| {
                    if (h.refCount == 0 and !self.keepStale) {
                        self.freeFunc(h.val);
                        self.alloc.destroy(h);
                        self.res.items[i] = null;
                    }
                }
            }

            const handle = try self.alloc.create(Handle);
            errdefer self.alloc.destroy(handle);
            handle.* = .{
                .id = self.id,
                .generation = self.gen + 1,
                .refCount = 0,
                .dirty = false,
                .val = obj,
                .parent = self,
            };

            try self.insertHandle(handle);

            // Only mark still-referenced handles dirty after insertion succeeds.
            // If insertHandle had failed, marking them dirty would leave callers
            // with handles that get freed on release even though no new version exists.
            self.gen += 1;
            for (self.res.items) |hOpt| {
                if (hOpt) |h| {
                    if (h != handle) h.dirty = true;
                }
            }
        }

        /// Undo a just-added generation that has not been acquired by callers.
        /// Used by multi-resource loaders to roll back partial commits.
        pub fn rollbackAdd(self: *Self, generation: u32) bool {
            for (self.res.items, 0..) |hOpt, i| {
                if (hOpt) |h| {
                    if (h.generation == generation) {
                        if (h.refCount != 0) return false;
                        self.freeFunc(h.val);
                        self.alloc.destroy(h);
                        self.res.items[i] = null;
                        self.recomputeDirtyFlags();
                        return true;
                    }
                }
            }
            return false;
        }

        /// Increment the refCount on the latest live handle for the resource.
        /// Returns null if nothing is registered under `id`.
        pub fn acquire(self: *Self) ?*Handle {
            const latestHandle = self.latest() orelse return null;
            latestHandle.refCount += 1;
            return latestHandle;
        }

        /// Decrement the refCount. A dirty handle dropping to refCount == 0
        /// is freed and its slot reclaimed. Clean handles at refCount == 0
        /// are retained so subsequent `acquire` calls still hit.
        pub fn release(self: *Self, handle: *Handle) void {
            std.debug.assert(handle.refCount > 0);
            handle.refCount -= 1;
            if (handle.refCount == 0 and handle.dirty and !self.keepStale) {
                self.freeHandle(handle);
            }
        }

        /// Latest live handle for the resource without bumping refCount.
        /// Useful for peeking; prefer `acquire` for anything that outlives
        /// one frame.
        pub fn get(self: *Self) ?*Handle {
            return self.latest();
        }

        fn latest(self: *Self) ?*Handle {
            var latestHandle: ?*Handle = null;
            for (self.res.items) |hOpt| {
                if (hOpt) |h| {
                    if (latestHandle == null or h.generation > latestHandle.?.generation) {
                        latestHandle = h;
                    }
                }
            }
            return latestHandle;
        }

        fn recomputeDirtyFlags(self: *Self) void {
            const latestHandle = self.latest();
            for (self.res.items) |hOpt| {
                if (hOpt) |h| {
                    h.dirty = if (latestHandle) |latest_handle|
                        h.generation < latest_handle.generation
                    else
                        false;
                }
            }
        }

        fn insertHandle(self: *Self, handle: *Handle) !void {
            for (self.res.items) |*slot| {
                if (slot.* == null) {
                    slot.* = handle;
                    return;
                }
            }
            try self.res.append(self.alloc, handle);
        }

        fn freeHandle(self: *Self, handle: *Handle) void {
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
/// value owns no GL state itself, but a view added by the ResourceManager
/// holds a reference on its `TextureImage` generation, released when the
/// view is reclaimed.
pub const ManagedTexture = ManagedResource("Texture", Texture);

/// Debug builds keep superseded texture generations alive until the manager
/// deinits, so borrowed handles (`getTexture`, `load*` return values) stay
/// valid across hot-reloads. Release builds reclaim them eagerly.
pub const keepStaleTextures = builtin.mode == .debug;

/// A TextureImage owns the GL texture handle. Reclaiming a stale
/// TextureImage deletes the GL handle.
pub const ManagedTextureImage = ManagedResource("TextureImage", TextureImage);

/// A Shader owns its GL program + vertex/fragment shaders. The managed resource
/// stores shaders by value; pointer stability comes from the heap-allocated
/// `Handle` inside the managed resource.
pub const ManagedShader = ManagedResource("Shader", Shader);

/// A FontAtlas owns a GL texture + a char-to-glyph hashmap. Stored by value
/// inside the managed resource.
pub const ManagedFont = ManagedResource("Font", FontAtlas);

/// A TileMap owns allocated tile/layer/tileset data. Stored by value inside
/// the managed resource; the free function calls deinit to release all memory.
pub const ManagedTileMap = ManagedResource("TileMap", TileMap);

pub const TextureHandle = ManagedTexture.Handle;
pub const TextureImageHandle = ManagedTextureImage.Handle;
pub const ShaderHandle = ManagedShader.Handle;
pub const FontAtlasHandle = ManagedFont.Handle;
pub const TileMapHandle = ManagedTileMap.Handle;

fn freeTextureView(t: Texture) void {
    if (t.image) |image| image.release();
}

fn freeTextureImage(t: TextureImage) void {
    gl.deleteTextures(1, &t.texture);
}

fn freeShader(s: Shader) void {
    var copy = s;
    copy.deinit();
}

fn freeFontAtlas(fa: FontAtlas) void {
    var copy = fa;
    copy.deinit();
}

fn freeTileMap(t: TileMap) void {
    var copy = t;
    copy.deinit();
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
/// Each resource type is stored in a `ManagedResource` pool that supports multiple
/// generations and ref-counting.
///
/// Every resource type has the same two ways in:
/// - Borrowed: the `load*` functions, `addSubTexture*`, and the `getX(name)`
///   family (`getTexture`, `getShader`, `getFontAtlas`, `getTileMap`) return a
///   handle without taking a reference. Never release it; it stays valid
///   until the manager deinits (for textures in debug builds even across
///   hot-reloads; in release builds re-loading the same name frees an
///   unreferenced older generation). This is the simple path: load, draw,
///   forget.
/// - Owned: the `acquireX(name)` family (`acquireTexture`, `acquireShader`,
///   `acquireFontAtlas`, `acquireTileMap`) bumps the refcount; call
///   `handle.release()` when done. Use this when something must keep the
///   resource alive on its own.
///
/// A `Sprite`, batch queue or tile renderer given a handle of either kind
/// retains its own reference and releases it in `deinit`.
///
/// Relative file paths are resolved by `paths.resolve` against the build's
/// asset base directory (the executable's own directory once packaged), not
/// the process's current working directory.
///
/// In debug builds, all file-backed resources are watched via `FileWatcher`.
/// When a file changes, the resource is reloaded and live handles are marked
/// dirty so callers can call `handle.reacquire()` to upgrade to the new version.
pub const ResourceManager = struct {
    textures: std.StringHashMap(*ManagedTextureImage),
    shaders: std.StringHashMap(*ManagedShader),
    atlas: std.StringHashMap(*ManagedTexture),
    /// Tracks which frame names each atlas registered so stale frames can be
    /// removed when the atlas JSON changes during hot-reload.
    atlasManifests: std.StringHashMap(std.ArrayListUnmanaged([]const u8)),
    fonts: std.StringHashMap(*ManagedFont),
    tilemaps: std.StringHashMap(*ManagedTileMap),
    alloc: std.mem.Allocator,
    /// Monotonic id assigned to each new ManagedResource the manager owns.
    /// Lookups inside a managed resource use generations; this id distinguishes
    /// each managed resource.
    gid: u32,
    /// File-change watcher used in debug builds for hot-reload. Always null
    /// in release builds (never initialised). The field type is always
    /// `?HotReload` so the struct layout is uniform across build modes.
    hotReload: ?HotReload,

    const Self = @This();

    const TextureLoad = struct {
        managed: *ManagedTexture,
        imageManaged: *ManagedTextureImage,
        atlasGeneration: u32,
        imageGeneration: u32,
    };

    const AtlasFrameLoad = struct {
        managed: *ManagedTexture,
        generation: u32,
    };

    /// Initializes the resource manager.
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .textures = std.StringHashMap(*ManagedTextureImage).init(alloc),
            .shaders = std.StringHashMap(*ManagedShader).init(alloc),
            .atlas = std.StringHashMap(*ManagedTexture).init(alloc),
            .atlasManifests = std.StringHashMap(std.ArrayListUnmanaged([]const u8)).init(alloc),
            .fonts = std.StringHashMap(*ManagedFont).init(alloc),
            .tilemaps = std.StringHashMap(*ManagedTileMap).init(alloc),
            .alloc = alloc,
            .gid = 0,
            .hotReload = null,
        };
    }

    /// Frees all managed resources and their backing OpenGL objects.
    /// All handles must be released before calling this.
    pub fn deinit(self: *Self) void {
        // Views hold references on their images, so free them first.
        var it = self.atlas.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        self.atlas.deinit();

        var tit = self.textures.iterator();
        while (tit.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        self.textures.deinit();

        var amit = self.atlasManifests.iterator();
        while (amit.next()) |entry| {
            for (entry.value_ptr.items) |name| self.alloc.free(name);
            entry.value_ptr.deinit(self.alloc);
            self.alloc.free(entry.key_ptr.*);
        }
        self.atlasManifests.deinit();

        var sit = self.shaders.iterator();
        while (sit.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        self.shaders.deinit();

        var fit = self.fonts.iterator();
        while (fit.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        self.fonts.deinit();

        var tmit = self.tilemaps.iterator();
        while (tmit.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.alloc.destroy(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.*);
        }
        self.tilemaps.deinit();

        if (self.hotReload) |*hr| hr.deinit();
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
                const fa = try FontAtlas.initFromTtfFileIndexed(f.path, f.faceIndex, f.fontSize, self.alloc);
                const managed = try self.getOrCreateFont(f.name);
                try managed.add(fa);
            },
            .tilemap => |t| {
                std.log.info("Hot reload: reloading tilemap '{s}' from '{s}'", .{ t.name, t.path });
                const map = try TiledMapXmlLoader.initFromFile(t.path, self.alloc);
                const managed = try self.getOrCreateTileMap(t.name);
                try managed.add(map);
                std.log.info("Hot reload: tilemap '{s}' reloaded, {} live handles marked dirty", .{
                    t.name,
                    blk: {
                        var n: usize = 0;
                        for (managed.res.items) |h| if (h != null and h.?.dirty) {
                            n += 1;
                        };
                        break :blk n;
                    },
                });
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
    // Internal managed resource helpers
    // -----------------------------------------------------------------------

    fn getOrCreateAtlasTexture(self: *Self, name: []const u8) !*ManagedTexture {
        if (self.atlas.get(name)) |existing| return existing;

        const keyOwned = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(keyOwned);

        const managed = try self.alloc.create(ManagedTexture);
        errdefer self.alloc.destroy(managed);

        managed.* = ManagedTexture.init(self.alloc, self.gid, keyOwned, freeTextureView);
        managed.keepStale = keepStaleTextures;
        self.gid += 1;

        try self.atlas.put(keyOwned, managed);
        return managed;
    }

    fn getOrCreateTextureImage(self: *Self, name: []const u8) !*ManagedTextureImage {
        if (self.textures.get(name)) |existing| return existing;

        const keyOwned = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(keyOwned);

        const managed = try self.alloc.create(ManagedTextureImage);
        errdefer self.alloc.destroy(managed);

        managed.* = ManagedTextureImage.init(self.alloc, self.gid, keyOwned, freeTextureImage);
        self.gid += 1;

        try self.textures.put(keyOwned, managed);
        return managed;
    }

    fn getOrCreateShader(self: *Self, name: []const u8) !*ManagedShader {
        if (self.shaders.get(name)) |existing| return existing;

        const keyOwned = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(keyOwned);

        const managed = try self.alloc.create(ManagedShader);
        errdefer self.alloc.destroy(managed);

        managed.* = ManagedShader.init(self.alloc, self.gid, keyOwned, freeShader);
        self.gid += 1;

        try self.shaders.put(keyOwned, managed);
        return managed;
    }

    fn getOrCreateTileMap(self: *Self, name: []const u8) !*ManagedTileMap {
        if (self.tilemaps.get(name)) |existing| return existing;

        const keyOwned = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(keyOwned);

        const managed = try self.alloc.create(ManagedTileMap);
        errdefer self.alloc.destroy(managed);

        managed.* = ManagedTileMap.init(self.alloc, self.gid, keyOwned, freeTileMap);
        self.gid += 1;

        try self.tilemaps.put(keyOwned, managed);
        return managed;
    }

    fn getOrCreateFont(self: *Self, name: []const u8) !*ManagedFont {
        if (self.fonts.get(name)) |existing| return existing;

        const keyOwned = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(keyOwned);

        const managed = try self.alloc.create(ManagedFont);
        errdefer self.alloc.destroy(managed);

        managed.* = ManagedFont.init(self.alloc, self.gid, keyOwned, freeFontAtlas);
        self.gid += 1;

        try self.fonts.put(keyOwned, managed);
        return managed;
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

    /// Adds `view` as the newest generation of `managed`, taking a reference
    /// on `view.image` for as long as that generation lives.
    fn addTextureView(_: *Self, managed: *ManagedTexture, view: Texture) !void {
        if (view.image) |image| _ = image.retain();
        errdefer if (view.image) |image| image.release();
        try managed.add(view);
    }

    fn rollbackTextureLoad(_: *Self, load: TextureLoad) void {
        _ = load.managed.rollbackAdd(load.atlasGeneration);
        _ = load.imageManaged.rollbackAdd(load.imageGeneration);
    }

    fn loadTextureFromBufferTracked(
        self: *Self,
        name: []const u8,
        width: usize,
        height: usize,
        buffer: []u8,
    ) !TextureLoad {
        const baseName = utils.baseNameFromPath(name);
        const imageManaged = try self.getOrCreateTextureImage(baseName);
        const managed = try self.getOrCreateAtlasTexture(baseName);

        var texture: c_uint = undefined;
        gl.genTextures(1, &texture);
        var gl_texture_owned = false;
        errdefer if (!gl_texture_owned) gl.deleteTextures(1, &texture);

        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        const format = gl.RGBA;
        gl.texImage2D(gl.TEXTURE_2D, 0, format, @intCast(width), @intCast(height), 0, format, gl.UNSIGNED_BYTE, @ptrCast(buffer));

        const imageGeneration = imageManaged.gen + 1;
        try imageManaged.add(.{
            .texture = texture,
            .size = .{ .x = @intCast(width), .y = @intCast(height) },
        });
        gl_texture_owned = true;
        errdefer _ = imageManaged.rollbackAdd(imageGeneration);

        const atlasGeneration = managed.gen + 1;
        try self.addTextureView(managed, .{
            .texture = texture,
            .size = .{ .x = @intCast(width), .y = @intCast(height) },
            .src = .{ .t = 0, .l = 0, .b = 1, .r = 1 },
            .image = imageManaged.get().?,
        });

        return .{
            .managed = managed,
            .imageManaged = imageManaged,
            .atlasGeneration = atlasGeneration,
            .imageGeneration = imageGeneration,
        };
    }

    /// Loads an RGBA texture from a raw buffer. The buffer should be in RGBA
    /// format, with 4 bytes per pixel. The name is the name that the texture
    /// will be stored with in the resource manager, and is used to access the
    /// texture later with `getTexture`. The width and height are the dimensions
    /// of the texture and must match the buffer size. Returns a borrowed
    /// handle (see `ResourceManager`).
    pub fn loadTextureFromBuffer(
        self: *Self,
        name: []const u8,
        width: usize,
        height: usize,
        buffer: []u8,
    ) !*TextureHandle {
        return latestOf((try self.loadTextureFromBufferTracked(name, width, height, buffer)).managed);
    }

    /// Internal: loads a texture from a file without registering a hot-reload
    /// watch. Called from `loadTexture` (which adds the watch) and from
    /// `loadAtlasImpl` (which registers atlas-level watches instead).
    fn loadTextureImplTracked(
        self: *Self,
        name: []const u8,
        filePath: []const u8,
    ) !TextureLoad {
        std.log.info("Loading image '{s}' from '{s}'\n", .{ name, filePath });
        const nt_file_path = try std.mem.concatWithSentinel(self.alloc, u8, &.{filePath}, 0);
        defer self.alloc.free(nt_file_path);

        var image = try stbi.Image.loadFromFile(nt_file_path, 4);
        defer image.deinit();

        std.log.info("Loaded image '{s}', width={}, height={}\n", .{ name, image.width, image.height });

        return try self.loadTextureFromBufferTracked(name, image.width, image.height, image.data);
    }

    fn loadTextureImpl(
        self: *Self,
        name: []const u8,
        filePath: []const u8,
    ) !*ManagedTexture {
        return (try self.loadTextureImplTracked(name, filePath)).managed;
    }

    /// Loads a texture from a file path. The name is the base name of the
    /// file, without the extension, so "player" would match "player.png".
    /// The texture is stored in the atlas with the base name, so it can be
    /// accessed with `getTexture` using that name.  The file type is
    /// determined from the file extension, and should be a type supported
    /// by the `stbi` library, such as png or jpg.
    ///
    /// In debug builds, the file is automatically watched and the texture
    /// is reloaded (with any live handles marked dirty) when the file changes.
    ///
    /// Returns a borrowed handle (see `ResourceManager`).
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

        return latestOf(result);
    }

    /// The newest generation of `managed`, which every loader has just added.
    fn latestOf(managed: *ManagedTexture) *TextureHandle {
        return managed.get().?;
    }

    // -----------------------------------------------------------------------
    // Atlas loading
    // -----------------------------------------------------------------------

    /// Internal: loads a texture atlas without registering hot-reload watches.
    /// `name` is the resource key; `basePath` is the file path base (without
    /// extension). When both are equal this is an ordinary loadAtlas call.
    fn loadAtlasImpl(self: *Self, name: []const u8, basePath: []const u8) !usize {
        // Read and validate the JSON before touching the base texture: if the
        // atlas fails to load, the previous texture (if any, from an earlier
        // load of this same name) must be left untouched and still valid.
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
        const base_load = try self.loadTextureImplTracked(name, imageName);
        errdefer self.rollbackTextureLoad(base_load);

        const texImageManaged = self.textures.get(utils.baseNameFromPath(name)) orelse return error.NoTextureWithThatName;
        const texImage = texImageManaged.get() orelse return error.NoTextureWithThatName;
        const sz: Vec2I = texImage.val.size.asVec2I();

        var new_manifest: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (new_manifest.items) |n| self.alloc.free(n);
            new_manifest.deinit(self.alloc);
        }

        var added_frames: std.ArrayListUnmanaged(AtlasFrameLoad) = .empty;
        defer added_frames.deinit(self.alloc);
        errdefer {
            for (added_frames.items) |frame_load| {
                _ = frame_load.managed.rollbackAdd(frame_load.generation);
            }
        }

        var num: usize = 0;
        for (spack.frames) |frame| {
            const managed = try self.getOrCreateAtlasTexture(frame.name);
            const generation = managed.gen + 1;
            try added_frames.append(self.alloc, .{ .managed = managed, .generation = generation });
            try self.addTextureView(managed, .{
                .image = texImage,
                .texture = texImage.val.texture,
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

            const name_owned = try self.alloc.dupe(u8, frame.name);
            errdefer self.alloc.free(name_owned);
            try new_manifest.append(self.alloc, name_owned);

            num += 1;
        }

        // Remove atlas entries for frames absent from the new JSON.
        if (self.atlasManifests.getPtr(name)) |old_manifest| {
            outer: for (old_manifest.items) |old_name| {
                for (new_manifest.items) |new_name| {
                    if (std.mem.eql(u8, old_name, new_name)) continue :outer;
                }
                if (self.atlas.fetchRemove(old_name)) |kv| {
                    kv.value.deinit();
                    self.alloc.destroy(kv.value);
                    self.alloc.free(kv.key);
                }
            }
            for (old_manifest.items) |n| self.alloc.free(n);
            old_manifest.deinit(self.alloc);
            old_manifest.* = new_manifest;
        } else {
            const key_owned = try self.alloc.dupe(u8, name);
            errdefer self.alloc.free(key_owned);
            try self.atlasManifests.put(key_owned, new_manifest);
        }

        return num;
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
    /// After loading, `acquireTexture(name)` returns a handle to the full atlas
    /// image; individual frames remain accessible by their frame names.
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
    /// a subtexture or atlas frame works as expected). Cuts from the exact
    /// generation `tex` points at. Returns a borrowed handle (see
    /// `ResourceManager`).
    pub fn addSubTexture(
        self: *Self,
        tex: *TextureHandle,
        name: []const u8,
        px: RectI,
    ) !*TextureHandle {
        const current = tex;
        const managed = try self.getOrCreateAtlasTexture(name);
        try self.addTextureView(managed, .{
            .texture = current.val.texture,
            .size = .{ .x = @intCast(px.width()), .y = @intCast(px.height()) },
            .src = sprites.pixelsToUv(&current.val, px),
            .image = current.val.image,
        });
        return latestOf(managed);
    }

    /// Like `addSubTexture`, but `coords` are in the underlying image's UV
    /// space: (0,0) is top-left, (1,1) is bottom-right.
    pub fn addSubTextureUV(
        self: *Self,
        tex: *TextureHandle,
        name: []const u8,
        coords: RectF,
    ) !*TextureHandle {
        const current = tex;
        const managed = try self.getOrCreateAtlasTexture(name);
        try self.addTextureView(managed, current.val.sub(coords));
        return latestOf(managed);
    }

    /// Creates a `Sprite` for the texture (or atlas frame / subtexture)
    /// registered as `name`. The sprite retains its own reference; call
    /// `sprite.deinit()` to release it.
    pub fn createSprite(self: *Self, name: []const u8) !sprites.Sprite {
        return sprites.Sprite.create(try self.getTexture(name));
    }

    /// Borrows the newest generation of the texture (or atlas frame /
    /// subtexture) registered as `name`, without taking a reference. Don't
    /// release it; see `ResourceManager` for how long it stays valid. Use
    /// `acquireTexture` for a refcounted handle instead.
    pub fn getTexture(self: *Self, name: []const u8) !*TextureHandle {
        const managed = self.atlas.get(name) orelse return error.NoTextureWithThatName;
        return managed.get() orelse return error.NoTextureWithThatName;
    }

    /// Acquires a refcounted handle to a texture by name. The handle stays
    /// alive until released via `handle.release()`. The owning managed resource
    /// marks the handle dirty when the texture is reloaded so the caller can
    /// call `handle.reacquire()` to upgrade.
    pub fn acquireTexture(self: *Self, name: []const u8) !*TextureHandle {
        const managed = self.atlas.get(name) orelse return error.NoTextureWithThatName;
        return managed.acquire() orelse return error.NoTextureWithThatName;
    }

    /// Acquires a refcounted handle to a shader by name. See `acquireTexture`
    /// for lifecycle notes.
    pub fn acquireShader(self: *Self, name: []const u8) !*ShaderHandle {
        const managed = self.shaders.get(name) orelse return error.NoShaderWithThatName;
        return managed.acquire() orelse return error.NoShaderWithThatName;
    }

    // -----------------------------------------------------------------------
    // Font loading
    // -----------------------------------------------------------------------

    /// Loads a TTF font from disk and registers it under `name`. A second
    /// call with the same name marks the prior generation dirty and adds a
    /// fresh one (auto-reload semantics matching other load* methods).
    ///
    /// In debug builds, the file is watched and the font is reloaded (with
    /// live handles marked dirty) when the file changes.
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

        const managed = try self.getOrCreateFont(name);
        try managed.add(fa);

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

        return managed.get().?;
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

        const managed = try self.getOrCreateFont(name);
        try managed.add(fa);
        return managed.get().?;
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

        const managed = try self.getOrCreateFont(name);
        try managed.add(fa);
        return managed.get().?;
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

        const managed = try self.getOrCreateFont(name);
        try managed.add(fa);
        return managed.get().?;
    }

    /// Borrows the newest generation of the font atlas registered as `name`,
    /// without taking a reference -- the font counterpart of `getTexture`.
    /// Use `acquireFontAtlas` when something must keep the atlas alive on
    /// its own.
    pub fn getFontAtlas(self: *Self, name: []const u8) !*FontAtlasHandle {
        const managed = self.fonts.get(name) orelse return error.NoFontWithThatName;
        return managed.get() orelse return error.NoFontWithThatName;
    }

    /// Acquires a refcounted handle to a font atlas by name. See
    /// `acquireTexture` for lifecycle notes.
    pub fn acquireFontAtlas(self: *Self, name: []const u8) !*FontAtlasHandle {
        const managed = self.fonts.get(name) orelse return error.NoFontWithThatName;
        return managed.acquire() orelse return error.NoFontWithThatName;
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
        const managed = self.fonts.get(name) orelse return error.NoFontWithThatName;
        const handle = managed.get() orelse return error.NoFontWithThatName;

        const resolved = try paths.resolve(self.alloc, fontPath);
        defer self.alloc.free(resolved);

        try handle.val.addFallbackFaceFromFile(resolved, faceIndex, self.alloc);
    }

    // -----------------------------------------------------------------------
    // TileMap loading
    // -----------------------------------------------------------------------

    /// Loads a Tiled map from a .tmx file and registers it under `name`.
    /// A second call with the same name marks the prior generation dirty so
    /// holders can re-acquire the new data (hot-reload semantics matching
    /// other load* methods).
    ///
    /// In debug builds, the .tmx file is watched and the map is reloaded
    /// (with live handles marked dirty) when the file changes.
    pub fn loadTileMap(self: *Self, name: []const u8, path: []const u8) !*TileMapHandle {
        const resolved = try paths.resolve(self.alloc, path);
        defer self.alloc.free(resolved);

        var map = try TiledMapXmlLoader.initFromFile(resolved, self.alloc);
        errdefer map.deinit();

        const managed = try self.getOrCreateTileMap(name);
        try managed.add(map);

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

        return managed.get().?;
    }

    /// Borrows the newest generation of the tilemap registered as `name`,
    /// without taking a reference -- the tilemap counterpart of
    /// `getTexture`. Use `acquireTileMap` when something must keep the map
    /// alive on its own (a renderer built from it, say).
    pub fn getTileMap(self: *Self, name: []const u8) !*TileMapHandle {
        const managed = self.tilemaps.get(name) orelse return error.NoTileMapWithThatName;
        return managed.get() orelse return error.NoTileMapWithThatName;
    }

    /// Acquires a refcounted handle to a tilemap by name. The handle stays
    /// alive until released via `handle.release()`. The owning managed resource
    /// marks the handle dirty when the map file is reloaded, signalling the
    /// caller to call `handle.reacquire()` and rebuild any renderer data.
    pub fn acquireTileMap(self: *Self, name: []const u8) !*TileMapHandle {
        const managed = self.tilemaps.get(name) orelse return error.NoTileMapWithThatName;
        return managed.acquire() orelse return error.NoTileMapWithThatName;
    }

    // -----------------------------------------------------------------------
    // Shader loading
    // -----------------------------------------------------------------------

    /// Borrows the newest generation of the shader registered as `name`,
    /// without taking a reference -- the shader counterpart of `getTexture`.
    /// Use `acquireShader` when something must keep the program alive on its
    /// own (a batch queue, say).
    pub fn getShader(self: *Self, name: []const u8) !*ShaderHandle {
        const managed = self.shaders.get(name) orelse return error.NoShaderWithThatName;
        return managed.get() orelse return error.NoShaderWithThatName;
    }

    /// Loads a shader from vertex and fragment shader source code, and stores
    /// it in the resource manager with the given name. Calling with an
    /// existing name compiles a fresh shader and marks the prior version
    /// dirty, so live holders can call `handle.reacquire()` to pick up the
    /// new program.
    pub fn loadShader(
        self: *Self,
        name: []const u8,
        vs: shaders.ShaderCodePtr,
        fs: shaders.ShaderCodePtr,
    ) !*ShaderHandle {
        var shader = try Shader.init(vs, fs);
        errdefer shader.deinit();

        const managed = try self.getOrCreateShader(name);
        try managed.add(shader);
        return managed.get().?;
    }
};
