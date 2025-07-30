const std = @import("std");
const LspServer = @import("lsp/server.zig").LspServer;
const protocol = @import("lsp/protocol.zig");
const allocator_utils = @import("utils/allocator.zig");

pub fn main() !void {
    defer allocator_utils.deinit();

    // Set up logging
    var log_file = std.fs.cwd().createFile("lsp.log", .{}) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer log_file.close();

    // Initialize server
    var server = LspServer.init();
    defer server.deinit();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    std.log.info("LSP server starting...", .{});

    // Main server loop
    while (true) {
        if (protocol.readMessage(stdin)) |maybe_message| {
            if (maybe_message) |message| {
                server.handleMessage(stdout, message) catch |err| {
                    std.log.err("Error handling message: {}", .{err});
                    continue;
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

    std.log.info("LSP server shutting down...", .{});
}

test "basic server functionality" {
    const testing = std.testing;

    var server = LspServer.init();
    defer server.deinit();

    try testing.expect(!server.initialized);
    try testing.expect(!server.shutdown_requested);
}
