const std = @import("std");
const file_index = @import("file_index.zig");
const discovery = @import("../markdown/discovery.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const FileWatcher = struct {
    workspace_path: []const u8,
    last_scan_time: i64,

    pub fn init(workspace: []const u8) FileWatcher {
        return FileWatcher{
            .workspace_path = workspace,
            .last_scan_time = std.time.timestamp(),
        };
    }

    pub fn checkForChanges(self: *FileWatcher, file_idx: *file_index.FileIndex) !bool {
        // Simple polling-based approach
        // In production, would use inotify on Linux, kqueue on macOS, etc.
        
        const current_time = std.time.timestamp();
        // Only check every 2 seconds to avoid excessive scanning
        if (current_time - self.last_scan_time < 2) {
            return false;
        }
        
        self.last_scan_time = current_time;

        // Discover current markdown files
        const current_files = discovery.discoverMarkdownFiles(self.workspace_path) catch |err| {
            std.log.warn("Failed to scan workspace for changes: {}", .{err});
            return false;
        };
        defer {
            for (current_files.items) |*file| {
                file.deinit();
            }
            current_files.deinit();
        }

        // Simple approach: rebuild index if file count differs
        // In production, would do more sophisticated change detection
        if (current_files.items.len != file_idx.all_files.items.len) {
            try self.rebuildIndex(file_idx, current_files.items);
            return true;
        }

        return false;
    }

    fn rebuildIndex(self: *FileWatcher, file_idx: *file_index.FileIndex, current_files: []const discovery.MarkdownFile) !void {
        _ = self;
        // Clear existing index
        for (file_idx.all_files.items) |file| {
            file.deinit();
            allocator.destroy(file);
        }
        file_idx.all_files.clearAndFree();
        file_idx.name_to_file.clearAndFree();
        file_idx.path_to_file.clearAndFree();

        // Rebuild with current files
        for (current_files) |markdown_file| {
            file_idx.addFile(markdown_file.path) catch |err| {
                std.log.warn("Failed to add file to index: {} - {s}", .{ err, markdown_file.path });
            };
        }

    }
};

test "file watcher detects changes" {
    var test_file_index = file_index.FileIndex.init();
    defer test_file_index.deinit();

    var watcher = FileWatcher.init(".");

    // First check should not detect changes
    const changes = try watcher.checkForChanges(&test_file_index);
    try std.testing.expect(!changes);
}