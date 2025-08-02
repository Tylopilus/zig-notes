# Chunk 4: Intelligent Completion (Week 4)

## Goal
Autocomplete for productivity - `<C-x><C-o>` provides intelligent suggestions for tags (from frontmatter) and filenames.

## Success Criteria
- Parse tags from YAML frontmatter (e.g., `tags: [project, work]`)
- Build tag index mapping tags to files that contain them
- Implement `textDocument/completion` for tags and filenames
- Context-aware completion (tags vs filenames based on cursor position)

## Tasks
- [x] Implement tag parsing from frontmatter
- [x] Create tag index data structure (tag → files mapping)
- [x] Implement `textDocument/completion` LSP method
- [x] Add context detection (inside wikilink vs frontmatter tag context)
- [x] Implement fuzzy matching for completion items
- [x] Test completion in various contexts

## Technical Details

### Tag Parsing (Frontmatter)
```zig
const Frontmatter = struct {
    tags: []const []const u8,
    // ... other fields
};

fn parseFrontmatter(content: []const u8) !?Frontmatter {
    // ... logic to parse YAML frontmatter
    // Extracts tags from a line like:
    // tags: [project, work/meeting, development]
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
            .frontmatter_tag => try self.completeTags(params),
            .none => CompletionList{ .items = &.{} },
        };
    }
    
    fn detectContext(self: *CompletionProvider, params: CompletionParams) !CompletionContext {
        // Analyze text around cursor to determine context
        // Check if inside [[...]] for wikilink completion
        // Check if inside `tags: [...]` in frontmatter for tag completion
    }
    
    fn completeFilenames(self: *CompletionProvider, params: CompletionParams) !CompletionList {
        // ... (implementation for filename completion)
    }
    
    fn completeTags(self: *CompletionProvider, params: CompletionParams) !CompletionList {
        // ... (implementation for tag completion)
    }
};
```

### Context Detection
```zig
const CompletionContext = enum {
    wikilink,        // Inside [[...]]
    frontmatter_tag, // Inside `tags: [...]` in YAML frontmatter
    none,            // No special context
};

fn detectCompletionContext(text: []const u8, position: usize) CompletionContext {
    // Look backwards from cursor position
    // Check for [[ without closing ]] → wikilink context
    // Check for `tags:` and surrounding `[]` → frontmatter_tag context
}
```

### Fuzzy Matching
```zig
fn fuzzyMatch(query: []const u8, target: []const u8) f32 {
    // ... (fuzzy matching logic)
}

fn sortCompletionItems(items: []CompletionItem, query: []const u8) void {
    // ... (sorting logic)
}
```

### Completion Triggers
- **Manual**: `<C-x><C-o>` in Neovim
- **Automatic**: After typing `[[` or `,` inside the frontmatter tag list.
- **Character triggers**: `[`, `,` configured in server capabilities

### Testing Scenarios
1. **Wikilink completion**: Type `[[te` → suggest `test-file`, `template`
2. **Frontmatter Tag completion**: In `tags: [pr]`, type `pr` → suggest `project`, `programming`
3. **Nested tag completion**: In `tags: [work/]`, type `work/` → suggest `work/meeting`, `work/todo`
4. **Fuzzy matching**: In `tags: [prg]`, type `prg` → suggest `programming`
5. **Context switching**: Different suggestions inside `[[]]` vs inside `tags: []`

### Performance Considerations
- **Incremental indexing**: Update tag index on document changes
- **Caching**: Cache completion results for repeated queries
- **Limits**: Cap completion results to prevent UI slowdown

### Error Handling
- Handle malformed completion requests gracefully
- Provide empty completion list on parsing errors
- Log completion errors for debugging

## Integration Points

### From Chunk 3
- Use real-time document updates to maintain tag index
- Build on incremental parsing infrastructure

### For Chunk 5
- Tag index foundation for rename operations
- Completion infrastructure for rename suggestions

## Deliverable
Intelligent completion system where:
- `<C-x><C-o>` provides relevant suggestions based on context
- Wikilink completion suggests existing filenames
- Frontmatter tag completion suggests existing tags with usage counts
- Fuzzy matching helps find items with partial typing
- Real-time updates keep suggestions current
