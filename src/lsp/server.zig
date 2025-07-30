const std = @import("std");
const types = @import("types.zig");
const protocol = @import("protocol.zig");
const discovery = @import("../markdown/discovery.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const LspServer = struct {
    initialized: bool = false,
    shutdown_requested: bool = false,
    workspace_path: ?[]const u8 = null,
    markdown_files: std.ArrayList(discovery.MarkdownFile),

    pub fn init() LspServer {
        return LspServer{
            .markdown_files = std.ArrayList(discovery.MarkdownFile).init(allocator),
        };
    }

    pub fn deinit(self: *LspServer) void {
        for (self.markdown_files.items) |*file| {
            file.deinit();
        }
        self.markdown_files.deinit();

        if (self.workspace_path) |path| {
            allocator.free(path);
        }
    }

    pub fn handleMessage(self: *LspServer, writer: anytype, message: protocol.Message) !void {
        switch (message) {
            .request => |request| try self.handleRequest(writer, request),
            .notification => |notification| try self.handleNotification(writer, notification),
            .response => {}, // We don't send requests, so we don't handle responses
        }
    }

    fn handleRequest(self: *LspServer, writer: anytype, request: types.JsonRpcRequest) !void {
        if (std.mem.eql(u8, request.method, "initialize")) {
            try self.handleInitialize(writer, request);
        } else if (std.mem.eql(u8, request.method, "shutdown")) {
            try self.handleShutdown(writer, request);
        } else {
            try protocol.writeError(writer, request.id, -32601, "Method not found");
        }
    }

    fn handleNotification(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        if (std.mem.eql(u8, notification.method, "initialized")) {
            try self.handleInitialized(writer, notification);
        } else if (std.mem.eql(u8, notification.method, "exit")) {
            std.process.exit(if (self.shutdown_requested) 0 else 1);
        } else if (std.mem.eql(u8, notification.method, "textDocument/didOpen")) {
            try self.handleDidOpen(writer, notification);
        } else if (std.mem.eql(u8, notification.method, "textDocument/didClose")) {
            try self.handleDidClose(writer, notification);
        } else if (std.mem.eql(u8, notification.method, "textDocument/didChange")) {
            try self.handleDidChange(writer, notification);
        }
        // Ignore unknown notifications
    }

    fn handleInitialize(self: *LspServer, writer: anytype, request: types.JsonRpcRequest) !void {
        // For now, just use current directory as workspace
        self.workspace_path = try allocator.dupe(u8, ".");

        // Discover markdown files if we have a workspace
        if (self.workspace_path) |workspace| {
            self.markdown_files = discovery.discoverMarkdownFiles(workspace) catch |err| blk: {
                std.log.warn("Failed to discover markdown files: {}", .{err});
                break :blk std.ArrayList(discovery.MarkdownFile).init(allocator);
            };
        }

        const trigger_chars = [_][]const u8{ "[", "#" };
        const server_capabilities = types.ServerCapabilities{
            .text_document_sync = 1, // Full sync
            .hover_provider = true,
            .completion_provider = types.CompletionOptions{
                .resolve_provider = false,
                .trigger_characters = &trigger_chars,
            },
            .definition_provider = true,
            .references_provider = true,
            .document_symbol_provider = true,
            .rename_provider = true,
        };

        const server_info = types.ServerInfo{
            .name = "zig-notes-lsp",
            .version = "0.1.0",
        };

        const result = types.InitializeResult{
            .capabilities = server_capabilities,
            .server_info = server_info,
        };

        try protocol.writeResponse(writer, request.id, result);
    }

    fn handleInitialized(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        _ = writer;
        _ = notification;
        self.initialized = true;
        std.log.info("LSP server initialized with {} markdown files", .{self.markdown_files.items.len});
    }

    fn handleShutdown(self: *LspServer, writer: anytype, request: types.JsonRpcRequest) !void {
        self.shutdown_requested = true;
        try protocol.writeResponse(writer, request.id, null);
    }

    fn handleDidOpen(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        _ = self;
        _ = writer;
        _ = notification;
        // Stub implementation - just log that we received the notification
        std.log.debug("Received textDocument/didOpen notification", .{});
    }

    fn handleDidClose(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        _ = self;
        _ = writer;
        _ = notification;
        // Stub implementation - just log that we received the notification
        std.log.debug("Received textDocument/didClose notification", .{});
    }

    fn handleDidChange(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        _ = self;
        _ = writer;
        _ = notification;
        // Stub implementation - just log that we received the notification
        std.log.debug("Received textDocument/didChange notification", .{});
    }
};
