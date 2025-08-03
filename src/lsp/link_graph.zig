const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;

pub const LinkGraph = struct {
    const Self = @This();
    pub const StringHashSet = std.hash_map.StringHashMap(void);

    // Forward links: file → files it references
    outgoing_links: std.StringHashMap(StringHashSet),
    // Backward links: file → files that reference it
    incoming_links: std.StringHashMap(StringHashSet),
    // Tag usage: tag → files that use it
    tag_usage: std.StringHashMap(StringHashSet),
    // File tags: file → tags it contains
    file_tags: std.StringHashMap(StringHashSet),

    pub fn init() Self {
        return Self{
            .outgoing_links = std.StringHashMap(StringHashSet).init(allocator),
            .incoming_links = std.StringHashMap(StringHashSet).init(allocator),
            .tag_usage = std.StringHashMap(StringHashSet).init(allocator),
            .file_tags = std.StringHashMap(StringHashSet).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Deinit all the HashSets stored in the HashMaps and free keys
        var outgoing_it = self.outgoing_links.iterator();
        while (outgoing_it.next()) |entry| {
            entry.value_ptr.deinit();
            allocator.free(entry.key_ptr.*);
        }
        self.outgoing_links.deinit();
        
        var incoming_it = self.incoming_links.iterator();
        while (incoming_it.next()) |entry| {
            entry.value_ptr.deinit();
            allocator.free(entry.key_ptr.*);
        }
        self.incoming_links.deinit();
        
        var tag_usage_it = self.tag_usage.iterator();
        while (tag_usage_it.next()) |entry| {
            entry.value_ptr.deinit();
            allocator.free(entry.key_ptr.*);
        }
        self.tag_usage.deinit();
        
        var file_tags_it = self.file_tags.iterator();
        while (file_tags_it.next()) |entry| {
            entry.value_ptr.deinit();
            allocator.free(entry.key_ptr.*);
        }
        self.file_tags.deinit();
    }

    pub fn addLink(self: *Self, from_file: []const u8, to_file: []const u8) !void {
        // Simple approach: check if we already have an entry, if not, create one
        if (!self.outgoing_links.contains(from_file)) {
            const owned_from = try allocator.dupe(u8, from_file);
            try self.outgoing_links.put(owned_from, StringHashSet.init(allocator));
        }
        
        if (!self.incoming_links.contains(to_file)) {
            const owned_to = try allocator.dupe(u8, to_file);
            try self.incoming_links.put(owned_to, StringHashSet.init(allocator));
        }

        // Find the actual keys in the maps to use for cross-references
        var from_key: []const u8 = undefined;
        var to_key: []const u8 = undefined;
        
        var from_it = self.outgoing_links.keyIterator();
        while (from_it.next()) |key| {
            if (std.mem.eql(u8, key.*, from_file)) {
                from_key = key.*;
                break;
            }
        }
        
        var to_it = self.incoming_links.keyIterator();
        while (to_it.next()) |key| {
            if (std.mem.eql(u8, key.*, to_file)) {
                to_key = key.*;
                break;
            }
        }
        
        try self.outgoing_links.getPtr(from_key).?.put(to_key, {});
        try self.incoming_links.getPtr(to_key).?.put(from_key, {});
    }

    pub fn addTagUsage(self: *Self, file: []const u8, tag: []const u8) !void {
        // Simple approach: check if we already have an entry, if not, create one
        if (!self.tag_usage.contains(tag)) {
            const owned_tag = try allocator.dupe(u8, tag);
            try self.tag_usage.put(owned_tag, StringHashSet.init(allocator));
        }
        
        if (!self.file_tags.contains(file)) {
            const owned_file = try allocator.dupe(u8, file);
            try self.file_tags.put(owned_file, StringHashSet.init(allocator));
        }

        // Find the actual keys in the maps to use for cross-references
        var tag_key: []const u8 = undefined;
        var file_key: []const u8 = undefined;
        
        var tag_it = self.tag_usage.keyIterator();
        while (tag_it.next()) |key| {
            if (std.mem.eql(u8, key.*, tag)) {
                tag_key = key.*;
                break;
            }
        }
        
        var file_it = self.file_tags.keyIterator();
        while (file_it.next()) |key| {
            if (std.mem.eql(u8, key.*, file)) {
                file_key = key.*;
                break;
            }
        }

        try self.tag_usage.getPtr(tag_key).?.put(file_key, {});
        try self.file_tags.getPtr(file_key).?.put(tag_key, {});
    }

    pub fn getFilesReferencingTag(self: *Self, tag: []const u8) ?*StringHashSet {
        return self.tag_usage.getPtr(tag);
    }

    pub fn getFilesReferencingFile(self: *Self, file_path: []const u8) ?*StringHashSet {
        return self.incoming_links.getPtr(file_path);
    }
};
