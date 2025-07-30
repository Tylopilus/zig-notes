# AGENTS.md - Development Guidelines

## Build/Test Commands
- `zig build` - Build the project
- `zig build run` - Build and run the project
- `zig build test` - Run all tests
- `zig test src/main.zig` - Run tests for a specific file
- `zig fmt .` - Format all Zig files

## Code Style Guidelines
- Use snake_case for variables, functions, and file names
- Use PascalCase for types, structs, and enums
- Use SCREAMING_SNAKE_CASE for constants
- Imports: Standard library first, then third-party, then local modules
- Error handling: Use Zig's error unions (`!Type`) and handle errors explicitly
- Memory management: Prefer allocators, avoid global state
- Function naming: Use verbs for functions, nouns for types
- Line length: Keep lines under 100 characters
- Indentation: 4 spaces, no tabs
- Braces: Opening brace on same line for functions/structs
- Documentation: Use `///` for public APIs, `//` for internal comments

## Testing
- Place tests in the same file as the code being tested
- Use `test "description"` blocks
- Test files should end with `_test.zig` if separate from main code