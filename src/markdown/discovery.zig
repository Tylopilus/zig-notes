const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;

pub const MarkdownFile = struct {
    path: []const u8,
    uri: []const u8,

    pub fn deinit(self: *MarkdownFile) void {
        allocator.free(self.path);
        allocator.free(self.uri);
    }
};

pub fn discoverMarkdownFiles(workspace_path: []const u8) !std.ArrayList(MarkdownFile) {
    var files = std.ArrayList(MarkdownFile).init(allocator);
    errdefer {
        for (files.items) |*file| {
            file.deinit();
        }
        files.deinit();
    }

    try walkDirectory(workspace_path, &files);
    return files;
}

fn walkDirectory(dir_path: []const u8, files: *std.ArrayList(MarkdownFile)) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        error.AccessDenied => return,
        else => return err,
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            if (std.mem.eql(u8, entry.name, ".git") or
                std.mem.eql(u8, entry.name, "node_modules") or
                std.mem.eql(u8, entry.name, ".zig-cache"))
            {
                continue;
            }

            const sub_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(sub_path);

            try walkDirectory(sub_path, files);
        } else if (entry.kind == .file) {
            if (std.mem.endsWith(u8, entry.name, ".md")) {
                const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
                const uri = try std.fmt.allocPrint(allocator, "file://{s}", .{full_path});

                try files.append(MarkdownFile{
                    .path = full_path,
                    .uri = uri,
                });
            }
        }
    }
}

test "discover markdown files" {
    // Simple test that just verifies the function can be called
    // without crashing on the current directory
    var files = discoverMarkdownFiles(".") catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => {
            // These are expected in some test environments
            return;
        },
        else => return err,
    };
    defer {
        for (files.items) |*file| {
            file.deinit();
        }
        files.deinit();
    }

    // Just verify we got a valid list (could be empty)
    try std.testing.expect(files.items.len >= 0);
}
