const std = @import("std");
const resources = @import("./resources.zig");
const ResourceManager = resources.ResourceManager;
const TextureHandle = resources.TextureHandle;
const FontAtlasHandle = resources.FontAtlasHandle;
const TileMapHandle = resources.TileMapHandle;

/// The default icon used for applications in pixzig.
pub const icon48x48 = @embedFile("assets/pixzig_icon.png");

/// Logs a contextual error for a failed asset file operation before the
/// caller propagates `err` unchanged. A bare `FileNotFound` gives no
/// indication of what was being loaded or where the loader looked for it;
/// this reports the asset kind, the resolved path, and (for relative paths)
/// the process's cwd, since that's what a relative path is resolved against.
fn logAssetIoError(err: anyerror, kind: []const u8, path: []const u8) void {
    if (std.fs.path.isAbsolute(path)) {
        std.log.err("Failed to load {s} '{s}': {s}", .{ kind, path, @errorName(err) });
        return;
    }
    const io = std.Io.Threaded.global_single_threaded.io();
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_str = if (std.Io.Dir.cwd().realPath(io, &buf)) |len| buf[0..len] else |_| "<unknown>";
    std.log.err("Failed to load {s} '{s}' (cwd: '{s}'): {s}", .{ kind, path, cwd_str, @errorName(err) });
}

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

/// Abstracts over file-path vs inline-JSON manifest sources. Produced at
/// comptime by `fromOptions` from the `manifest_options` build module, then
/// used at runtime to open the manifest.
pub const ManifestSource = union(enum) {
    file: []const u8,
    json: struct { content: []const u8, base_dir: []const u8 },

    pub fn fromOptions(comptime Opts: type) ManifestSource {
        return if (Opts.manifest_path.len > 0)
            .{ .file = Opts.manifest_path }
        else
            .{ .json = .{
                .content = Opts.manifest_json,
                .base_dir = Opts.manifest_base_dir,
            } };
    }

    pub fn load(self: ManifestSource, alloc: std.mem.Allocator, res: *ResourceManager) !AssetManifest {
        return switch (self) {
            .file => |path| AssetManifest.loadFromFile(alloc, res, path),
            .json => |j| AssetManifest.loadFromJson(alloc, res, j.content, j.base_dir),
        };
    }
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
    /// `manifest_path` may be absolute, or relative -- a relative path is
    /// resolved against the running executable's own directory (not the
    /// process's current working directory), so a packaged build finds its
    /// assets no matter where it's launched from. All asset paths in the
    /// manifest are then resolved as:
    ///   dir(resolved manifest path) / root / asset.path
    pub fn loadFromFile(
        alloc: std.mem.Allocator,
        res: *ResourceManager,
        manifest_path: []const u8,
    ) !Self {
        const io = std.Io.Threaded.global_single_threaded.io();

        var owned_path: ?[]u8 = null;
        defer if (owned_path) |p| alloc.free(p);

        const resolved_path: []const u8 = if (std.fs.path.isAbsolute(manifest_path))
            manifest_path
        else blk: {
            const exe_dir = try std.process.executableDirPathAlloc(io, alloc);
            defer alloc.free(exe_dir);
            const joined = try std.fs.path.join(alloc, &.{ exe_dir, manifest_path });
            owned_path = joined;
            break :blk joined;
        };

        const file_contents = std.Io.Dir.cwd().readFileAlloc(io, resolved_path, alloc, .unlimited) catch |err| {
            logAssetIoError(err, "manifest", resolved_path);
            return err;
        };
        defer alloc.free(file_contents);

        const manifest_dir = std.fs.path.dirname(resolved_path) orelse ".";
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
        // `allocate = .alloc_always` forces string values to be copied into
        // `parsed`'s own arena rather than sliced from `json_content`. Without
        // it, id/path strings alias `json_content` directly; `loadFromFile`
        // frees its `file_contents` buffer right after parsing, so any lookup
        // after that point (e.g. a later `loadGroup` or `resolvePath` call)
        // would read freed memory.
        const parsed = try std.json.parseFromSlice(ManifestJson, alloc, json_content, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        errdefer parsed.deinit();

        const root_dir = try std.fs.path.join(alloc, &.{ base_dir, parsed.value.root });
        errdefer alloc.free(root_dir);

        var groups = std.StringHashMap([]const []const u8).init(alloc);
        errdefer groups.deinit();

        var it = parsed.value.groups.map.iterator();
        while (it.next()) |entry| {
            const gop = try groups.getOrPut(entry.key_ptr.*);
            if (gop.found_existing) {
                std.log.err("AssetManifest: duplicate group '{s}'", .{entry.key_ptr.*});
                return error.DuplicateGroup;
            }
            gop.value_ptr.* = entry.value_ptr.*;
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
            const gop = try defs.getOrPut(entry.id);
            if (gop.found_existing) {
                std.log.err("AssetManifest: duplicate asset id '{s}'", .{entry.id});
                return error.DuplicateAssetId;
            }
            gop.value_ptr.* = .{
                .kind = kind,
                .path = entry.path,
                .font_size = entry.font_size orelse 0,
            };
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
                    _ = self.res.loadTexture(id, full_path) catch |err| {
                        logAssetIoError(err, "texture", full_path);
                        return err;
                    };
                    try handles.append(self.alloc, .{ .texture = try self.res.acquireTexture(id) });
                },
                .atlas => {
                    _ = self.res.loadAtlasNamed(id, full_path) catch |err| {
                        logAssetIoError(err, "atlas", full_path);
                        return err;
                    };
                    try handles.append(self.alloc, .{ .texture = try self.res.acquireTexture(id) });
                },
                .font => {
                    self.res.loadFontFromTtfFile(id, full_path, def.font_size) catch |err| {
                        logAssetIoError(err, "font", full_path);
                        return err;
                    };
                    try handles.append(self.alloc, .{ .font = try self.res.acquireFontAtlas(id) });
                },
                .tilemap => {
                    self.res.loadTileMap(id, full_path) catch |err| {
                        logAssetIoError(err, "tilemap", full_path);
                        return err;
                    };
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

    /// Resolve the full filesystem path for `id` as declared in the manifest,
    /// without loading it into `ResourceManager`. Intended for `raw` assets
    /// (e.g. Lua scripts) that game code opens directly rather than through
    /// `loadGroup`. Caller owns the returned buffer.
    pub fn resolvePath(self: *const Self, alloc: std.mem.Allocator, id: []const u8) ![:0]u8 {
        const def = self.defs.get(id) orelse {
            std.log.err("AssetManifest: unknown asset id '{s}'", .{id});
            return error.UnknownAsset;
        };
        return std.fs.path.joinZ(alloc, &.{ self.root_dir, def.path });
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
