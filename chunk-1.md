# Chunk 1: Minimal Viable LSP (Week 1)

## Goal
Get basic LSP server responding to Neovim without crashing.

## Success Criteria
- LSP server that Neovim can connect to
- Handles basic LSP lifecycle (initialize/shutdown)
- Can discover markdown files in workspace
- Responds to LSP requests without errors

## Tasks
- [ ] Set up basic Zig project structure with `build.zig`
- [ ] Implement minimal JSON-RPC message parsing
- [ ] Handle LSP `initialize` request with server capabilities
- [ ] Handle LSP `shutdown` and `exit` requests
- [ ] Implement basic file discovery (scan markdown files in directory)
- [ ] Create stub responses for core LSP methods to prevent crashes
- [ ] Test LSP server connection with Neovim

## Technical Details

### Project Structure
```
src/
├── main.zig           # Entry point and LSP server loop
├── lsp/
│   ├── server.zig     # LSP server implementation
│   ├── protocol.zig   # JSON-RPC protocol handling
│   └── types.zig      # LSP type definitions
├── markdown/
│   └── discovery.zig  # File discovery utilities
└── utils/
    └── allocator.zig  # Memory management utilities
```

### Core Components
1. **JSON-RPC Handler**: Parse incoming LSP messages from stdin
2. **LSP Server**: Handle initialize, shutdown, and basic lifecycle
3. **File Discovery**: Recursively find `.md` files in workspace
4. **Response Builder**: Create valid LSP responses

### LSP Methods to Implement
- `initialize` - Return server capabilities
- `initialized` - Acknowledge initialization complete
- `shutdown` - Prepare for server shutdown
- `exit` - Terminate server process
- `textDocument/didOpen` - Stub implementation
- `textDocument/didClose` - Stub implementation
- `textDocument/didChange` - Stub implementation

### Server Capabilities to Advertise
```json
{
  "capabilities": {
    "textDocumentSync": 1,
    "definitionProvider": true,
    "completionProvider": {
      "triggerCharacters": ["[", "#"]
    },
    "renameProvider": true,
    "hoverProvider": true,
    "referencesProvider": true,
    "documentSymbolProvider": true,
    "diagnosticProvider": true
  }
}
```

### Testing Approach
1. Manual testing with Neovim LSP client
2. Use `:LspInfo` to verify connection
3. Check `:LspLog` for errors
4. Verify server doesn't crash on basic operations

### Neovim Configuration
```lua
-- Add to init.lua for testing
vim.lsp.start({
  name = 'zig-markdown',
  cmd = {'zig', 'run', 'src/main.zig'},
  root_dir = vim.fn.getcwd(),
  filetypes = {'markdown'},
})
```

## Deliverable
A basic LSP server that:
- Starts without errors
- Connects to Neovim successfully
- Responds to LSP lifecycle events
- Discovers markdown files in workspace
- Provides foundation for next chunk