const std = @import("std");
const tag_parser = @import("../markdown/tag_parser.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const TagIndex = struct {
    // Map tag name to list of files containing it
    tag_to_files: std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    // Map file to list of tags it contains
    file_to_tags: std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init() TagIndex {
        return TagIndex{
            .tag_to_files = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .file_to_tags = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *TagIndex) void {
        // Free tag_to_files map
        var tag_iter = self.tag_to_files.iterator();
        while (tag_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |file_path| {
                allocator.free(file_path);
            }
            entry.value_ptr.deinit();
        }
        self.tag_to_files.deinit();

        // Free file_to_tags map
        var file_iter = self.file_to_tags.iterator();
        while (file_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |tag_name| {
                allocator.free(tag_name);
            }
            entry.value_ptr.deinit();
        }
        self.file_to_tags.deinit();
    }

    pub fn addTagsFromFile(self: *TagIndex, file_path: []const u8, content: []const u8) !void {
        // Remove existing tags for this file first
        self.removeFile(file_path);

        // Parse tags from content
        const tags = tag_parser.parseTags(content) catch |err| {
            std.log.warn("Failed to parse tags from {s}: {}", .{ file_path, err });
            return;
        };
        defer {
            for (tags) |*tag| {
                tag.deinit();
            }
            allocator.free(tags);
        }

        // Add each tag
        for (tags) |tag| {
            try self.addTag(tag.name, file_path);
        }
    }

    pub fn addTag(self: *TagIndex, tag: []const u8, file_path: []const u8) !void {
        // Add to tag_to_files mapping
        const owned_tag = try allocator.dupe(u8, tag);
        const owned_file_path = try allocator.dupe(u8, file_path);

        const result = try self.tag_to_files.getOrPut(owned_tag);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(allocator);
        } else {
            // Free the duplicate tag name since we already have it
            allocator.free(owned_tag);
        }

        // Check if file is already in the list
        var found = false;
        for (result.value_ptr.items) |existing_file| {
            if (std.mem.eql(u8, existing_file, file_path)) {
                found = true;
                break;
            }
        }

        if (!found) {
            try result.value_ptr.append(owned_file_path);
        } else {
            allocator.free(owned_file_path);
        }

        // Add to file_to_tags mapping
        const owned_file_path2 = try allocator.dupe(u8, file_path);
        const owned_tag2 = try allocator.dupe(u8, tag);

        const file_result = try self.file_to_tags.getOrPut(owned_file_path2);
        if (!file_result.found_existing) {
            file_result.value_ptr.* = std.ArrayList([]const u8).init(allocator);
        } else {
            // Free the duplicate file path since we already have it
            allocator.free(owned_file_path2);
        }

        // Check if tag is already in the list
        var tag_found = false;
        for (file_result.value_ptr.items) |existing_tag| {
            if (std.mem.eql(u8, existing_tag, tag)) {
                tag_found = true;
                break;
            }
        }

        if (!tag_found) {
            try file_result.value_ptr.append(owned_tag2);
        } else {
            allocator.free(owned_tag2);
        }
    }

    pub fn removeFile(self: *TagIndex, file_path: []const u8) void {
        // Get tags for this file
        if (self.file_to_tags.get(file_path)) |tags_list| {
            // Remove file from each tag's file list
            for (tags_list.items) |tag_name| {
                if (self.tag_to_files.getPtr(tag_name)) |files_list| {
                    for (files_list.items, 0..) |file, i| {
                        if (std.mem.eql(u8, file, file_path)) {
                            allocator.free(files_list.swapRemove(i));
                            break;
                        }
                    }

                    // If no files left for this tag, remove the tag entirely
                    if (files_list.items.len == 0) {
                        const tag_entry = self.tag_to_files.fetchRemove(tag_name);
                        if (tag_entry) |kv| {
                            allocator.free(kv.key);
                            kv.value.deinit();
                        }
                    }
                }
            }

            // Remove file from file_to_tags
            const entry = self.file_to_tags.fetchRemove(file_path);
            if (entry) |kv| {
                allocator.free(kv.key);
                for (kv.value.items) |tag_name| {
                    allocator.free(tag_name);
                }
                kv.value.deinit();
            }
        }
    }

    pub fn getTagsStartingWith(self: *TagIndex, prefix: []const u8) ![][]const u8 {
        var matching_tags = std.ArrayList([]const u8).init(allocator);
        defer matching_tags.deinit();

        var iter = self.tag_to_files.iterator();
        while (iter.next()) |entry| {
            const tag_name = entry.key_ptr.*;
            if (std.mem.startsWith(u8, tag_name, prefix)) {
                try matching_tags.append(try allocator.dupe(u8, tag_name));
            }
        }

        return try matching_tags.toOwnedSlice();
    }

    pub fn getFilesForTag(self: *TagIndex, tag: []const u8) ?[]const []const u8 {
        if (self.tag_to_files.get(tag)) |files_list| {
            return files_list.items;
        }
        return null;
    }

    pub fn getTagsForFile(self: *TagIndex, file_path: []const u8) ?[]const []const u8 {
        if (self.file_to_tags.get(file_path)) |tags_list| {
            return tags_list.items;
        }
        return null;
    }

    pub fn getTagCount(self: *TagIndex, tag: []const u8) usize {
        if (self.tag_to_files.get(tag)) |files_list| {
            return files_list.items.len;
        }
        return 0;
    }

    pub fn getAllTags(self: *TagIndex) ![][]const u8 {
        var all_tags = std.ArrayList([]const u8).init(allocator);
        defer all_tags.deinit();

        var iter = self.tag_to_files.iterator();
        while (iter.next()) |entry| {
            try all_tags.append(try allocator.dupe(u8, entry.key_ptr.*));
        }

        return try all_tags.toOwnedSlice();
    }
};

test "tag index basic operations" {
    var index = TagIndex.init();
    defer index.deinit();

    // Add some tags
    try index.addTag("project", "file1.md");
    try index.addTag("work", "file1.md");
    try index.addTag("project", "file2.md");

    // Test getTagsForFile
    const file1_tags = index.getTagsForFile("file1.md");
    try std.testing.expect(file1_tags != null);
    try std.testing.expect(file1_tags.?.len == 2);

    // Test getFilesForTag
    const project_files = index.getFilesForTag("project");
    try std.testing.expect(project_files != null);
    try std.testing.expect(project_files.?.len == 2);

    // Test getTagCount
    try std.testing.expect(index.getTagCount("project") == 2);
    try std.testing.expect(index.getTagCount("work") == 1);
    try std.testing.expect(index.getTagCount("nonexistent") == 0);
}

test "tag index prefix matching" {
    var index = TagIndex.init();
    defer index.deinit();

    try index.addTag("project", "file1.md");
    try index.addTag("programming", "file2.md");
    try index.addTag("work", "file3.md");

    const matching = try index.getTagsStartingWith("pro");
    defer {
        for (matching) |tag| {
            allocator.free(tag);
        }
        allocator.free(matching);
    }

    try std.testing.expect(matching.len == 2);
}

test "tag index file removal" {
    var index = TagIndex.init();
    defer index.deinit();

    try index.addTag("project", "file1.md");
    try index.addTag("work", "file1.md");
    try index.addTag("project", "file2.md");

    // Before removal
    try std.testing.expect(index.getTagCount("project") == 2);
    try std.testing.expect(index.getTagCount("work") == 1);

    // Remove file1.md
    index.removeFile("file1.md");

    // After removal
    try std.testing.expect(index.getTagCount("project") == 1);
    try std.testing.expect(index.getTagCount("work") == 0);
    try std.testing.expect(index.getTagsForFile("file1.md") == null);
}