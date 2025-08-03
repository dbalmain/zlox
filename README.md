# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## Current Status

- **Chapter 16**: Scanning on Demand - ✅ Complete
  - Complete lexical analyzer with all Lox token types
  - Interactive REPL and file execution modes
  - Proper error handling with standard Unix exit codes
  - Bounds-safe scanner implementation using end pointers

## Building and Running

```bash
# Build the project
zig build

# Run the REPL (interactive mode)
zig build run

# Run a Lox file
zig build run -- script.lox

# Run with trace output (debug VM execution)
zig build run -Dtrace=true

# Run tests
zig build test
```

## Project Structure

- `src/main.zig` - Main executable entry point with CLI interface
- `src/scanner.zig` - Lexical analyzer for tokenizing Lox source code
- `src/compiler.zig` - Compiler frontend (currently token printing)
- `src/vm.zig` - Virtual machine implementation
- `src/chunk.zig` - Bytecode chunk representation
- `src/value.zig` - Value types and operations
- `src/debug.zig` - Disassembler and debugging utilities
- `src/root.zig` - Library module exports
- `build.zig` - Zig build configuration

## Learning Goals

This implementation focuses on:
- Understanding bytecode virtual machines
- Zig language features and idioms
- Memory management in language implementations
- Performance-oriented interpreter design

## Reference

Based on "Crafting Interpreters" by Robert Nystrom - https://craftinginterpreters.com/