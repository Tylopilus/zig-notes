const std = @import("std");
const types = @import("types.zig");
const protocol = @import("protocol.zig");
const discovery = @import("../markdown/discovery.zig");
const file_index = @import("file_index.zig");
const document_manager = @import("document_manager.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const LspServer = struct {
    initialized: bool = false,
    shutdown_requested: bool = false,
    workspace_path: ?[]const u8 = null,
    markdown_files: std.ArrayList(discovery.MarkdownFile),
    file_index: file_index.FileIndex,
    document_manager: document_manager.DocumentManager,

    pub fn init() LspServer {
        return LspServer{
            .markdown_files = std.ArrayList(discovery.MarkdownFile).init(allocator),
            .file_index = file_index.FileIndex.init(),
            .document_manager = document_manager.DocumentManager.init(),
        };
    }

    pub fn deinit(self: *LspServer) void {
        for (self.markdown_files.items) |*file| {
            file.deinit();
        }
        self.markdown_files.deinit();
        self.file_index.deinit();
        self.document_manager.deinit();

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
        } else if (std.mem.eql(u8, request.method, "textDocument/definition")) {
            try self.handleDefinition(writer, request);
        } else if (std.mem.eql(u8, request.method, "textDocument/completion")) {
            try self.handleCompletion(writer, request);
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

            // Build file index
            for (self.markdown_files.items) |markdown_file| {
                self.file_index.addFile(markdown_file.path) catch |err| {
                    std.log.warn("Failed to add file to index: {} - {s}", .{ err, markdown_file.path });
                };
            }
        }

        const trigger_chars = [_][]const u8{ "[", "#" };
        const server_capabilities = types.ServerCapabilities{
            .textDocumentSync = types.TextDocumentSyncOptions{
                .openClose = true,
                .change = 1, // Full sync
                .willSave = false,
                .willSaveWaitUntil = false,
                .save = types.SaveOptions{ .includeText = false },
            },
            .hoverProvider = true,
            .completionProvider = types.CompletionOptions{
                .resolveProvider = false,
                .triggerCharacters = &trigger_chars,
            },
            .definitionProvider = true,
            .referencesProvider = true,
            .documentSymbolProvider = true,
            .renameProvider = true,
        };

        const server_info = types.ServerInfo{
            .name = "zig-notes-lsp",
            .version = "0.1.0",
        };

        const result = types.InitializeResult{
            .capabilities = server_capabilities,
            .server_info = server_info,
        };

        std.log.debug("Sending initialize response with capabilities", .{});
        try protocol.writeResponse(writer, request.id, result);
        std.log.debug("Initialize response sent successfully", .{});
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
        _ = writer;
        if (notification.params) |params| {
            if (parseDidOpenParams(params)) |did_open_params| {
                try self.document_manager.didOpen(
                    did_open_params.text_document.uri,
                    did_open_params.text_document.text,
                    did_open_params.text_document.version,
                );
                std.log.debug("Opened document: {s}", .{did_open_params.text_document.uri});
            } else |err| {
                std.log.warn("Failed to parse didOpen params: {}", .{err});
            }
        }
    }

    fn handleDidClose(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        _ = writer;
        if (notification.params) |params| {
            if (parseDidCloseParams(params)) |did_close_params| {
                self.document_manager.didClose(did_close_params.text_document.uri);
                std.log.debug("Closed document: {s}", .{did_close_params.text_document.uri});
            } else |err| {
                std.log.warn("Failed to parse didClose params: {}", .{err});
            }
        }
    }

    fn handleDidChange(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        _ = writer;
        if (notification.params) |params| {
            if (parseDidChangeParams(params)) |did_change_params| {
                // For full sync, we expect one change event with the full text
                if (did_change_params.content_changes.len > 0) {
                    const change = did_change_params.content_changes[0];
                    try self.document_manager.didChange(
                        did_change_params.text_document.uri,
                        change.text,
                        did_change_params.text_document.version orelse 0,
                    );
                    std.log.debug("Changed document: {s}", .{did_change_params.text_document.uri});
                }
            } else |err| {
                std.log.warn("Failed to parse didChange params: {}", .{err});
            }
        }
    }

    fn handleDefinition(self: *LspServer, writer: anytype, request: types.JsonRpcRequest) !void {
        if (request.params) |params| {
            if (parseDefinitionParams(params)) |def_params| {
                // Check if cursor is on a wikilink
                if (self.document_manager.getWikilinkAtPosition(def_params.text_document.uri, def_params.position)) |wikilink| {
                    // Resolve wikilink to file path
                    if (self.file_index.resolveWikilink(wikilink.target)) |target_path| {
                        // Convert relative path to absolute path
                        const absolute_path = if (std.fs.path.isAbsolute(target_path)) 
                            try allocator.dupe(u8, target_path)
                        else 
                            try std.fs.cwd().realpathAlloc(allocator, target_path);
                        defer allocator.free(absolute_path);
                        
                        const target_uri = try document_manager.pathToUri(absolute_path);
                        defer allocator.free(target_uri);

                        const location = types.Location{
                            .uri = target_uri,
                            .range = types.Range{
                                .start = types.Position{ .line = 0, .character = 0 },
                                .end = types.Position{ .line = 0, .character = 0 },
                            },
                        };

                        try protocol.writeResponse(writer, request.id, location);
                        return;
                    }
                }

                // No definition found
                try protocol.writeResponse(writer, request.id, null);
            } else |err| {
                std.log.warn("Failed to parse definition params: {}", .{err});
                try protocol.writeError(writer, request.id, -32602, "Invalid params");
            }
        } else {
            try protocol.writeError(writer, request.id, -32602, "Invalid params");
        }
    }

    fn handleCompletion(self: *LspServer, writer: anytype, request: types.JsonRpcRequest) !void {
        if (request.params) |params| {
            if (parseCompletionParams(params)) |completion_params| {
                // Check if we're in a wikilink context
                if (self.document_manager.getDocument(completion_params.textDocument.uri)) |document| {
                    if (self.isWikilinkContext(document.content, completion_params.position)) {
                        // Generate completion items from file index
                        var completion_items = std.ArrayList(types.CompletionItem).init(allocator);
                        defer {
                            for (completion_items.items) |*item| {
                                allocator.free(item.label);
                                if (item.insertText) |text| allocator.free(text);
                                if (item.detail) |detail| allocator.free(detail);
                            }
                            completion_items.deinit();
                        }

                        for (self.file_index.all_files.items) |file_metadata| {
                            // Convert file path to URI for comparison
                            const file_uri = document_manager.pathToUri(file_metadata.path) catch continue;
                            defer allocator.free(file_uri);
                            
                            // Skip the current file
                            if (std.mem.eql(u8, file_uri, completion_params.textDocument.uri)) continue;

                            // Get the filename with extension
                            const filename = std.fs.path.basename(file_metadata.path);
                            const insert_text = try std.fmt.allocPrint(allocator, "{s}]]", .{filename});
                            const detail = try allocator.dupe(u8, file_metadata.path);

                            const item = types.CompletionItem{
                                .label = try allocator.dupe(u8, filename),
                                .kind = 17, // File completion kind
                                .detail = detail,
                                .insertText = insert_text,
                                .filterText = try allocator.dupe(u8, filename),
                            };
                            try completion_items.append(item);
                        }

                        const completion_list = types.CompletionList{
                            .isIncomplete = false,
                            .items = try allocator.dupe(types.CompletionItem, completion_items.items),
                        };
                        defer allocator.free(completion_list.items);

                        try protocol.writeResponse(writer, request.id, completion_list);
                        return;
                    }
                }

                // No completion available
                const empty_list = types.CompletionList{
                    .isIncomplete = false,
                    .items = &[_]types.CompletionItem{},
                };
                try protocol.writeResponse(writer, request.id, empty_list);
            } else |err| {
                std.log.warn("Failed to parse completion params: {}", .{err});
                try protocol.writeError(writer, request.id, -32602, "Invalid params");
            }
        } else {
            try protocol.writeError(writer, request.id, -32602, "Invalid params");
        }
    }

    fn isWikilinkContext(self: *LspServer, content: []const u8, position: types.Position) bool {
        _ = self;
        // Look backwards from cursor position to find [[ without matching ]]
        
        // Convert position to byte offset
        var line: u32 = 0;
        var character: u32 = 0;
        var cursor_offset: usize = 0;
        
        for (content, 0..) |c, i| {
            if (line == position.line and character == position.character) {
                cursor_offset = i;
                break;
            }
            if (c == '\n') {
                line += 1;
                character = 0;
            } else {
                character += 1;
            }
        }
        
        // Look backwards from cursor to find the most recent [[ or ]]
        var i = cursor_offset;
        while (i >= 2) {
            i -= 1;
            if (i + 1 < content.len and content[i] == '[' and content[i + 1] == '[') {
                return true; // Found opening [[
            }
            if (i + 1 < content.len and content[i] == ']' and content[i + 1] == ']') {
                return false; // Found closing ]]
            }
        }
        
        return false; // No [[ found
    }
};

fn parseDidOpenParams(params: std.json.Value) !types.DidOpenTextDocumentParams {
    const obj = switch (params) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const text_document_value = obj.get("textDocument") orelse return error.InvalidParams;
    const text_document_obj = switch (text_document_value) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const uri = switch (text_document_obj.get("uri") orelse return error.InvalidParams) {
        .string => |s| s,
        else => return error.InvalidParams,
    };

    const language_id = switch (text_document_obj.get("languageId") orelse return error.InvalidParams) {
        .string => |s| s,
        else => return error.InvalidParams,
    };

    const version = switch (text_document_obj.get("version") orelse return error.InvalidParams) {
        .integer => |i| @as(i32, @intCast(i)),
        else => return error.InvalidParams,
    };

    const text = switch (text_document_obj.get("text") orelse return error.InvalidParams) {
        .string => |s| s,
        else => return error.InvalidParams,
    };

    return types.DidOpenTextDocumentParams{
        .text_document = types.TextDocumentItem{
            .uri = uri,
            .language_id = language_id,
            .version = version,
            .text = text,
        },
    };
}

fn parseDidCloseParams(params: std.json.Value) !types.DidCloseTextDocumentParams {
    const obj = switch (params) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const text_document_value = obj.get("textDocument") orelse return error.InvalidParams;
    const text_document_obj = switch (text_document_value) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const uri = switch (text_document_obj.get("uri") orelse return error.InvalidParams) {
        .string => |s| s,
        else => return error.InvalidParams,
    };

    return types.DidCloseTextDocumentParams{
        .text_document = types.TextDocumentIdentifier{
            .uri = uri,
        },
    };
}

fn parseDidChangeParams(params: std.json.Value) !types.DidChangeTextDocumentParams {
    const obj = switch (params) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const text_document_value = obj.get("textDocument") orelse return error.InvalidParams;
    const text_document_obj = switch (text_document_value) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const uri = switch (text_document_obj.get("uri") orelse return error.InvalidParams) {
        .string => |s| s,
        else => return error.InvalidParams,
    };

    const version = if (text_document_obj.get("version")) |v| switch (v) {
        .integer => |i| @as(i32, @intCast(i)),
        .null => null,
        else => return error.InvalidParams,
    } else null;

    const content_changes_value = obj.get("contentChanges") orelse return error.InvalidParams;
    const content_changes_array = switch (content_changes_value) {
        .array => |a| a,
        else => return error.InvalidParams,
    };

    var content_changes = try allocator.alloc(types.TextDocumentContentChangeEvent, content_changes_array.items.len);
    for (content_changes_array.items, 0..) |change_value, i| {
        const change_obj = switch (change_value) {
            .object => |o| o,
            else => return error.InvalidParams,
        };

        const text = switch (change_obj.get("text") orelse return error.InvalidParams) {
            .string => |s| s,
            else => return error.InvalidParams,
        };

        content_changes[i] = types.TextDocumentContentChangeEvent{
            .text = text,
        };
    }

    return types.DidChangeTextDocumentParams{
        .text_document = types.VersionedTextDocumentIdentifier{
            .uri = uri,
            .version = version,
        },
        .content_changes = content_changes,
    };
}

fn parseDefinitionParams(params: std.json.Value) !types.DefinitionParams {
    const obj = switch (params) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const text_document_value = obj.get("textDocument") orelse return error.InvalidParams;
    const text_document_obj = switch (text_document_value) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const uri = switch (text_document_obj.get("uri") orelse return error.InvalidParams) {
        .string => |s| s,
        else => return error.InvalidParams,
    };

    const position_value = obj.get("position") orelse return error.InvalidParams;
    const position_obj = switch (position_value) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const line = switch (position_obj.get("line") orelse return error.InvalidParams) {
        .integer => |i| @as(u32, @intCast(i)),
        else => return error.InvalidParams,
    };

    const character = switch (position_obj.get("character") orelse return error.InvalidParams) {
        .integer => |i| @as(u32, @intCast(i)),
        else => return error.InvalidParams,
    };

    return types.DefinitionParams{
        .text_document = types.TextDocumentIdentifier{
            .uri = uri,
        },
        .position = types.Position{
            .line = line,
            .character = character,
        },
    };
}

fn parseCompletionParams(params: std.json.Value) !types.CompletionParams {
    const obj = switch (params) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const text_document_value = obj.get("textDocument") orelse return error.InvalidParams;
    const text_document_obj = switch (text_document_value) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const uri = switch (text_document_obj.get("uri") orelse return error.InvalidParams) {
        .string => |s| s,
        else => return error.InvalidParams,
    };

    const position_value = obj.get("position") orelse return error.InvalidParams;
    const position_obj = switch (position_value) {
        .object => |o| o,
        else => return error.InvalidParams,
    };

    const line = switch (position_obj.get("line") orelse return error.InvalidParams) {
        .integer => |i| @as(u32, @intCast(i)),
        else => return error.InvalidParams,
    };

    const character = switch (position_obj.get("character") orelse return error.InvalidParams) {
        .integer => |i| @as(u32, @intCast(i)),
        else => return error.InvalidParams,
    };

    return types.CompletionParams{
        .textDocument = types.TextDocumentIdentifier{
            .uri = uri,
        },
        .position = types.Position{
            .line = line,
            .character = character,
        },
    };
}
