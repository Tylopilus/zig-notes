# Chunk 4: Intelligent Completion (Week 4)

## Goal
Autocomplete for productivity - `<C-x><C-o>` provides intelligent suggestions for tags and filenames.

## Success Criteria
- Parse tags (`#tag`, `#nested/tag`) from markdown content
- Build tag index mapping tags to files that contain them
- Implement `textDocument/completion` for tags and filenames
- Context-aware completion (tags vs filenames based on cursor position)

## Tasks
- [ ] Implement tag parsing for `#tag` and `#nested/tag` formats
- [ ] Create tag index data structure (tag → files mapping)
- [ ] Implement `textDocument/completion` LSP method
- [ ] Add context detection (inside wikilink vs tag context)
- [ ] Implement fuzzy matching for completion items
- [ ] Test completion in various contexts

## Technical Details

### Tag Parsing
```zig
const Tag = struct {
    name: []const u8,
    position: Position,
    range: Range,
};

fn parseTags(content: []const u8, allocator: Allocator) ![]Tag {
    var tags = ArrayList(Tag).init(allocator);
    
    // Parse #tag and #nested/tag patterns
    // Handle edge cases: #tag-with-dashes, #tag_with_underscores
    // Exclude tags in code blocks and inline code
    
    return tags.toOwnedSlice();
}
```

### Tag Index Structure
```zig
const TagIndex = struct {
    // Map tag name to list of files containing it
    tag_to_files: HashMap([]const u8, ArrayList([]const u8)),
    // Map file to list of tags it contains
    file_to_tags: HashMap([]const u8, ArrayList([]const u8)),
    
    fn addTag(self: *TagIndex, tag: []const u8, file_path: []const u8) !void {
        // Add bidirectional mapping
    }
    
    fn removeFile(self: *TagIndex, file_path: []const u8) !void {
        // Clean up all tags for removed file
    }
    
    fn getTagsStartingWith(self: *TagIndex, prefix: []const u8) ![][]const u8 {
        // Return tags matching prefix for completion
    }
};
```

### Completion Provider
```zig
const CompletionProvider = struct {
    file_index: *FileIndex,
    tag_index: *TagIndex,
    
    fn provideCompletion(self: *CompletionProvider, params: CompletionParams) !CompletionList {
        const context = try self.detectContext(params);
        
        return switch (context) {
            .wikilink => try self.completeFilenames(params),
            .tag => try self.completeTags(params),
            .none => CompletionList{ .items = &.{} },
        };
    }
    
    fn detectContext(self: *CompletionProvider, params: CompletionParams) !CompletionContext {
        // Analyze text around cursor to determine context
        // Check if inside [[...]] for wikilink completion
        // Check if after # for tag completion
    }
    
    fn completeFilenames(self: *CompletionProvider, params: CompletionParams) !CompletionList {
        const prefix = try self.extractPrefix(params);
        const matching_files = try self.file_index.getFilesStartingWith(prefix);
        
        var items = ArrayList(CompletionItem).init(allocator);
        for (matching_files) |file_path| {
            const filename = std.fs.path.stem(std.fs.path.basename(file_path));
            try items.append(CompletionItem{
                .label = filename,
                .kind = CompletionItemKind.File,
                .detail = file_path,
                .insertText = filename,
            });
        }
        
        return CompletionList{ .items = items.toOwnedSlice() };
    }
    
    fn completeTags(self: *CompletionProvider, params: CompletionParams) !CompletionList {
        const prefix = try self.extractTagPrefix(params);
        const matching_tags = try self.tag_index.getTagsStartingWith(prefix);
        
        var items = ArrayList(CompletionItem).init(allocator);
        for (matching_tags) |tag| {
            const file_count = self.tag_index.tag_to_files.get(tag).?.items.len;
            try items.append(CompletionItem{
                .label = tag,
                .kind = CompletionItemKind.Keyword,
                .detail = try std.fmt.allocPrint(allocator, "Used in {} files", .{file_count}),
                .insertText = tag,
            });
        }
        
        return CompletionList{ .items = items.toOwnedSlice() };
    }
};
```

### Context Detection
```zig
const CompletionContext = enum {
    wikilink,  // Inside [[...]]
    tag,       // After #
    none,      // No special context
};

fn detectCompletionContext(text: []const u8, position: usize) CompletionContext {
    // Look backwards from cursor position
    // Check for [[ without closing ]] → wikilink context
    // Check for # at word boundary → tag context
    // Handle edge cases like escaped characters
}
```

### Fuzzy Matching
```zig
fn fuzzyMatch(query: []const u8, target: []const u8) f32 {
    // Simple fuzzy matching algorithm
    // Score based on character matches and order
    // Higher score for exact prefix matches
    // Lower score for scattered character matches
}

fn sortCompletionItems(items: []CompletionItem, query: []const u8) void {
    // Sort by fuzzy match score descending
    // Exact matches first, then fuzzy matches
}
```

### Completion Triggers
- **Manual**: `<C-x><C-o>` in Neovim
- **Automatic**: After typing `[[` or `#`
- **Character triggers**: `[`, `#` configured in server capabilities

### Testing Scenarios
1. **Wikilink completion**: Type `[[te` → suggest `test-file`, `template`
2. **Tag completion**: Type `#pro` → suggest `#project`, `#programming`
3. **Nested tag completion**: Type `#work/` → suggest `#work/meeting`, `#work/todo`
4. **Fuzzy matching**: Type `#prg` → suggest `#programming`
5. **Context switching**: Different suggestions inside `[[]]` vs after `#`

### Performance Considerations
- **Incremental indexing**: Update tag index on document changes
- **Prefix trees**: Use trie data structure for fast prefix matching
- **Caching**: Cache completion results for repeated queries
- **Limits**: Cap completion results to prevent UI slowdown

### Error Handling
- Handle malformed completion requests gracefully
- Provide empty completion list on parsing errors
- Log completion errors for debugging
- Fallback to basic text completion on failures

## Integration Points

### From Chunk 3
- Use real-time document updates to maintain tag index
- Build on incremental parsing infrastructure
- Extend validation to include tag consistency

### For Chunk 5
- Tag index foundation for rename operations
- Completion infrastructure for rename suggestions
- Context detection foundation for smart refactoring

## Deliverable
Intelligent completion system where:
- `<C-x><C-o>` provides relevant suggestions based on context
- Wikilink completion suggests existing filenames
- Tag completion suggests existing tags with usage counts
- Fuzzy matching helps find items with partial typing
- Real-time updates keep suggestions current