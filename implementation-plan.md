# Zig-Powered Neovim Markdown Assistant - Implementation Plan

## Architecture Overview

This project implements a **true LSP server** in Zig that provides native Neovim integration for markdown files with powerful refactoring capabilities. The LSP-first approach enables native features like rename refactoring for tags and links while maintaining specialized markdown functionality.

## Key LSP Benefits

- **Native Rename**: `<leader>rn` to rename tags across all files safely
- **Go-to-Definition**: `gd` on wikilinks to jump to files  
- **Hover Previews**: `K` to preview linked content and backlinks
- **Completion**: `<C-x><C-o>` for intelligent tag/file suggestions
- **Diagnostics**: Broken links shown as errors in gutter
- **References**: `gr` to find all uses of a tag or file
- **Document Symbols**: Headers and tags for outline/navigation

## Implementation Phases

### Phase 1: LSP Foundation (High Priority)
1. **Project Setup**: Basic Zig structure with build.zig
2. **LSP Server Foundation**: Initialize, shutdown, and lifecycle management
3. **Core Data Structures**: FileIndex, ContentIndex, LinkGraph, TagIndex optimized for LSP operations
4. **LSP Text Synchronization**: Handle document open/close/change events
5. **Markdown Parser**: Parse headers, tags, wikilinks, standard links, frontmatter
6. **Workspace Indexing**: File discovery and initial indexing

### Phase 2: Core LSP Features (High Priority)
7. **Go-to-Definition**: Navigate wikilinks `[[filename]]` and references
8. **Completion**: Autocomplete tags, file names, link targets
9. **Rename Refactoring**: Rename tags/files across entire workspace safely

### Phase 3: Advanced LSP Features (Medium Priority)
10. **Hover**: Preview linked files, show backlinks and metadata
11. **Diagnostics**: Real-time broken link detection and reporting
12. **Find References**: Locate all uses of tags, files, or links
13. **Document Symbols**: Headers and tags for outline/navigation
14. **File Watching**: Real-time updates via LSP workspace events
15. **Custom Commands**: Advanced search, backlink analysis, orphan detection

### Phase 4: Polish (Low-Medium Priority)
16. **Configuration**: TOML-based settings
17. **Error Handling**: Robust error management and logging
18. **Performance**: Meet sub-50ms response requirements
19. **Testing**: Comprehensive LSP feature testing
20. **Documentation**: Setup guides and API documentation

## Detailed Task List

### High Priority Tasks
- [ ] Set up basic Zig project structure with build.zig
- [ ] Implement LSP server foundation (initialize, shutdown, lifecycle)
- [ ] Implement core data structures (FileIndex, ContentIndex, LinkGraph, TagIndex)
- [ ] Implement LSP text document synchronization
- [ ] Create markdown parser for headers, tags, links, frontmatter
- [ ] Implement file discovery and workspace indexing
- [ ] Implement LSP textDocument/definition for wikilinks and references
- [ ] Implement LSP textDocument/completion for tags and file references
- [ ] Implement LSP textDocument/rename for tags and file references

### Medium Priority Tasks
- [ ] Implement LSP textDocument/hover for link previews and backlinks
- [ ] Implement LSP textDocument/publishDiagnostics for broken links
- [ ] Implement LSP textDocument/references to find all tag/file references
- [ ] Implement LSP textDocument/documentSymbol for headers and tags
- [ ] Implement file system monitoring with LSP workspace/didChangeWatchedFiles
- [ ] Implement custom LSP commands for advanced search and analysis
- [ ] Implement TOML configuration system
- [ ] Add comprehensive error handling and logging

### Low Priority Tasks
- [ ] Optimize for performance requirements (sub-50ms operations)
- [ ] Create comprehensive test suite for LSP features
- [ ] Write LSP server documentation and Neovim setup guide

## Technical Specifications

### LSP Features Implementation

#### Core LSP Methods
- `initialize` - Server capabilities and workspace setup
- `textDocument/didOpen` - Track opened markdown files
- `textDocument/didChange` - Incremental content updates
- `textDocument/didClose` - Clean up file resources
- `textDocument/definition` - Navigate to wikilink targets
- `textDocument/completion` - Tag and file autocomplete
- `textDocument/rename` - Safe refactoring across workspace
- `textDocument/hover` - Link previews and backlinks
- `textDocument/publishDiagnostics` - Broken link errors
- `textDocument/references` - Find all tag/file uses
- `textDocument/documentSymbol` - Headers and tags outline
- `workspace/didChangeWatchedFiles` - File system monitoring

#### Custom LSP Commands
- `markdown/search` - Full-text search across workspace
- `markdown/backlinks` - Generate backlink maps
- `markdown/orphans` - Find orphaned files
- `markdown/tagAnalysis` - Tag usage statistics
- `markdown/templateExpansion` - Note template system

### Data Structures

```zig
// File metadata and content index
const FileIndex = HashMap([]const u8, FileMetadata);
const ContentIndex = InvertedIndex; // For full-text search
const LinkGraph = AdjacencyList; // File relationships
const TagIndex = HashMap([]const u8, ArrayList([]const u8)); // Tag to files mapping
```

### Markdown Elements Support
- **Wikilinks**: `[[filename]]`, `[[filename|alias]]`, `[[filename#section]]`
- **Standard Links**: `[text](path)`, `[text](path "title")`
- **Tags**: `#tag`, `#nested/tag`
- **Headers**: `# Header`, `## Subheader`
- **Frontmatter**: YAML, TOML, JSON metadata blocks
- **Code Blocks**: Language-specific indexing

### Performance Requirements
- Index 10,000 markdown files in under 5 seconds (cold start)
- LSP response time under 50ms for typical operations
- File change detection and re-indexing under 100ms
- Memory usage under 100MB for 10,000 files
- CPU usage under 5% during idle monitoring

### Configuration Format
```toml
[general]
markdown_dirs = ["/path/to/notes", "/path/to/docs"]
ignore_patterns = ["*.tmp", ".git/**"]
max_file_size = "10MB"

[lsp]
hover_preview_lines = 10
completion_max_items = 50
diagnostics_enabled = true

[search]
fuzzy_threshold = 0.6
max_results = 100
enable_regex = true
```

## Success Criteria
1. **Native LSP Integration**: Seamless rename, go-to-definition, hover, completion
2. **Performance**: Sub-50ms LSP responses across 1000+ markdown files
3. **Reliability**: 24/7 operation without memory leaks or crashes
4. **Workflow**: Zero-friction markdown editing with intelligent assistance
5. **Learning**: Practical Zig experience across LSP, parsing, and indexing domains

## Risk Assessment
- **High**: Zig LSP ecosystem maturity and JSON-RPC implementation
- **Medium**: Cross-platform file watching and Unicode handling
- **Low**: Basic markdown parsing and Neovim LSP client integration

## Dependencies
- **Zig**: Latest stable release (0.11+)
- **Neovim**: 0.8+ with built-in LSP client
- **External Libraries**: Minimal, prefer Zig standard library
- **Development Tools**: Zig Language Server, testing framework

This LSP-first architecture provides the powerful refactoring capabilities requested while maintaining all specialized markdown features from the original requirements.