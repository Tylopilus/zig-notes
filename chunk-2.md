# Chunk 2: Core Navigation (Week 2)

## Goal
Basic wikilink navigation working - users can press `gd` on wikilinks to jump to files.

## Success Criteria
- Parse wikilinks `[[filename]]` from markdown content
- Build basic file index mapping filenames to paths
- Implement `textDocument/definition` for wikilink navigation
- Handle file opening/tracking via `textDocument/didOpen`

## Tasks
- [ ] Implement basic markdown parser for wikilinks
- [ ] Create file index data structure (filename → path mapping)
- [ ] Implement `textDocument/definition` LSP method
- [ ] Handle `textDocument/didOpen` to track opened files
- [ ] Add wikilink resolution logic (handle extensions, case sensitivity)
- [ ] Test navigation with real markdown files

## Technical Details

### Wikilink Parsing
```zig
// Simple regex-based approach initially
const WikiLink = struct {
    target: []const u8,
    alias: ?[]const u8,
    position: Position,
};

fn parseWikilinks(content: []const u8, allocator: Allocator) ![]WikiLink {
    // Parse [[filename]] and [[filename|alias]] patterns
    // Return array of WikiLink structs with positions
}
```

### File Index Structure
```zig
const FileIndex = struct {
    // Map filename (without extension) to full path
    name_to_path: HashMap([]const u8, []const u8),
    // Map full path to file metadata
    path_to_metadata: HashMap([]const u8, FileMetadata),
    
    fn addFile(self: *FileIndex, path: []const u8) !void {
        // Extract filename, add to both maps
    }
    
    fn resolveWikilink(self: *FileIndex, target: []const u8) ?[]const u8 {
        // Find file path for wikilink target
        // Handle case insensitivity, missing extensions
    }
};
```

### LSP Definition Provider
```zig
fn handleDefinition(request: DefinitionRequest) !DefinitionResponse {
    // 1. Get document content at cursor position
    // 2. Check if cursor is on a wikilink
    // 3. Extract wikilink target
    // 4. Resolve target to file path using FileIndex
    // 5. Return Location with file URI and position
}
```

### Document Tracking
```zig
const DocumentManager = struct {
    open_documents: HashMap([]const u8, Document),
    
    fn didOpen(self: *DocumentManager, params: DidOpenParams) !void {
        // Store document content and version
        // Parse wikilinks in document
        // Update file index if needed
    }
};
```

### Wikilink Resolution Rules
1. **Exact match**: `[[filename]]` → `filename.md`
2. **Case insensitive**: `[[FileName]]` → `filename.md`
3. **With extension**: `[[file.md]]` → `file.md`
4. **Without extension**: `[[file]]` → `file.md`
5. **Subdirectories**: `[[folder/file]]` → `folder/file.md`

### Testing Scenarios
1. Basic wikilink: `[[test-file]]` → jump to `test-file.md`
2. With alias: `[[test-file|Test File]]` → jump to `test-file.md`
3. Case variations: `[[Test-File]]` → jump to `test-file.md`
4. Missing file: `[[nonexistent]]` → no definition found
5. Subdirectory: `[[notes/important]]` → jump to `notes/important.md`

### Error Handling
- Graceful handling of malformed wikilinks
- Return empty response for unresolvable links
- Log parsing errors without crashing server

## Integration Points

### From Chunk 1
- Use existing JSON-RPC infrastructure
- Extend file discovery to build filename index
- Add definition handling to LSP server

### For Chunk 3
- Document tracking foundation for real-time updates
- Wikilink parsing foundation for link validation
- File index foundation for broken link detection

## Deliverable
Working wikilink navigation where:
- `gd` on `[[filename]]` jumps to the target file
- Works with various filename formats and cases
- Handles missing files gracefully
- Provides foundation for more advanced features