const std = @import("std");
const types = @import("types.zig");
const parser = @import("../markdown/parser.zig");
const file_index = @import("file_index.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const LinkValidator = struct {

    pub fn init() LinkValidator {
        return LinkValidator{};
    }

    pub fn validateDocument(self: *LinkValidator, file_idx: *file_index.FileIndex, uri: []const u8, wikilinks: []const parser.WikiLink) ![]types.Diagnostic {
        _ = self;
        _ = uri;
        var diagnostics = std.ArrayList(types.Diagnostic).init(allocator);
        errdefer {
            for (diagnostics.items) |*diagnostic| {
                allocator.free(diagnostic.message);
                if (diagnostic.source) |source| {
                    allocator.free(source);
                }
            }
            diagnostics.deinit();
        }

        for (wikilinks) |link| {
            if (file_idx.resolveWikilink(link.target) == null) {
                const diagnostic = try createBrokenLinkDiagnostic(link);
                try diagnostics.append(diagnostic);
            }
        }

        return try diagnostics.toOwnedSlice();
    }

fn createBrokenLinkDiagnostic(link: parser.WikiLink) !types.Diagnostic {
    const message = try std.fmt.allocPrint(allocator, "Broken wikilink: target file '{s}' not found", .{link.target});
    
    return types.Diagnostic{
        .range = link.range,
        .severity = types.DiagnosticSeverity.Error,
        .message = message,
        .source = try allocator.dupe(u8, "zig-notes-lsp"),
    };
}

    pub fn freeDiagnostic(self: *LinkValidator, diagnostic: *types.Diagnostic) void {
        _ = self;
        allocator.free(diagnostic.message);
        if (diagnostic.source) |source| {
            allocator.free(source);
        }
    }

    pub fn freeDiagnostics(self: *LinkValidator, diagnostics: []types.Diagnostic) void {
        for (diagnostics) |*diagnostic| {
            self.freeDiagnostic(diagnostic);
        }
        allocator.free(diagnostics);
    }
};

test "link validator detects broken links" {
    var test_file_index = file_index.FileIndex.init();
    defer test_file_index.deinit();

    // Create a temporary file for testing
    const test_path = "existing-file.md";
    const test_file = try std.fs.cwd().createFile(test_path, .{});
    test_file.close();
    defer std.fs.cwd().deleteFile(test_path) catch {};

    try test_file_index.addFile("existing-file.md");

    var validator = LinkValidator.init();

    const content = "This has a [[existing-file]] and a [[missing-file]] link.";
    var wikilinks = try parser.parseWikilinks(content);
    defer {
        for (wikilinks.items) |*link| {
            link.deinit();
        }
        wikilinks.deinit();
    }

    const diagnostics = try validator.validateDocument(&test_file_index, "test.md", wikilinks.items);
    defer validator.freeDiagnostics(diagnostics);

    try std.testing.expect(diagnostics.len == 1);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics[0].message, "missing-file") != null);
    try std.testing.expect(diagnostics[0].severity == types.DiagnosticSeverity.Error);
}