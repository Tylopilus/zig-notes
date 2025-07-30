# Chunk 3: Real-time Updates (Week 3)

## Goal
Live editing without restarts - broken links show as errors in real-time as you type.

## Success Criteria
- Handle incremental document changes via `textDocument/didChange`
- Validate links in real-time and detect broken references
- Show broken links as diagnostics in Neovim gutter
- Update file index when files are created/deleted/renamed

## Tasks
- [ ] Implement `textDocument/didChange` for incremental updates
- [ ] Add link validation logic to detect broken wikilinks
- [ ] Implement `textDocument/publishDiagnostics` for error reporting
- [ ] Add basic file system monitoring for workspace changes
- [ ] Update file index when files change
- [ ] Test real-time error detection and clearing

## Technical Details

### Incremental Document Updates
```zig
const DocumentManager = struct {
    open_documents: HashMap([]const u8, Document),
    
    fn didChange(self: *DocumentManager, params: DidChangeParams) !void {
        // Apply incremental changes to document
        // Re-parse wikilinks in changed regions
        // Validate links and publish diagnostics
        // Update any affected indexes
    }
    
    fn applyChanges(document: *Document, changes: []TextDocumentContentChangeEvent) !void {
        // Handle full document replacement or incremental changes
        // Update document version number
    }
};
```

### Link Validation
```zig
const LinkValidator = struct {
    file_index: *FileIndex,
    
    fn validateDocument(self: *LinkValidator, uri: []const u8, content: []const u8) ![]Diagnostic {
        var diagnostics = ArrayList(Diagnostic).init(allocator);
        
        const wikilinks = try parseWikilinks(content, allocator);
        for (wikilinks) |link| {
            if (self.file_index.resolveWikilink(link.target) == null) {
                try diagnostics.append(createBrokenLinkDiagnostic(link));
            }
        }
        
        return diagnostics.toOwnedSlice();
    }
    
    fn createBrokenLinkDiagnostic(link: WikiLink) Diagnostic {
        return Diagnostic{
            .range = link.range,
            .severity = DiagnosticSeverity.Error,
            .message = "Broken wikilink: target file not found",
            .source = "zig-markdown",
        };
    }
};
```

### Diagnostic Publishing
```zig
fn publishDiagnostics(server: *LSPServer, uri: []const u8, diagnostics: []Diagnostic) !void {
    const params = PublishDiagnosticsParams{
        .uri = uri,
        .diagnostics = diagnostics,
    };
    
    const notification = LSPNotification{
        .method = "textDocument/publishDiagnostics",
        .params = params,
    };
    
    try server.sendNotification(notification);
}
```

### File System Monitoring
```zig
const FileWatcher = struct {
    file_index: *FileIndex,
    validator: *LinkValidator,
    server: *LSPServer,
    
    fn watchWorkspace(self: *FileWatcher, workspace_path: []const u8) !void {
        // Basic polling approach initially (can optimize later)
        // Watch for .md file creation, deletion, modification
        // Update file index and re-validate affected documents
    }
    
    fn handleFileCreated(self: *FileWatcher, path: []const u8) !void {
        try self.file_index.addFile(path);
        try self.revalidateAllDocuments();
    }
    
    fn handleFileDeleted(self: *FileWatcher, path: []const u8) !void {
        try self.file_index.removeFile(path);
        try self.revalidateAllDocuments();
    }
};
```

### Real-time Validation Flow
1. **Document Change**: User types in Neovim
2. **LSP Notification**: `textDocument/didChange` sent to server
3. **Content Update**: Apply changes to document content
4. **Link Parsing**: Re-parse wikilinks in changed regions
5. **Validation**: Check if wikilink targets exist
6. **Diagnostics**: Send broken link errors to Neovim
7. **Display**: Errors appear in gutter and error list

### Optimization Strategies
- **Incremental Parsing**: Only re-parse changed text regions
- **Debouncing**: Wait for typing pause before validation
- **Caching**: Cache validation results for unchanged links
- **Batch Updates**: Group multiple changes before validation

### Testing Scenarios
1. **Type broken link**: `[[nonexistent]]` → immediate error
2. **Fix broken link**: `[[nonexistent]]` → `[[existing]]` → error clears
3. **Create target file**: Error disappears when target file created
4. **Delete target file**: Error appears when target file deleted
5. **Rename file**: Update all references automatically

### Error Handling
- Handle malformed change events gracefully
- Recover from parsing errors without losing state
- Provide meaningful error messages for different failure types
- Log validation errors for debugging

## Integration Points

### From Chunk 2
- Use existing wikilink parsing logic
- Extend file index with validation capabilities
- Build on document tracking foundation

### For Chunk 4
- Document change handling foundation for completion
- Link validation foundation for intelligent suggestions
- Real-time parsing foundation for tag completion

## Deliverable
Real-time link validation where:
- Broken wikilinks show as red squiggles immediately
- Errors clear when links are fixed or target files created
- File system changes update validation in real-time
- No need to restart LSP server for changes to take effect