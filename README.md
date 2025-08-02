# Zig Notes LSP

A Language Server Protocol (LSP) implementation for markdown note-taking and knowledge management, built with Zig. Designed to provide intelligent features for markdown files with YAML frontmatter metadata and wikilink navigation.

## Features

### 🔗 **Wikilink Navigation**
- **Go-to-Definition**: Jump to target files using `[[filename]]` syntax
- **Hover Previews**: Display file content when hovering over wikilinks
- **File Completion**: Autocomplete file names within wikilinks with fuzzy matching

### 🏷️ **Tag Management**
- **YAML Frontmatter**: Supports standard frontmatter metadata
- **Tag Completion**: Intelligent tag suggestions within frontmatter arrays
- **Tag Indexing**: Real-time tag indexing across all markdown files
- **Usage Tracking**: Shows tag usage counts ("Used in N files")

### 📝 **Document Management**
- **Real-time Updates**: Maintains indexes as documents change
- **Link Validation**: Validates wikilinks and reports broken links
- **File Watching**: Automatically updates when files are added/removed
- **Diagnostics**: Reports issues with links and references

### ⚡ **Performance**
- **Fuzzy Matching**: Fast fuzzy search for files and tags
- **Incremental Updates**: Efficient real-time indexing
- **Memory Efficient**: Built with Zig for optimal performance

## Installation

### Prerequisites
- [Zig](https://ziglang.org/) 0.14.0 or later
- An LSP-compatible editor (Neovim, VSCode, Emacs, etc.)

### Building from Source

```bash
git clone <repository-url>
cd zig-notes
zig build
```

The LSP server will be built to `zig-out/bin/zig-notes-lsp`.

### Running Tests

```bash
zig build test
```

## Usage

### Markdown File Structure

Zig Notes LSP works with markdown files that use YAML frontmatter for metadata:

```markdown
---
title: "My Project Notes"
tags: [project, development, backend/api]
date: 2024-08-02
author: "Your Name"
---

# My Project Notes

This is the main content of your note.

You can link to other files using [[other-file]] syntax.

## Features

- Regular markdown content
- Wikilinks for navigation
- No confusion with # headlines
```

### Supported Frontmatter Fields

- `title`: Note title (string)
- `tags`: Array of tags (e.g., `[tag1, nested/tag2, tag3]`)
- `date`: Note date (string)
- `author`: Author name (string)

### Editor Configuration

#### Neovim (with nvim-lspconfig)

```lua
local lspconfig = require('lspconfig')

-- Add zig-notes-lsp configuration
local configs = require('lspconfig.configs')
if not configs.zig_notes then
  configs.zig_notes = {
    default_config = {
      cmd = { '/path/to/zig-notes/zig-out/bin/zig-notes-lsp' },
      filetypes = { 'markdown' },
      root_dir = lspconfig.util.root_pattern('.git', '.'),
      settings = {},
    },
  }
end

-- Enable the LSP
lspconfig.zig_notes.setup({
  on_attach = function(client, bufnr)
    -- Configure keybindings
    local opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', '<C-Space>', vim.lsp.buf.completion, opts)
  end,
})
```

#### VSCode

Create a VSCode extension or use a generic LSP client with the following configuration:

```json
{
  "languageServer": {
    "command": "/path/to/zig-notes/zig-out/bin/zig-notes-lsp",
    "args": [],
    "filetypes": ["markdown"]
  }
}
```

## Features in Detail

### Wikilink Completion

When typing `[[`, the LSP provides intelligent file suggestions:

```markdown
[[test-fi|]]  → suggests "test-file.md", "test-fixtures.md", etc.
```

- Fuzzy matching for partial filenames
- Excludes current file from suggestions
- Shows full file paths in completion details

### Tag Completion

When editing the tags array in frontmatter, get intelligent tag suggestions:

```yaml
tags: [project, wo|]  → suggests "work/meeting", "work/todo", etc.
```

- Fuzzy matching for tag names
- Shows usage counts for each tag
- Supports nested tags with `/` separator

### Link Validation

The LSP validates wikilinks and provides diagnostics for:

- Broken links (file not found)
- Invalid link syntax
- Missing file extensions

### Go-to-Definition

Press `gd` (or your editor's go-to-definition key) on a wikilink to jump to the target file.

### Hover Previews

Hover over a wikilink to see a preview of the target file's content (first 1KB).

## Architecture

```
src/
├── main.zig                    # Entry point and main server loop
├── lsp/                        # LSP implementation
│   ├── server.zig             # Core LSP server logic
│   ├── protocol.zig           # JSON-RPC protocol handling
│   ├── types.zig              # LSP type definitions
│   ├── document_manager.zig   # Document lifecycle management
│   ├── file_index.zig         # File indexing and lookup
│   ├── tag_index.zig          # Tag indexing and management
│   ├── fuzzy.zig              # Fuzzy search implementation
│   ├── link_validator.zig     # Link validation
│   └── file_watcher.zig       # File system monitoring
├── markdown/                   # Markdown-specific functionality
│   ├── discovery.zig          # File discovery and scanning
│   ├── parser.zig             # Markdown parsing utilities
│   ├── frontmatter.zig        # YAML frontmatter parsing
│   └── tag_parser.zig         # Tag extraction from frontmatter
└── utils/
    └── allocator.zig          # Memory allocation utilities
```

## LSP Capabilities

The server implements the following LSP features:

- **textDocument/completion**: File and tag completion
- **textDocument/hover**: Hover information for wikilinks
- **textDocument/definition**: Go-to-definition for wikilinks
- **textDocument/publishDiagnostics**: Link validation diagnostics
- **textDocument/didOpen/didChange/didSave**: Document synchronization

## Configuration

The LSP server supports the following trigger characters:

- `[` - Triggers wikilink completion
- `,` - Triggers tag completion in frontmatter arrays

## Development

### Code Style

- Use `snake_case` for variables, functions, and file names
- Use `PascalCase` for types, structs, and enums
- Use `SCREAMING_SNAKE_CASE` for constants
- Use Zig's error unions (`!Type`) and handle errors explicitly
- Prefer allocators over global state
- Always use `defer` for resource cleanup

### Testing

Tests are co-located with the code they test. Run the full test suite:

```bash
zig build test
```

### Memory Management

The LSP uses explicit memory management with allocators. All allocated memory is properly freed using `defer` statements and explicit cleanup functions.

## Performance Considerations

- **Incremental Indexing**: Only re-indexes changed files
- **Fuzzy Matching**: Optimized algorithms for fast completion
- **Memory Efficient**: Careful memory management prevents leaks
- **Caching**: Results are cached where appropriate
- **Limits**: Completion results are limited to prevent UI slowdown

## Troubleshooting

### Common Issues

1. **LSP not starting**: Check that the binary path is correct and executable
2. **No completions**: Ensure files have proper frontmatter format
3. **Broken links not detected**: Check that file extensions match exactly
4. **Performance issues**: Large repositories may take time to index initially

### Debugging

Enable LSP logging in your editor to see detailed information about requests and responses.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass: `zig build test`
6. Submit a pull request

## License

[Specify your license here]

## Acknowledgments

Built with [Zig](https://ziglang.org/) for performance and memory safety.
Inspired by modern note-taking tools and knowledge management systems.
