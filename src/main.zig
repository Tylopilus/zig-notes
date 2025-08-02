const std = @import("std");
const LspServer = @import("lsp/server.zig").LspServer;
const protocol = @import("lsp/protocol.zig");
const allocator_utils = @import("utils/allocator.zig");

pub fn main() !void {
    defer allocator_utils.deinit();

    // Initialize server
    var server = LspServer.init();
    defer server.deinit();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();


    // Main server loop
    while (true) {
        if (protocol.readMessage(stdin)) |maybe_message| {
            if (maybe_message) |message| {
                server.handleMessage(stdout, message) catch |err| {
                    std.log.err("Error handling message: {}", .{err});
                    continue;
                };
                
                // Check for file system changes after handling messages
                server.checkFileSystemChanges(stdout) catch |err| {
                    std.log.warn("Error checking file system changes: {}", .{err});
                };
            } else {
                // EOF reached, exit gracefully
                break;
            }
        } else |err| {
            std.log.err("Error reading message: {}", .{err});
            continue;
        }
    }

}

test "basic server functionality" {
    const testing = std.testing;

    var server = LspServer.init();
    defer server.deinit();

    try testing.expect(!server.initialized);
    try testing.expect(!server.shutdown_requested);
}
