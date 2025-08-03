const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;

pub const FileMetadata = struct {
    path: []const u8,
    basename: []const u8,
    basename_lower: []const u8,
    last_modified: i64,

    pub fn deinit(self: *FileMetadata) void {
        allocator.free(self.path);
        allocator.free(self.basename);
        allocator.free(self.basename_lower);
    }
};

pub const FileIndex = struct {
    // Map basename (without extension) to file metadata
    name_to_file: std.HashMap([]const u8, *FileMetadata, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    // Map full path to file metadata
    path_to_file: std.HashMap([]const u8, *FileMetadata, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    // All files for cleanup
    all_files: std.ArrayList(*FileMetadata),

    pub fn init() FileIndex {
        return FileIndex{
            .name_to_file = std.HashMap([]const u8, *FileMetadata, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .path_to_file = std.HashMap([]const u8, *FileMetadata, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .all_files = std.ArrayList(*FileMetadata).init(allocator),
        };
    }

    pub fn deinit(self: *FileIndex) void {
        for (self.all_files.items) |file| {
            file.deinit();
            allocator.destroy(file);
        }
        self.all_files.deinit();
        self.name_to_file.deinit();
        self.path_to_file.deinit();
    }

    pub fn addFile(self: *FileIndex, path: []const u8) !void {
        // Extract basename without extension
        const basename_with_ext = std.fs.path.basename(path);
        const basename = if (std.mem.lastIndexOf(u8, basename_with_ext, ".")) |dot_pos|
            basename_with_ext[0..dot_pos]
        else
            basename_with_ext;

        // Create lowercase version for case-insensitive lookup
        var basename_lower = try allocator.alloc(u8, basename.len);
        for (basename, 0..) |c, i| {
            basename_lower[i] = std.ascii.toLower(c);
        }

        // Get file stats
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        const stat = try file.stat();

        // Create file metadata
        const file_metadata = try allocator.create(FileMetadata);
        file_metadata.* = FileMetadata{
            .path = try allocator.dupe(u8, path),
            .basename = try allocator.dupe(u8, basename),
            .basename_lower = basename_lower,
            .last_modified = @intCast(stat.mtime),
        };

        // Add to indices
        try self.name_to_file.put(file_metadata.basename_lower, file_metadata);
        try self.path_to_file.put(file_metadata.path, file_metadata);
        try self.all_files.append(file_metadata);
    }

    pub fn resolveWikilink(self: *FileIndex, target: []const u8) ?[]const u8 {
        // Create lowercase version of target for case-insensitive lookup
        var target_lower = allocator.alloc(u8, target.len) catch return null;
        defer allocator.free(target_lower);

        for (target, 0..) |c, i| {
            target_lower[i] = std.ascii.toLower(c);
        }

        // Remove .md extension if present
        const clean_target = if (std.mem.endsWith(u8, target_lower, ".md"))
            target_lower[0 .. target_lower.len - 3]
        else
            target_lower;

        // Look up in index
        if (self.name_to_file.get(clean_target)) |file_metadata| {
            return file_metadata.path;
        }

        return null;
    }

    pub fn getFileByPath(self: *FileIndex, path: []const u8) ?*FileMetadata {
        return self.path_to_file.get(path);
    }

    pub fn removeFile(self: *FileIndex, path: []const u8) void {
        if (self.path_to_file.get(path)) |file_metadata| {
            _ = self.name_to_file.remove(file_metadata.basename_lower);
            _ = self.path_to_file.remove(path);

            // Remove from all_files list
            for (self.all_files.items, 0..) |file, i| {
                if (file == file_metadata) {
                    _ = self.all_files.swapRemove(i);
                    break;
                }
            }

            file_metadata.deinit();
            allocator.destroy(file_metadata);
        }
    }

    pub fn renameFile(self: *FileIndex, old_path: []const u8, new_path: []const u8) !void {
        self.removeFile(old_path);
        try self.addFile(new_path);
    }
};

test "file index basic operations" {
    var index = FileIndex.init();
    defer index.deinit();

    // Create a temporary file for testing
    const test_path = "test-file.md";
    const test_file = try std.fs.cwd().createFile(test_path, .{});
    test_file.close();
    defer std.fs.cwd().deleteFile(test_path) catch {};

    try index.addFile(test_path);

    // Test resolution
    const resolved = index.resolveWikilink("test-file");
    try std.testing.expect(resolved != null);
    try std.testing.expectEqualStrings(test_path, resolved.?);

    // Test case insensitive resolution
    const resolved_case = index.resolveWikilink("Test-File");
    try std.testing.expect(resolved_case != null);
    try std.testing.expectEqualStrings(test_path, resolved_case.?);

    // Test with .md extension
    const resolved_ext = index.resolveWikilink("test-file.md");
    try std.testing.expect(resolved_ext != null);
    try std.testing.expectEqualStrings(test_path, resolved_ext.?);
}

test "file index nonexistent file" {
    var index = FileIndex.init();
    defer index.deinit();

    const resolved = index.resolveWikilink("nonexistent");
    try std.testing.expect(resolved == null);
}
