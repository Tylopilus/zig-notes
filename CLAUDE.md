# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Zig-based Language Server Protocol (LSP) implementation for markdown note-taking and knowledge management. The server provides intelligent features like wikilink navigation, file completion, hover previews, and file indexing specifically designed for markdown workflows.

## Build and Development Commands

- `zig build` - Build the LSP server executable
- `zig build run` - Build and run the LSP server
- `zig build test` - Run all unit tests
- `zig test src/main.zig` - Run tests for a specific file
- `zig fmt .` - Format all Zig source files

## Architecture Overview

### Core Components

- **LSP Server** (`src/lsp/server.zig`): Main LSP implementation handling client communication
- **Protocol Layer** (`src/lsp/protocol.zig`): JSON-RPC message parsing and serialization
- **Document Manager** (`src/lsp/document_manager.zig`): Tracks open documents and their content
- **File Index** (`src/lsp/file_index.zig`): Maintains searchable index of markdown files
- **Markdown Discovery** (`src/markdown/discovery.zig`): Scans and discovers markdown files
- **Fuzzy Matching** (`src/lsp/fuzzy.zig`): Provides fuzzy search for file completion
- **Types** (`src/lsp/types.zig`): LSP protocol type definitions

### Key Features

- **Wikilink Support**: Navigate between files using `[[filename]]` syntax
- **File Completion**: Autocomplete file names within wikilinks
- **Hover Previews**: Display file content when hovering over wikilinks
- **Go-to-Definition**: Jump to target files from wikilinks
- **File Indexing**: Automatic discovery and indexing of markdown files

### Data Flow

1. Server discovers markdown files on initialization
2. Files are indexed for fast lookup and completion
3. Document manager tracks open files and their content
4. LSP protocol layer handles client requests (completion, hover, definition)
5. Fuzzy matching provides intelligent file suggestions

## Development Guidelines

From `AGENTS.md`:

### Code Style
- Use snake_case for variables, functions, and file names
- Use PascalCase for types, structs, and enums
- Use SCREAMING_SNAKE_CASE for constants
- Error handling: Use Zig's error unions (`!Type`) and handle errors explicitly
- Memory management: Prefer allocators, avoid global state
- Always use `defer` for resource cleanup
- Use `std.log` for debug/info/error messages

### Testing
- Place tests in the same file as the code being tested
- Use `test "description"` blocks
- Test files should end with `_test.zig` if separate from main code

## Project Structure

```
src/
├── main.zig              # Entry point and main server loop
├── lsp/                  # LSP implementation
│   ├── server.zig        # Core LSP server logic
│   ├── protocol.zig      # JSON-RPC protocol handling
│   ├── types.zig         # LSP type definitions
│   ├── document_manager.zig # Document lifecycle management
│   ├── file_index.zig    # File indexing and lookup
│   └── fuzzy.zig         # Fuzzy search implementation
├── markdown/             # Markdown-specific functionality
│   ├── discovery.zig     # File discovery and scanning
│   └── parser.zig        # Markdown parsing utilities
└── utils/
    └── allocator.zig     # Memory allocation utilities
```

## Key Implementation Details

- The server uses stdio for LSP communication
- Workspace is set to current directory on initialization
- File indexing happens during LSP initialization
- Completion is triggered by `[` and `#` characters
- Hover previews are limited to first 1KB of file content
- Fuzzy matching supports up to 20 results for completion