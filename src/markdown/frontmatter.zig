const std = @import("std");
const types = @import("../lsp/types.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const FrontmatterData = struct {
    title: ?[]const u8 = null,
    tags: [][]const u8 = &[_][]const u8{},
    date: ?[]const u8 = null,
    author: ?[]const u8 = null,
    // Range in the document where frontmatter exists
    range: ?types.Range = null,

    pub fn deinit(self: *FrontmatterData) void {
        if (self.title) |title| allocator.free(title);
        if (self.date) |date| allocator.free(date);
        if (self.author) |author| allocator.free(author);
        for (self.tags) |tag| {
            allocator.free(tag);
        }
        if (self.tags.len > 0) allocator.free(self.tags);
    }
};

pub const FrontmatterSection = struct {
    content: []const u8,
    range: types.Range,
    is_tags_section: bool = false,
    tags_line: u32 = 0,
};

pub fn parseFrontmatter(content: []const u8) !?FrontmatterData {
    if (!std.mem.startsWith(u8, content, "---\n")) {
        return null;
    }

    // Find the end of frontmatter
    const frontmatter_end = std.mem.indexOf(u8, content[4..], "\n---") orelse return null;
    const frontmatter_content = content[4..4 + frontmatter_end];
    
    var data = FrontmatterData{};
    var tags_list = std.ArrayList([]const u8).init(allocator);
    defer tags_list.deinit();

    // Calculate range
    var end_line: u32 = 0;
    for (content[0..4 + frontmatter_end + 4]) |c| {
        if (c == '\n') end_line += 1;
    }
    
    data.range = types.Range{
        .start = types.Position{ .line = 0, .character = 0 },
        .end = types.Position{ .line = end_line, .character = 3 }, // "---"
    };

    // Parse YAML-like frontmatter (simplified)
    var lines = std.mem.splitScalar(u8, frontmatter_content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
            const key = std.mem.trim(u8, trimmed[0..colon_pos], " \t");
            const value_raw = std.mem.trim(u8, trimmed[colon_pos + 1..], " \t");
            
            if (std.mem.eql(u8, key, "title")) {
                // Remove quotes if present
                const value = if (std.mem.startsWith(u8, value_raw, "\"") and std.mem.endsWith(u8, value_raw, "\""))
                    value_raw[1..value_raw.len - 1]
                else
                    value_raw;
                data.title = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "date")) {
                data.date = try allocator.dupe(u8, value_raw);
            } else if (std.mem.eql(u8, key, "author")) {
                // Remove quotes if present
                const value = if (std.mem.startsWith(u8, value_raw, "\"") and std.mem.endsWith(u8, value_raw, "\""))
                    value_raw[1..value_raw.len - 1]
                else
                    value_raw;
                data.author = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "tags")) {
                // Parse tags array: [tag1, tag2, tag3]
                if (std.mem.startsWith(u8, value_raw, "[") and std.mem.endsWith(u8, value_raw, "]")) {
                    const tags_content = value_raw[1..value_raw.len - 1];
                    var tag_items = std.mem.splitScalar(u8, tags_content, ',');
                    while (tag_items.next()) |tag_item| {
                        const tag = std.mem.trim(u8, tag_item, " \t");
                        if (tag.len > 0) {
                            try tags_list.append(try allocator.dupe(u8, tag));
                        }
                    }
                }
            }
        }
    }

    data.tags = try tags_list.toOwnedSlice();
    return data;
}

pub fn findFrontmatterSection(content: []const u8) ?FrontmatterSection {
    if (!std.mem.startsWith(u8, content, "---\n")) {
        return null;
    }

    // Find the end of frontmatter
    const frontmatter_end = std.mem.indexOf(u8, content[4..], "\n---") orelse return null;
    const full_end = 4 + frontmatter_end + 4; // Include the closing ---
    
    // Calculate range
    var end_line: u32 = 0;
    for (content[0..full_end]) |c| {
        if (c == '\n') end_line += 1;
    }
    
    return FrontmatterSection{
        .content = content[0..full_end],
        .range = types.Range{
            .start = types.Position{ .line = 0, .character = 0 },
            .end = types.Position{ .line = end_line, .character = 0 },
        },
    };
}

pub fn getTagsLineInfo(content: []const u8, position: types.Position) ?struct { line_content: []const u8, tags_start: u32 } {
    const frontmatter = findFrontmatterSection(content) orelse return null;
    
    // Check if position is within frontmatter
    if (!isPositionInRange(position, frontmatter.range)) {
        return null;
    }
    
    // Find the line at the position
    var current_line: u32 = 0;
    var line_start: usize = 0;
    
    for (content, 0..) |c, i| {
        if (current_line == position.line) {
            // Find end of this line
            var line_end = i;
            while (line_end < content.len and content[line_end] != '\n') {
                line_end += 1;
            }
            
            const line_content = content[line_start..line_end];
            
            // Check if this line contains tags
            if (std.mem.indexOf(u8, line_content, "tags:")) |tags_pos| {
                // Check if we're in the tags array
                const after_tags = line_content[tags_pos + 5..];
                if (std.mem.indexOf(u8, after_tags, "[")) |bracket_pos| {
                    const tags_start = @as(u32, @intCast(tags_pos + 5 + bracket_pos + 1));
                    return .{
                        .line_content = line_content,
                        .tags_start = tags_start,
                    };
                }
            }
            break;
        }
        
        if (c == '\n') {
            current_line += 1;
            line_start = i + 1;
        }
    }
    
    return null;
}

fn isPositionInRange(position: types.Position, range: types.Range) bool {
    if (position.line < range.start.line or position.line > range.end.line) {
        return false;
    }
    if (position.line == range.start.line and position.character < range.start.character) {
        return false;
    }
    if (position.line == range.end.line and position.character > range.end.character) {
        return false;
    }
    return true;
}

test "parse frontmatter with tags" {
    const content =
        \\---
        \\title: "Test Note"
        \\tags: [project, work/meeting, development]
        \\date: 2024-08-02
        \\---
        \\
        \\# Content
        ;
    
    const frontmatter = try parseFrontmatter(content);
    try std.testing.expect(frontmatter != null);
    
    var fm = frontmatter.?;
    defer fm.deinit();
    
    try std.testing.expect(fm.title != null);
    try std.testing.expectEqualStrings("Test Note", fm.title.?);
    try std.testing.expect(fm.tags.len == 3);
    try std.testing.expectEqualStrings("project", fm.tags[0]);
    try std.testing.expectEqualStrings("work/meeting", fm.tags[1]);
    try std.testing.expectEqualStrings("development", fm.tags[2]);
}

test "no frontmatter" {
    const content = "# Just a regular markdown file";
    const frontmatter = try parseFrontmatter(content);
    try std.testing.expect(frontmatter == null);
}

test "frontmatter section detection" {
    const content =
        \\---
        \\title: "Test"
        \\tags: [project]
        \\---
        \\
        \\# Content
        ;
    
    const section = findFrontmatterSection(content);
    try std.testing.expect(section != null);
    
    const fm = section.?;
    try std.testing.expect(fm.range.start.line == 0);
    try std.testing.expect(fm.range.end.line == 3);
}