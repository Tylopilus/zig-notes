# Chunk 5: Refactoring Power (Week 5)

## Goal
Safe rename operations - `<leader>rn` safely renames tags and files across the entire workspace.

## Success Criteria
- Build comprehensive link graph tracking all file relationships
- Implement `textDocument/rename` for tags and filenames
- Handle cross-file reference updates atomically
- Provide rename preview and confirmation workflow

## Tasks
- [ ] Build comprehensive link graph (file → referenced files, file → referencing files)
- [ ] Implement `textDocument/rename` LSP method
- [ ] Add atomic multi-file edit operations
- [ ] Handle tag renaming across all files
- [ ] Handle filename renaming with link updates
- [ ] Add rename validation and conflict detection
- [ ] Test complex rename scenarios

## Technical Details

### Link Graph Structure
```zig
const LinkGraph = struct {
    // Forward links: file → files it references
    outgoing_links: HashMap([]const u8, HashSet([]const u8)),
    // Backward links: file → files that reference it
    incoming_links: HashMap([]const u8, HashSet([]const u8)),
    // Tag usage: tag → files that use it
    tag_usage: HashMap([]const u8, HashSet([]const u8)),
    // File tags: file → tags it contains
    file_tags: HashMap([]const u8, HashSet([]const u8)),
    
    fn addLink(self: *LinkGraph, from_file: []const u8, to_file: []const u8) !void {
        // Add bidirectional link relationship
    }
    
    fn addTagUsage(self: *LinkGraph, file: []const u8, tag: []const u8) !void {
        // Track tag usage in file
    }
    
    fn getFilesReferencingTag(self: *LinkGraph, tag: []const u8) [][]const u8 {
        // Return all files that use a specific tag
    }
    
    fn getFilesReferencingFile(self: *LinkGraph, file_path: []const u8) [][]const u8 {
        // Return all files that link to a specific file
    }
};
```

### Rename Provider
```zig
const RenameProvider = struct {
    link_graph: *LinkGraph,
    file_index: *FileIndex,
    tag_index: *TagIndex,
    document_manager: *DocumentManager,
    
    fn prepareRename(self: *RenameProvider, params: PrepareRenameParams) !?PrepareRenameResult {
        const context = try self.detectRenameContext(params);
        
        return switch (context) {
            .tag => |tag| PrepareRenameResult{
                .range = tag.range,
                .placeholder = tag.name,
            },
            .filename => |file| PrepareRenameResult{
                .range = file.range,
                .placeholder = file.name,
            },
            .none => null,
        };
    }
    
    fn rename(self: *RenameProvider, params: RenameParams) !?WorkspaceEdit {
        const context = try self.detectRenameContext(params);
        
        return switch (context) {
            .tag => |tag| try self.renameTag(tag.name, params.newName),
            .filename => |file| try self.renameFile(file.path, params.newName),
            .none => null,
        };
    }
    
    fn renameTag(self: *RenameProvider, old_tag: []const u8, new_tag: []const u8) !WorkspaceEdit {
        const affected_files = self.link_graph.getFilesReferencingTag(old_tag);
        var changes = HashMap([]const u8, []TextEdit).init(allocator);
        
        for (affected_files) |file_path| {
            const edits = try self.generateTagRenameEdits(file_path, old_tag, new_tag);
            try changes.put(file_path, edits);
        }
        
        return WorkspaceEdit{
            .changes = changes,
        };
    }
    
    fn renameFile(self: *RenameProvider, old_path: []const u8, new_name: []const u8) !WorkspaceEdit {
        const old_filename = std.fs.path.stem(std.fs.path.basename(old_path));
        const referencing_files = self.link_graph.getFilesReferencingFile(old_path);
        
        var changes = HashMap([]const u8, []TextEdit).init(allocator);
        
        // Update all wikilinks pointing to this file
        for (referencing_files) |file_path| {
            const edits = try self.generateFilenameRenameEdits(file_path, old_filename, new_name);
            try changes.put(file_path, edits);
        }
        
        // Add file rename operation
        var resource_operations = ArrayList(ResourceOperation).init(allocator);
        try resource_operations.append(ResourceOperation{
            .kind = "rename",
            .oldUri = try pathToUri(old_path),
            .newUri = try pathToUri(try buildNewPath(old_path, new_name)),
        });
        
        return WorkspaceEdit{
            .changes = changes,
            .documentChanges = resource_operations.toOwnedSlice(),
        };
    }
};
```

### Rename Context Detection
```zig
const RenameContext = union(enum) {
    tag: struct {
        name: []const u8,
        range: Range,
    },
    filename: struct {
        name: []const u8,
        path: []const u8,
        range: Range,
    },
    none,
};

fn detectRenameContext(params: RenameParams) !RenameContext {
    const document = try getDocument(params.textDocument.uri);
    const position = params.position;
    
    // Check if cursor is on a tag
    if (try findTagAtPosition(document.content, position)) |tag| {
        return RenameContext{ .tag = tag };
    }
    
    // Check if cursor is on a wikilink
    if (try findWikilinkAtPosition(document.content, position)) |wikilink| {
        const file_path = try resolveWikilink(wikilink.target);
        return RenameContext{ 
            .filename = .{
                .name = wikilink.target,
                .path = file_path,
                .range = wikilink.range,
            }
        };
    }
    
    return RenameContext.none;
}
```

### Atomic Multi-File Operations
```zig
const WorkspaceEdit = struct {
    changes: ?HashMap([]const u8, []TextEdit),
    documentChanges: ?[]ResourceOperation,
    
    fn validate(self: *WorkspaceEdit) ![]RenameError {
        // Check for conflicts and validation errors
        // Ensure all target files exist
        // Check for circular references
        // Validate new names
    }
    
    fn preview(self: *WorkspaceEdit) !RenamePreview {
        // Generate preview of all changes
        // Show affected files and change counts
        // Highlight potential conflicts
    }
};
```

### Rename Validation
```zig
const RenameValidator = struct {
    fn validateTagRename(old_tag: []const u8, new_tag: []const u8) ![]ValidationError {
        var errors = ArrayList(ValidationError).init(allocator);
        
        // Check tag name format
        if (!isValidTagName(new_tag)) {
            try errors.append(ValidationError{
                .message = "Invalid tag name format",
                .severity = .error,
            });
        }
        
        // Check for conflicts with existing tags
        if (tagExists(new_tag) and !std.mem.eql(u8, old_tag, new_tag)) {
            try errors.append(ValidationError{
                .message = "Tag already exists",
                .severity = .warning,
            });
        }
        
        return errors.toOwnedSlice();
    }
    
    fn validateFileRename(old_path: []const u8, new_name: []const u8) ![]ValidationError {
        var errors = ArrayList(ValidationError).init(allocator);
        
        // Check filename format
        if (!isValidFilename(new_name)) {
            try errors.append(ValidationError{
                .message = "Invalid filename format",
                .severity = .error,
            });
        }
        
        // Check for file conflicts
        const new_path = try buildNewPath(old_path, new_name);
        if (std.fs.cwd().access(new_path, .{})) |_| {
            try errors.append(ValidationError{
                .message = "File already exists",
                .severity = .error,
            });
        } else |_| {}
        
        return errors.toOwnedSlice();
    }
};
```

### Testing Scenarios
1. **Tag rename**: `#project` → `#work` across 10 files
2. **File rename**: `meeting-notes.md` → `standup-notes.md` with 5 references
3. **Nested tag rename**: `#work/meeting` → `#work/standup`
4. **Conflict detection**: Rename to existing tag/file name
5. **Complex dependencies**: File A → File B → File C rename chain
6. **Partial failures**: Handle cases where some files can't be updated

### Performance Considerations
- **Batch operations**: Group related edits together
- **Incremental updates**: Only update affected parts of link graph
- **Progress reporting**: Show progress for large rename operations
- **Cancellation**: Allow users to cancel long-running renames

### Error Handling
- **Validation errors**: Prevent invalid renames before execution
- **Partial failures**: Handle cases where some files can't be updated
- **Rollback**: Ability to undo rename operations
- **Conflict resolution**: Handle merge conflicts gracefully

## Integration Points

### From Chunk 4
- Use tag index for comprehensive tag rename operations
- Build on completion infrastructure for rename suggestions
- Extend context detection for rename scenarios

### Future Extensions
- **Undo/Redo**: Track rename operations for reversal
- **Batch renames**: Rename multiple items simultaneously
- **Smart suggestions**: Suggest better names based on content
- **Refactoring patterns**: Common rename patterns and templates

## Deliverable
Powerful rename system where:
- `<leader>rn` on tags renames across all files safely
- `<leader>rn` on wikilinks renames target files and updates all references
- Validation prevents conflicts and invalid operations
- Atomic operations ensure consistency across workspace
- Preview shows all changes before execution