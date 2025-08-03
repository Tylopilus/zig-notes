const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;
const parser = @import("../markdown/parser.zig");

pub const Document = struct {
    uri: []const u8,
    content: []const u8,
    version: i32,
    wikilinks: std.ArrayList(parser.WikiLink),

    pub fn deinit(self: *Document) void {
        allocator.free(self.uri);
        allocator.free(self.content);
        for (self.wikilinks.items) |*link| {
            link.deinit();
        }
        self.wikilinks.deinit();
    }
};

pub const DocumentManager = struct {
    open_documents: std.HashMap([]const u8, *Document, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init() DocumentManager {
        return DocumentManager{
            .open_documents = std.HashMap([]const u8, *Document, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *DocumentManager) void {
        var iterator = self.open_documents.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            allocator.destroy(entry.value_ptr.*);
        }
        self.open_documents.deinit();
    }

    pub fn didOpen(self: *DocumentManager, uri: []const u8, content: []const u8, version: i32) !void {
        // Parse wikilinks from content
        const wikilinks = try parser.parseWikilinks(content);

        // Create document
        const document = try allocator.create(Document);
        document.* = Document{
            .uri = try allocator.dupe(u8, uri),
            .content = try allocator.dupe(u8, content),
            .version = version,
            .wikilinks = wikilinks,
        };

        // Store document
        try self.open_documents.put(document.uri, document);
    }

    pub fn didChange(self: *DocumentManager, uri: []const u8, content: []const u8, version: i32) !void {
        if (self.open_documents.getPtr(uri)) |document_ptr| {
            // Free old content and wikilinks
            allocator.free(document_ptr.*.content);
            for (document_ptr.*.wikilinks.items) |*link| {
                link.deinit();
            }
            document_ptr.*.wikilinks.deinit();

            // Update with new content
            document_ptr.*.content = try allocator.dupe(u8, content);
            document_ptr.*.version = version;
            document_ptr.*.wikilinks = try parser.parseWikilinks(content);
        }
    }

    pub fn didClose(self: *DocumentManager, uri: []const u8) void {
        if (self.open_documents.fetchRemove(uri)) |entry| {
            entry.value.deinit();
            allocator.destroy(entry.value);
        }
    }

    pub fn getDocument(self: *DocumentManager, uri: []const u8) ?*Document {
        return self.open_documents.get(uri);
    }

    pub fn getWikilinkAtPosition(self: *DocumentManager, uri: []const u8, position: parser.Position) ?*const parser.WikiLink {
        if (self.getDocument(uri)) |document| {
            return parser.isPositionInWikilink(document.wikilinks.items, position);
        }
        return null;
    }
};

pub fn uriToPath(uri: []const u8) ![]const u8 {
    // Simple URI to path conversion for file:// URIs
    if (std.mem.startsWith(u8, uri, "file://")) {
        return try allocator.dupe(u8, uri[7..]);
    }
    return try allocator.dupe(u8, uri);
}

pub fn pathToUri(path: []const u8) ![]const u8 {
    // Convert to absolute path first
    const absolute_path = if (std.fs.path.isAbsolute(path)) 
        try allocator.dupe(u8, path)
    else 
        try std.fs.cwd().realpathAlloc(allocator, path);
    defer if (!std.fs.path.isAbsolute(path)) allocator.free(absolute_path);
    
    const uri = try std.fmt.allocPrint(allocator, "file://{s}", .{absolute_path});
    return uri;
}

test "document manager basic operations" {
    var manager = DocumentManager.init();
    defer manager.deinit();

    const uri = "file:///test.md";
    const content = "This is a [[test-link]] in markdown.";

    try manager.didOpen(uri, content, 1);

    const document = manager.getDocument(uri);
    try std.testing.expect(document != null);
    try std.testing.expectEqualStrings(content, document.?.content);
    try std.testing.expect(document.?.wikilinks.items.len == 1);

    // Test position lookup
    const position = parser.Position{ .line = 0, .character = 12 };
    const wikilink = manager.getWikilinkAtPosition(uri, position);
    try std.testing.expect(wikilink != null);
    try std.testing.expectEqualStrings("test-link", wikilink.?.target);

    manager.didClose(uri);
    try std.testing.expect(manager.getDocument(uri) == null);
}
