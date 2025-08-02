const std = @import("std");
const types = @import("types.zig");
const protocol = @import("protocol.zig");
const discovery = @import("../markdown/discovery.zig");
const file_index = @import("file_index.zig");
const tag_index = @import("tag_index.zig");
const document_manager = @import("document_manager.zig");
const fuzzy = @import("fuzzy.zig");
const link_validator = @import("link_validator.zig");
const file_watcher = @import("file_watcher.zig");
const frontmatter = @import("../markdown/frontmatter.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const LspServer = struct {
    initialized: bool = false,
    shutdown_requested: bool = false,
    workspace_path: ?[]const u8 = null,
    markdown_files: std.ArrayList(discovery.MarkdownFile),
    file_index: file_index.FileIndex,
    tag_index: tag_index.TagIndex,
    document_manager: document_manager.DocumentManager,
    link_validator: link_validator.LinkValidator,
    file_watcher: ?file_watcher.FileWatcher,

    pub fn init() LspServer {
        var server = LspServer{
            .markdown_files = std.ArrayList(discovery.MarkdownFile).init(allocator),
            .file_index = file_index.FileIndex.init(),
            .tag_index = tag_index.TagIndex.init(),
            .document_manager = document_manager.DocumentManager.init(),
            .link_validator = undefined,
            .file_watcher = null,
        };
        server.link_validator = link_validator.LinkValidator.init();
        return server;
    }

    pub fn deinit(self: *LspServer) void {
        for (self.markdown_files.items) |*file| {
            file.deinit();
        }
        self.markdown_files.deinit();
        self.file_index.deinit();
        self.tag_index.deinit();
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
        } else if (std.mem.eql(u8, request.method, "textDocument/hover")) {
            try self.handleHover(writer, request);
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
        } else if (std.mem.eql(u8, notification.method, "textDocument/didSave")) {
            try self.handleDidSave(writer, notification);
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

            // Build file index and tag index
            for (self.markdown_files.items) |markdown_file| {
                self.file_index.addFile(markdown_file.path) catch |err| {
                    std.log.warn("Failed to add file to index: {} - {s}", .{ err, markdown_file.path });
                };

                // Read file content and build tag index
                const file_content = std.fs.cwd().readFileAlloc(allocator, markdown_file.path, 1024 * 1024) catch |err| {
                    std.log.warn("Failed to read file for tag indexing: {} - {s}", .{ err, markdown_file.path });
                    continue;
                };
                defer allocator.free(file_content);

                self.tag_index.addTagsFromFile(markdown_file.path, file_content) catch |err| {
                    std.log.warn("Failed to add tags from file: {} - {s}", .{ err, markdown_file.path });
                };
            }
        }

        const trigger_chars = [_][]const u8{ "[", "," };
        const server_capabilities = types.ServerCapabilities{
            .textDocumentSync = types.TextDocumentSyncOptions{
                .openClose = true,
                .change = 1, // Full sync
                .willSave = false,
                .willSaveWaitUntil = false,
                .save = types.SaveOptions{ .includeText = true },
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

        try protocol.writeResponse(writer, request.id, result);
    }

    fn handleInitialized(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        _ = writer;
        _ = notification;
        self.initialized = true;
        
        // Initialize file watcher if we have a workspace
        if (self.workspace_path) |workspace| {
            self.file_watcher = file_watcher.FileWatcher.init(workspace);
        }
    }

    fn handleShutdown(self: *LspServer, writer: anytype, request: types.JsonRpcRequest) !void {
        self.shutdown_requested = true;
        try protocol.writeResponse(writer, request.id, null);
    }

    fn handleDidOpen(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        if (notification.params) |params| {
            if (parseDidOpenParams(params)) |did_open_params| {
                try self.document_manager.didOpen(
                    did_open_params.text_document.uri,
                    did_open_params.text_document.text,
                    did_open_params.text_document.version,
                );
                
                // Validate links and publish diagnostics
                try self.validateAndPublishDiagnostics(writer, did_open_params.text_document.uri);
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
            } else |err| {
                std.log.warn("Failed to parse didClose params: {}", .{err});
            }
        }
    }

    fn handleDidChange(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
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
                    
                    // Update tag index with new content
                    const file_path = document_manager.uriToPath(did_change_params.text_document.uri) catch |err| {
                        std.log.warn("Failed to convert URI to path for tag indexing: {}", .{err});
                        return;
                    };
                    defer allocator.free(file_path);
                    
                    self.tag_index.addTagsFromFile(file_path, change.text) catch |err| {
                        std.log.warn("Failed to update tag index: {}", .{err});
                    };
                    
                    // Validate links and publish diagnostics
                    try self.validateAndPublishDiagnostics(writer, did_change_params.text_document.uri);
                }
            } else |err| {
                std.log.warn("Failed to parse didChange params: {}", .{err});
            }
        }
    }

    fn handleDidSave(self: *LspServer, writer: anytype, notification: types.JsonRpcNotification) !void {
        if (notification.params) |params| {
            if (parseDidSaveParams(params)) |did_save_params| {
                // Validate links and publish diagnostics on save
                try self.validateAndPublishDiagnostics(writer, did_save_params.textDocument.uri);
            } else |err| {
                std.log.warn("Failed to parse didSave params: {}", .{err});
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

    const CompletionContext = enum {
        wikilink,  // Inside [[...]]
        tag,       // In frontmatter tags array
        none,      // No special context
    };

    fn detectCompletionContext(self: *LspServer, content: []const u8, position: types.Position) CompletionContext {
        // Check for wikilink context first
        if (self.isWikilinkContext(content, position)) {
            return .wikilink;
        }
        
        // Check for frontmatter tags context
        if (frontmatter.getTagsLineInfo(content, position)) |_| {
            return .tag;
        }
        
        return .none;
    }

    fn completeFilenames(self: *LspServer, completion_params: types.CompletionParams, document: *document_manager.Document) !types.CompletionList {
        // Extract query from the wikilink
        const query = self.extractWikilinkQuery(document.content, completion_params.position) catch "";
        defer if (query.len > 0) allocator.free(query);
        
        // Collect all candidate filenames
        var candidates = std.ArrayList([]const u8).init(allocator);
        defer {
            for (candidates.items) |candidate| {
                allocator.free(candidate);
            }
            candidates.deinit();
        }
        
        for (self.file_index.all_files.items) |file_metadata| {
            // Convert file path to URI for comparison
            const file_uri = document_manager.pathToUri(file_metadata.path) catch continue;
            defer allocator.free(file_uri);
            
            // Skip the current file
            if (std.mem.eql(u8, file_uri, completion_params.textDocument.uri)) continue;

            // Get the filename with extension
            const filename = std.fs.path.basename(file_metadata.path);
            try candidates.append(try allocator.dupe(u8, filename));
        }
        
        // Use fuzzy matching to filter and sort candidates
        const fuzzy_matches = try fuzzy.fuzzyMatch(query, candidates.items, 20);
        defer fuzzy.freeFuzzyMatches(fuzzy_matches);
        
        // Generate completion items from fuzzy matches
        var completion_items = std.ArrayList(types.CompletionItem).init(allocator);
        defer completion_items.deinit();

        for (fuzzy_matches) |match| {
            // Find the original file metadata for details
            var detail_path: ?[]const u8 = null;
            for (self.file_index.all_files.items) |file_metadata| {
                const filename = std.fs.path.basename(file_metadata.path);
                if (std.mem.eql(u8, filename, match.text)) {
                    detail_path = file_metadata.path;
                    break;
                }
            }
            
            // Create text edit that replaces from after [[ to cursor position
            const query_range = try self.getWikilinkQueryRange(document.content, completion_params.position);
            const new_text = try std.fmt.allocPrint(allocator, "{s}]]", .{match.text});
            
            const text_edit = types.TextEdit{
                .range = query_range,
                .newText = new_text,
            };

            const item = types.CompletionItem{
                .label = try allocator.dupe(u8, match.text),
                .kind = 17, // File completion kind
                .detail = if (detail_path) |path| try allocator.dupe(u8, path) else null,
                .textEdit = text_edit,
                .filterText = try allocator.dupe(u8, match.text),
            };
            try completion_items.append(item);
        }

        return types.CompletionList{
            .isIncomplete = false,
            .items = try allocator.dupe(types.CompletionItem, completion_items.items),
        };
    }

    fn completeTags(self: *LspServer, completion_params: types.CompletionParams, document: *document_manager.Document) !types.CompletionList {
        // Extract tag prefix
        const prefix = self.extractTagPrefix(document.content, completion_params.position) catch "";
        defer if (prefix.len > 0) allocator.free(prefix);
        
        // Get all tags for fuzzy matching
        const all_tags = try self.tag_index.getAllTags();
        defer {
            for (all_tags) |tag| {
                allocator.free(tag);
            }
            allocator.free(all_tags);
        }
        
        // Use fuzzy matching to filter and sort tags
        const fuzzy_matches = try fuzzy.fuzzyMatch(prefix, all_tags, 20);
        defer fuzzy.freeFuzzyMatches(fuzzy_matches);
        
        // Generate completion items
        var completion_items = std.ArrayList(types.CompletionItem).init(allocator);
        defer completion_items.deinit();

        for (fuzzy_matches) |match| {
            const file_count = self.tag_index.getTagCount(match.text);
            const detail = try std.fmt.allocPrint(allocator, "Used in {} files", .{file_count});
            
            const item = types.CompletionItem{
                .label = try allocator.dupe(u8, match.text),
                .kind = 14, // Keyword completion kind
                .detail = detail,
                .insertText = try allocator.dupe(u8, match.text),
                .filterText = try allocator.dupe(u8, match.text),
            };
            try completion_items.append(item);
        }

        return types.CompletionList{
            .isIncomplete = false,
            .items = try allocator.dupe(types.CompletionItem, completion_items.items),
        };
    }

    fn extractTagPrefix(self: *LspServer, content: []const u8, position: types.Position) ![]const u8 {
        _ = self;
        
        // Get tags line information
        const tags_info = frontmatter.getTagsLineInfo(content, position) orelse {
            return try allocator.dupe(u8, "");
        };
        
        // Find current position within the tags array
        const line_content = tags_info.line_content;
        const tags_start = tags_info.tags_start;
        
        // Convert position to offset within the line
        const char_offset = position.character;
        
        if (char_offset < tags_start) {
            return try allocator.dupe(u8, "");
        }
        
        // Find the start of the current tag being typed
        var tag_start = tags_start;
        var i = tags_start;
        
        while (i < char_offset and i < line_content.len) {
            const c = line_content[i];
            if (c == ',' or c == ']') {
                // Move past comma and whitespace to start of next tag
                tag_start = i + 1;
                while (tag_start < char_offset and tag_start < line_content.len and 
                       std.ascii.isWhitespace(line_content[tag_start])) {
                    tag_start += 1;
                }
            }
            i += 1;
        }
        
        // Extract prefix from tag start to cursor position
        if (char_offset <= tag_start) {
            return try allocator.dupe(u8, "");
        }
        
        const prefix = line_content[tag_start..char_offset];
        return try allocator.dupe(u8, std.mem.trim(u8, prefix, " \t"));
    }

    fn handleCompletion(self: *LspServer, writer: anytype, request: types.JsonRpcRequest) !void {
        if (request.params) |params| {
            if (parseCompletionParams(params)) |completion_params| {
                if (self.document_manager.getDocument(completion_params.textDocument.uri)) |document| {
                    // Detect completion context
                    const context = self.detectCompletionContext(document.content, completion_params.position);
                    
                    switch (context) {
                        .wikilink => {
                            const completion_list = try self.completeFilenames(completion_params, document);
                            defer {
                                for (completion_list.items) |*item| {
                                    allocator.free(item.label);
                                    if (item.insertText) |text| allocator.free(text);
                                    if (item.detail) |detail| allocator.free(detail);
                                    if (item.textEdit) |textEdit| allocator.free(textEdit.newText);
                                    if (item.filterText) |filter| allocator.free(filter);
                                }
                                allocator.free(completion_list.items);
                            }
                            try protocol.writeResponse(writer, request.id, completion_list);
                            return;
                        },
                        .tag => {
                            const completion_list = try self.completeTags(completion_params, document);
                            defer {
                                for (completion_list.items) |*item| {
                                    allocator.free(item.label);
                                    if (item.insertText) |text| allocator.free(text);
                                    if (item.detail) |detail| allocator.free(detail);
                                    if (item.filterText) |filter| allocator.free(filter);
                                }
                                allocator.free(completion_list.items);
                            }
                            try protocol.writeResponse(writer, request.id, completion_list);
                            return;
                        },
                        .none => {},
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

    fn handleHover(self: *LspServer, writer: anytype, request: types.JsonRpcRequest) !void {
        if (request.params) |params| {
            if (parseHoverParams(params)) |hover_params| {
                // Check if cursor is on a wikilink
                if (self.document_manager.getDocument(hover_params.textDocument.uri)) |_| {
                    if (self.document_manager.getWikilinkAtPosition(hover_params.textDocument.uri, hover_params.position)) |wikilink| {
                        // Resolve wikilink to file path
                        if (self.file_index.resolveWikilink(wikilink.target)) |target_path| {
                            // Convert relative path to absolute path
                            const absolute_path = if (std.fs.path.isAbsolute(target_path))
                                try allocator.dupe(u8, target_path)
                            else
                                try std.fs.cwd().realpathAlloc(allocator, target_path);
                            defer allocator.free(absolute_path);

                            // Generate file preview
                            const preview_content = try self.generateFilePreview(absolute_path);
                            defer allocator.free(preview_content);

                            const hover_response = types.Hover{
                                .contents = types.MarkupContent{
                                    .kind = "markdown",
                                    .value = preview_content,
                                },
                                .range = wikilink.range,
                            };

                            try protocol.writeResponse(writer, request.id, hover_response);
                            return;
                        }
                    }
                }

                // No hover information available
                try protocol.writeResponse(writer, request.id, null);
            } else |err| {
                std.log.warn("Failed to parse hover params: {}", .{err});
                try protocol.writeError(writer, request.id, -32602, "Invalid params");
            }
        } else {
            try protocol.writeError(writer, request.id, -32602, "Invalid params");
        }
    }

    fn generateFilePreview(self: *LspServer, file_path: []const u8) ![]const u8 {
        _ = self;
        
        // Try to read the file
        const file = std.fs.openFileAbsolute(file_path, .{}) catch |err| {
            return try std.fmt.allocPrint(allocator, "**File not found**: `{s}`\n\nError: {}", .{ file_path, err });
        };
        defer file.close();

        const file_size = try file.getEndPos();
        if (file_size == 0) {
            return try std.fmt.allocPrint(allocator, "**Empty file**: `{s}`", .{file_path});
        }

        // Limit preview to first 1KB to avoid huge hover windows
        const preview_size = @min(file_size, 1024);
        const content = try allocator.alloc(u8, preview_size);
        defer allocator.free(content);

        _ = try file.readAll(content);

        // Count lines for preview info
        var line_count: usize = 1;
        for (content) |c| {
            if (c == '\n') line_count += 1;
        }

        // Create preview with file info and content
        const filename = std.fs.path.basename(file_path);
        var preview = std.ArrayList(u8).init(allocator);
        defer preview.deinit();

        try preview.writer().print("**📄 {s}**", .{filename});
        
        if (file_size > preview_size) {
            try preview.writer().print(" _(showing first {}B of {}B)_", .{ preview_size, file_size });
        }
        
        try preview.writer().print("\n\n---\n\n", .{});

        // Add the actual content
        try preview.appendSlice(content);

        // If file was truncated, add indicator
        if (file_size > preview_size) {
            try preview.writer().print("\n\n---\n\n_...truncated_", .{});
        }

        return try allocator.dupe(u8, preview.items);
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

    fn extractWikilinkQuery(self: *LspServer, content: []const u8, position: types.Position) ![]const u8 {
        _ = self;
        
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
        
        // Find the start of the current wikilink [[
        var start_offset: ?usize = null;
        var i = cursor_offset;
        while (i >= 2) {
            i -= 1;
            if (i + 1 < content.len and content[i] == '[' and content[i + 1] == '[') {
                start_offset = i + 2; // Start after [[
                break;
            }
        }
        
        if (start_offset == null) {
            return try allocator.dupe(u8, ""); // No [[ found
        }
        
        // Extract text between [[ and cursor position
        const query_start = start_offset.?;
        if (cursor_offset <= query_start) {
            return try allocator.dupe(u8, ""); // Cursor is before or at [[
        }
        
        // Check if there's a pipe character (alias separator) before cursor
        var query_end = cursor_offset;
        for (content[query_start..cursor_offset], query_start..) |c, idx| {
            if (c == '|') {
                query_end = idx;
                break;
            }
        }
        
        const query = content[query_start..query_end];
        return try allocator.dupe(u8, query);
    }

    fn getWikilinkQueryRange(self: *LspServer, content: []const u8, position: types.Position) !types.Range {
        _ = self;
        
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
        
        // Find the start of the current wikilink [[
        var start_offset: ?usize = null;
        var start_line: u32 = 0;
        var start_char: u32 = 0;
        
        var i = cursor_offset;
        var temp_line = position.line;
        var temp_char = position.character;
        
        while (i >= 2) {
            i -= 1;
            if (temp_char == 0) {
                temp_line -= 1;
                // Find the length of the previous line
                var prev_line_len: u32 = 0;
                var j = i;
                while (j > 0 and content[j] != '\n') {
                    j -= 1;
                    prev_line_len += 1;
                }
                temp_char = prev_line_len;
            } else {
                temp_char -= 1;
            }
            
            if (i + 1 < content.len and content[i] == '[' and content[i + 1] == '[') {
                start_offset = i + 2; // Start after [[
                start_line = temp_line;
                start_char = temp_char + 2;
                break;
            }
        }
        
        if (start_offset == null) {
            // Fallback: replace from cursor position
            return types.Range{
                .start = position,
                .end = position,
            };
        }
        
        // Check if there's a pipe character (alias separator) before cursor
        var query_end_line = position.line;
        var query_end_char = position.character;
        
        for (content[start_offset.?..cursor_offset], start_offset.?..) |c, idx| {
            if (c == '|') {
                // Convert byte offset back to line/character
                var calc_line: u32 = 0;
                var calc_char: u32 = 0;
                for (content[0..idx]) |byte| {
                    if (byte == '\n') {
                        calc_line += 1;
                        calc_char = 0;
                    } else {
                        calc_char += 1;
                    }
                }
                query_end_line = calc_line;
                query_end_char = calc_char;
                break;
            }
        }
        
        return types.Range{
            .start = types.Position{ .line = start_line, .character = start_char },
            .end = types.Position{ .line = query_end_line, .character = query_end_char },
        };
    }

    fn clearDiagnostics(self: *LspServer, writer: anytype, uri: []const u8) !void {
        _ = self;
        const uri_copy = try allocator.dupe(u8, uri);
        defer allocator.free(uri_copy);
        
        const empty_diagnostics: []types.Diagnostic = &[_]types.Diagnostic{};
        const params = types.PublishDiagnosticsParams{
            .uri = uri_copy,
            .version = null,
            .diagnostics = empty_diagnostics,
        };
        
        try protocol.writeNotification(writer, "textDocument/publishDiagnostics", params);
    }

    fn validateAndPublishDiagnostics(self: *LspServer, writer: anytype, uri: []const u8) !void {
        if (self.document_manager.getDocument(uri)) |document| {
            // First clear existing diagnostics
            try self.clearDiagnostics(writer, uri);
            
            const diagnostics = try self.link_validator.validateDocument(&self.file_index, uri, document.wikilinks.items);
            defer self.link_validator.freeDiagnostics(diagnostics);

            // Create params with proper URI (ensure it's a copy for safety)
            const uri_copy = try allocator.dupe(u8, uri);
            defer allocator.free(uri_copy);
            
            const params = types.PublishDiagnosticsParams{
                .uri = uri_copy,
                .version = document.version,
                .diagnostics = diagnostics,
            };

            try protocol.writeNotification(writer, "textDocument/publishDiagnostics", params);
        }
    }

    pub fn checkFileSystemChanges(self: *LspServer, writer: anytype) !void {
        if (self.file_watcher) |*watcher| {
            if (try watcher.checkForChanges(&self.file_index)) {
                // Revalidate all open documents
                var iterator = self.document_manager.open_documents.iterator();
                while (iterator.next()) |entry| {
                    const uri = entry.key_ptr.*;
                    try self.validateAndPublishDiagnostics(writer, uri);
                }
            }
        }
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

fn parseHoverParams(params: std.json.Value) !types.HoverParams {
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

    return types.HoverParams{
        .textDocument = types.TextDocumentIdentifier{
            .uri = uri,
        },
        .position = types.Position{
            .line = line,
            .character = character,
        },
    };
}

fn parseDidSaveParams(params: std.json.Value) !types.DidSaveTextDocumentParams {
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

    return types.DidSaveTextDocumentParams{
        .textDocument = types.TextDocumentIdentifier{
            .uri = uri,
        },
        .text = null, // We don't expect text in the save params for our use case
    };
}
