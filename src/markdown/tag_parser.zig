const std = @import("std");
const types = @import("../lsp/types.zig");
const frontmatter = @import("frontmatter.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const Tag = struct {
    name: []const u8,
    position: types.Position,
    range: types.Range,

    pub fn deinit(self: *Tag) void {
        allocator.free(self.name);
    }
};

pub fn parseTags(content: []const u8) ![]Tag {
    // Parse frontmatter to extract tags
    const fm_data = frontmatter.parseFrontmatter(content) catch |err| {
        std.log.warn("Failed to parse frontmatter: {}", .{err});
        return &[_]Tag{};
    };
    
    if (fm_data == null) {
        return &[_]Tag{};
    }
    
    var fm = fm_data.?;
    defer fm.deinit();
    
    if (fm.tags.len == 0) {
        return &[_]Tag{};
    }
    
    // Find the tags line in the frontmatter to get positions
    return parseTagsFromFrontmatter(content, fm.tags);
}

fn parseTagsFromFrontmatter(content: []const u8, tag_names: [][]const u8) ![]Tag {
    var tags = std.ArrayList(Tag).init(allocator);
    defer tags.deinit();
    
    // Find the tags line in the frontmatter
    var current_line: u32 = 0;
    var line_start: usize = 0;
    var found_tags_line = false;
    
    for (content, 0..) |c, i| {
        if (c == '\n') {
            const line_content = content[line_start..i];
            
            // Check if this line contains the tags definition
            if (std.mem.indexOf(u8, line_content, "tags:")) |tags_pos| {
                if (std.mem.indexOf(u8, line_content[tags_pos..], "[")) |bracket_start| {
                    if (std.mem.indexOf(u8, line_content[tags_pos..], "]")) |bracket_end| {
                        // Found the tags array, parse individual tag positions
                        const array_start = tags_pos + bracket_start + 1;
                        const array_content = line_content[array_start..tags_pos + bracket_end];
                        
                        try parseTagPositions(array_content, current_line, 
                                            @as(u32, @intCast(array_start)), 
                                            tag_names, &tags);
                        found_tags_line = true;
                        break;
                    }
                }
            }
            
            current_line += 1;
            line_start = i + 1;
        }
        
        // Stop if we've exited the frontmatter
        if (current_line > 0 and std.mem.startsWith(u8, content[line_start..], "---")) {
            break;
        }
    }
    
    if (!found_tags_line) {
        // Fallback: create tags without specific positions
        for (tag_names) |tag_name| {
            const tag = Tag{
                .name = try allocator.dupe(u8, tag_name),
                .position = types.Position{ .line = 0, .character = 0 },
                .range = types.Range{
                    .start = types.Position{ .line = 0, .character = 0 },
                    .end = types.Position{ .line = 0, .character = 0 },
                },
            };
            try tags.append(tag);
        }
    }
    
    return try tags.toOwnedSlice();
}

fn parseTagPositions(array_content: []const u8, line: u32, line_offset: u32, 
                    tag_names: [][]const u8, tags: *std.ArrayList(Tag)) !void {
    var tag_start: ?u32 = null;
    var tag_index: usize = 0;
    
    for (array_content, 0..) |c, i| {
        const pos = @as(u32, @intCast(i));
        
        if (c == ',' or i == array_content.len - 1) {
            // End of current tag
            if (tag_start) |start| {
                // Find the actual end of the tag (skip trailing whitespace)
                var actual_end = if (c == ',') pos else pos + 1;
                while (actual_end > start and std.ascii.isWhitespace(array_content[actual_end - 1])) {
                    actual_end -= 1;
                }
                
                if (tag_index < tag_names.len) {
                    const tag = Tag{
                        .name = try allocator.dupe(u8, tag_names[tag_index]),
                        .position = types.Position{ .line = line, .character = line_offset + start },
                        .range = types.Range{
                            .start = types.Position{ .line = line, .character = line_offset + start },
                            .end = types.Position{ .line = line, .character = line_offset + actual_end },
                        },
                    };
                    try tags.append(tag);
                    tag_index += 1;
                }
            }
            tag_start = null;
        } else if (!std.ascii.isWhitespace(c) and tag_start == null) {
            // Start of new tag
            tag_start = pos;
        }
    }
}

test "parse frontmatter tags" {
    const content = 
        \\---
        \\title: "Test Note"
        \\tags: [project, work/meeting]
        \\---
        \\
        \\# Content
        ;
    
    const tags = try parseTags(content);
    defer {
        for (tags) |*tag| {
            tag.deinit();
        }
        allocator.free(tags);
    }

    try std.testing.expect(tags.len == 2);
    try std.testing.expectEqualStrings("project", tags[0].name);
    try std.testing.expectEqualStrings("work/meeting", tags[1].name);
}

test "parse nested tags from frontmatter" {
    const content = 
        \\---
        \\tags: [work/meeting, work/todo, development]
        \\---
        \\
        \\Content here.
        ;
    
    const tags = try parseTags(content);
    defer {
        for (tags) |*tag| {
            tag.deinit();
        }
        allocator.free(tags);
    }

    try std.testing.expect(tags.len == 3);
    try std.testing.expectEqualStrings("work/meeting", tags[0].name);
    try std.testing.expectEqualStrings("work/todo", tags[1].name);
    try std.testing.expectEqualStrings("development", tags[2].name);
}

test "no frontmatter returns empty tags" {
    const content = 
        \\# Regular Markdown
        \\
        \\This has no frontmatter and no tags.
        ;
    
    const tags = try parseTags(content);
    defer {
        for (tags) |*tag| {
            tag.deinit();
        }
        allocator.free(tags);
    }

    try std.testing.expect(tags.len == 0);
}

test "frontmatter without tags" {
    const content = 
        \\---
        \\title: "Test Note"
        \\date: 2024-08-02
        \\---
        \\
        \\# Content
        ;
    
    const tags = try parseTags(content);
    defer {
        for (tags) |*tag| {
            tag.deinit();
        }
        allocator.free(tags);
    }

    try std.testing.expect(tags.len == 0);
}

test "hashtags in content are ignored" {
    const content = 
        \\---
        \\tags: [project]
        \\---
        \\
        \\# This is a heading
        \\
        \\Some content with #hashtag that should be ignored.
        ;
    
    const tags = try parseTags(content);
    defer {
        for (tags) |*tag| {
            tag.deinit();
        }
        allocator.free(tags);
    }

    try std.testing.expect(tags.len == 1);
    try std.testing.expectEqualStrings("project", tags[0].name);
}