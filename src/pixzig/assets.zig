const std = @import("std");
const resources = @import("./resources.zig");
const ResourceManager = resources.ResourceManager;
const TextureHandle = resources.TextureHandle;
const FontAtlasHandle = resources.FontAtlasHandle;
const TileMapHandle = resources.TileMapHandle;

/// The default icon used for applications in pixzig.
pub const icon48x48 = @embedFile("assets/pixzig_icon.png");

/// Asset kinds for use in manifests. `raw` marks files that must be present
/// at runtime but are not loaded through `ResourceManager` (e.g. audio files,
/// Lua scripts, fonts consumed directly by the renderer). `loadGroup` skips
/// raw assets -- they produce no ref-counted handle.
pub const AssetKind = enum { texture, atlas, font, tilemap, raw };

/// A ref-counted handle to any asset type. Call `release()` when done.
pub const AnyHandle = union(enum) {
    texture: *TextureHandle,
    font: *FontAtlasHandle,
    tilemap: *TileMapHandle,

    pub fn release(self: AnyHandle) void {
        switch (self) {
            inline else => |h| h.release(),
        }
    }
};

const AssetDef = struct {
    kind: AssetKind,
    path: []const u8,
    font_size: f32,
};

// JSON schema types for parsing the manifest file.
const ManifestJson = struct {
    version: u32 = 1,
    root: []const u8 = ".",
    groups: std.json.ArrayHashMap([]const []const u8) = .{},
    assets: []const AssetJsonEntry = &.{},
};

const AssetJsonEntry = struct {
    id: []const u8,
    kind: []const u8,
    path: []const u8,
    font_size: ?f32 = null,
};

/// Loads and manages a JSON asset manifest. Multiple manifests may coexist;
/// each interacts with the shared `ResourceManager`.
///
/// Resources are loaded lazily per group. The manifest acquires ref-counted
/// handles on `loadGroup` and releases them on `unloadGroup`, so the ref count
/// drops to zero only when all callers have also released their own handles.
///
/// **Boot group**: if the manifest JSON contains a group named `"boot"`, it is
/// loaded automatically when the manifest is opened (via `loadFromFile` or
/// `loadFromJson`). This makes those assets immediately available without a
/// separate `loadGroup("boot")` call. Use it for assets that must exist at
/// startup, such as common UI elements or the initial game resources.
pub const AssetManifest = struct {
    alloc: std.mem.Allocator,
    res: *ResourceManager,
    /// Absolute or cwd-relative path to the asset root directory (owned).
    root_dir: []u8,

    /// Parsed JSON data -- kept alive so string slices into it remain valid.
    parsed: std.json.Parsed(ManifestJson),
    /// group name -> slice of asset IDs (slices into `parsed`).
    groups: std.StringHashMap([]const []const u8),
    /// asset id -> definition (path slice into `parsed`).
    defs: std.StringHashMap(AssetDef),
    /// group name -> acquired handles (keys borrowed from `groups`).
    loaded: std.StringHashMap([]AnyHandle),

    const Self = @This();

    /// Parse a manifest JSON file and return an `AssetManifest`. No assets are
    /// loaded yet; call `loadGroup` to load a group of assets.
    ///
    /// `manifest_path` may be absolute or relative to the current working
    /// directory. All asset paths in the manifest are resolved as:
    ///   dir(manifest_path) / root / asset.path
    pub fn loadFromFile(
        alloc: std.mem.Allocator,
        res: *ResourceManager,
        manifest_path: []const u8,
    ) !Self {
        const io = std.Io.Threaded.global_single_threaded.io();
        const file_contents = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, alloc, .unlimited);
        defer alloc.free(file_contents);

        const manifest_dir = std.fs.path.dirname(manifest_path) orelse ".";
        var result = try loadFromJsonImpl(alloc, res, file_contents, manifest_dir);
        errdefer result.deinit();
        if (result.groups.contains("boot")) try result.loadGroup("boot");
        return result;
    }

    /// Parse an inline manifest JSON string. `assets_root` is the absolute (or
    /// cwd-relative) path to the directory that `root` in the JSON is relative
    /// to. Use this when the manifest content is embedded as a build option via
    /// `manifestFromDef` rather than read from a file.
    pub fn loadFromJson(
        alloc: std.mem.Allocator,
        res: *ResourceManager,
        json_content: []const u8,
        assets_root: []const u8,
    ) !Self {
        var result = try loadFromJsonImpl(alloc, res, json_content, assets_root);
        errdefer result.deinit();
        if (result.groups.contains("boot")) try result.loadGroup("boot");
        return result;
    }

    fn loadFromJsonImpl(
        alloc: std.mem.Allocator,
        res: *ResourceManager,
        json_content: []const u8,
        base_dir: []const u8,
    ) !Self {
        const parsed = try std.json.parseFromSlice(ManifestJson, alloc, json_content, .{
            .ignore_unknown_fields = true,
        });
        errdefer parsed.deinit();

        const root_dir = try std.fs.path.join(alloc, &.{ base_dir, parsed.value.root });
        errdefer alloc.free(root_dir);

        var groups = std.StringHashMap([]const []const u8).init(alloc);
        errdefer groups.deinit();

        var it = parsed.value.groups.map.iterator();
        while (it.next()) |entry| {
            try groups.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var defs = std.StringHashMap(AssetDef).init(alloc);
        errdefer defs.deinit();

        for (parsed.value.assets) |entry| {
            const kind = parseKind(entry.kind) orelse {
                std.log.err("AssetManifest: unknown asset kind '{s}' for id '{s}'", .{ entry.kind, entry.id });
                return error.UnknownAssetKind;
            };
            if (kind == .font and entry.font_size == null) {
                std.log.err("AssetManifest: font '{s}' missing required font_size field", .{entry.id});
                return error.MissingFontSize;
            }
            try defs.put(entry.id, .{
                .kind = kind,
                .path = entry.path,
                .font_size = entry.font_size orelse 0,
            });
        }

        return .{
            .alloc = alloc,
            .res = res,
            .root_dir = root_dir,
            .parsed = parsed,
            .groups = groups,
            .defs = defs,
            .loaded = std.StringHashMap([]AnyHandle).init(alloc),
        };
    }

    /// Load all assets in `group_name`, acquiring ref-counted handles.
    /// Calling this on an already-loaded group is a no-op.
    /// Assets with kind `raw` are skipped (no ResourceManager handle is created).
    pub fn loadGroup(self: *Self, group_name: []const u8) !void {
        if (self.loaded.contains(group_name)) return;

        const ids = self.groups.get(group_name) orelse {
            std.log.err("AssetManifest: unknown group '{s}'", .{group_name});
            return error.UnknownGroup;
        };

        var handles: std.ArrayListUnmanaged(AnyHandle) = .empty;
        errdefer {
            for (handles.items) |h| h.release();
            handles.deinit(self.alloc);
        }

        for (ids) |id| {
            const def = self.defs.get(id) orelse {
                std.log.err("AssetManifest: group '{s}' references unknown asset '{s}'", .{ group_name, id });
                return error.UnknownAsset;
            };
            const full_path = try std.fs.path.join(self.alloc, &.{ self.root_dir, def.path });
            defer self.alloc.free(full_path);

            switch (def.kind) {
                .raw => {}, // present on disk but not loaded into ResourceManager
                .texture => {
                    _ = try self.res.loadTexture(id, full_path);
                    try handles.append(self.alloc, .{ .texture = try self.res.acquireTexture(id) });
                },
                .atlas => {
                    _ = try self.res.loadAtlasNamed(id, full_path);
                    try handles.append(self.alloc, .{ .texture = try self.res.acquireTexture(id) });
                },
                .font => {
                    try self.res.loadFontFromTtfFile(id, full_path, def.font_size);
                    try handles.append(self.alloc, .{ .font = try self.res.acquireFontAtlas(id) });
                },
                .tilemap => {
                    try self.res.loadTileMap(id, full_path);
                    try handles.append(self.alloc, .{ .tilemap = try self.res.acquireTileMap(id) });
                },
            }
        }

        try self.loaded.put(group_name, try handles.toOwnedSlice(self.alloc));
    }

    /// Release the manifest's ref-counted handles for all assets in `group_name`.
    /// This allows assets to be freed once all other callers release their handles.
    /// Silently ignores groups that are not currently loaded.
    pub fn unloadGroup(self: *Self, group_name: []const u8) void {
        const entry = self.loaded.fetchRemove(group_name) orelse return;
        for (entry.value) |h| h.release();
        self.alloc.free(entry.value);
    }

    /// Unload all loaded groups and free all manifest resources.
    pub fn deinit(self: *Self) void {
        var it = self.loaded.iterator();
        while (it.next()) |e| {
            for (e.value_ptr.*) |h| h.release();
            self.alloc.free(e.value_ptr.*);
        }
        self.loaded.deinit();
        self.defs.deinit();
        self.groups.deinit();
        self.parsed.deinit();
        self.alloc.free(self.root_dir);
    }

    fn parseKind(s: []const u8) ?AssetKind {
        if (std.mem.eql(u8, s, "texture")) return .texture;
        if (std.mem.eql(u8, s, "atlas")) return .atlas;
        if (std.mem.eql(u8, s, "font")) return .font;
        if (std.mem.eql(u8, s, "tilemap")) return .tilemap;
        if (std.mem.eql(u8, s, "raw")) return .raw;
        return null;
    }
};
