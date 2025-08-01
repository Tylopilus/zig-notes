const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;
const types = @import("../lsp/types.zig");

pub const Position = types.Position;
pub const Range = types.Range;

pub const WikiLink = struct {
    target: []const u8,
    alias: ?[]const u8,
    range: Range,

    pub fn deinit(self: *WikiLink) void {
        allocator.free(self.target);
        if (self.alias) |alias| {
            allocator.free(alias);
        }
    }
};

pub fn parseWikilinks(content: []const u8) !std.ArrayList(WikiLink) {
    var wikilinks = std.ArrayList(WikiLink).init(allocator);
    var line: u32 = 0;
    var character: u32 = 0;
    var i: usize = 0;

    while (i < content.len) {
        if (content[i] == '\n') {
            line += 1;
            character = 0;
            i += 1;
            continue;
        }

        // Look for wikilink start [[
        if (i + 1 < content.len and content[i] == '[' and content[i + 1] == '[') {
            const start_pos = Position{ .line = line, .character = character };
            i += 2; // Skip [[
            character += 2;

            // Find the end ]]
            const link_start = i;
            var link_end: ?usize = null;
            var temp_char = character;
            var temp_line = line;

            while (i + 1 < content.len) {
                if (content[i] == '\n') {
                    temp_line += 1;
                    temp_char = 0;
                } else if (content[i] == ']' and content[i + 1] == ']') {
                    link_end = i;
                    break;
                } else {
                    temp_char += 1;
                }
                i += 1;
            }

            if (link_end) |end| {
                const link_content = content[link_start..end];
                i += 2; // Skip ]]
                temp_char += 2;

                // Parse target and alias
                var target: []const u8 = undefined;
                var alias: ?[]const u8 = null;

                if (std.mem.indexOf(u8, link_content, "|")) |pipe_pos| {
                    target = try allocator.dupe(u8, std.mem.trim(u8, link_content[0..pipe_pos], " \t"));
                    alias = try allocator.dupe(u8, std.mem.trim(u8, link_content[pipe_pos + 1 ..], " \t"));
                } else {
                    target = try allocator.dupe(u8, std.mem.trim(u8, link_content, " \t"));
                }

                const end_pos = Position{ .line = temp_line, .character = temp_char };
                const wikilink = WikiLink{
                    .target = target,
                    .alias = alias,
                    .range = Range{ .start = start_pos, .end = end_pos },
                };

                try wikilinks.append(wikilink);
                line = temp_line;
                character = temp_char;
            } else {
                // Malformed wikilink, skip
                character += 1;
            }
        } else {
            character += 1;
            i += 1;
        }
    }

    return wikilinks;
}

pub fn isPositionInWikilink(wikilinks: []const WikiLink, pos: Position) ?*const WikiLink {
    for (wikilinks) |*link| {
        if (isPositionInRange(pos, link.range)) {
            return link;
        }
    }
    return null;
}

fn isPositionInRange(pos: Position, range: Range) bool {
    if (pos.line < range.start.line or pos.line > range.end.line) {
        return false;
    }
    if (pos.line == range.start.line and pos.character < range.start.character) {
        return false;
    }
    if (pos.line == range.end.line and pos.character > range.end.character) {
        return false;
    }
    return true;
}

test "parse simple wikilink" {
    const content = "This is a [[test-file]] link.";
    var wikilinks = try parseWikilinks(content);
    defer {
        for (wikilinks.items) |*link| {
            link.deinit();
        }
        wikilinks.deinit();
    }

    try std.testing.expect(wikilinks.items.len == 1);
    try std.testing.expectEqualStrings("test-file", wikilinks.items[0].target);
    try std.testing.expect(wikilinks.items[0].alias == null);
}

test "parse wikilink with alias" {
    const content = "This is a [[test-file|Test File]] link.";
    var wikilinks = try parseWikilinks(content);
    defer {
        for (wikilinks.items) |*link| {
            link.deinit();
        }
        wikilinks.deinit();
    }

    try std.testing.expect(wikilinks.items.len == 1);
    try std.testing.expectEqualStrings("test-file", wikilinks.items[0].target);
    try std.testing.expectEqualStrings("Test File", wikilinks.items[0].alias.?);
}

test "position in wikilink detection" {
    const content = "This is a [[test-file]] link.";
    var wikilinks = try parseWikilinks(content);
    defer {
        for (wikilinks.items) |*link| {
            link.deinit();
        }
        wikilinks.deinit();
    }

    const pos_inside = Position{ .line = 0, .character = 12 };
    const pos_outside = Position{ .line = 0, .character = 5 };

    try std.testing.expect(isPositionInWikilink(wikilinks.items, pos_inside) != null);
    try std.testing.expect(isPositionInWikilink(wikilinks.items, pos_outside) == null);
}
